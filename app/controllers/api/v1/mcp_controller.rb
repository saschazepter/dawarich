# frozen_string_literal: true

module Api
  module V1
    class McpController < ApiController
      MAX_BATCH_SIZE = 20

      before_action :ensure_mcp_enabled
      before_action :ensure_batch_within_limit

      def handle
        status, headers, body = transport.handle_request(request)

        headers.each { |key, value| response.set_header(key, value) }
        self.status = status
        self.response_body = body
      end

      private

      def ensure_mcp_enabled
        return if Flipper.enabled?(:mcp_server, current_api_user)

        render json: { error: 'MCP endpoint is not enabled' }, status: :not_found
      end

      def ensure_batch_within_limit
        return unless batch_size > MAX_BATCH_SIZE

        render json: { error: "Batch requests are limited to #{MAX_BATCH_SIZE} entries" },
               status: :payload_too_large
      end

      # A top-level JSON array body is exposed by Rails under the `_json` key.
      def batch_size
        payload = request.request_parameters
        return payload.size if payload.is_a?(Array)

        wrapped = payload['_json']
        wrapped.is_a?(Array) ? wrapped.size : 0
      end

      def transport
        server = MCP::Server.new(
          name: 'dawarich',
          title: 'Dawarich',
          version: APP_VERSION,
          instructions: 'Use these read-only tools to inspect the authenticated users own location history.',
          tools: [Mcp::GetTimelineTool, Mcp::GetLatestLocationTool],
          server_context: { user: current_api_user },
          configuration: mcp_configuration
        )

        MCP::Server::Transports::StreamableHTTPTransport.new(
          server,
          stateless: true,
          enable_json_response: true,
          allowed_hosts: allowed_hosts
        )
      end

      def allowed_hosts
        ENV.fetch('APPLICATION_HOSTS', 'localhost').split(',').map(&:strip).reject(&:blank?)
      end

      def mcp_configuration
        MCP::Configuration.new(validate_tool_call_results: true).tap do |configuration|
          configuration.exception_reporter = lambda do |exception, _context|
            ExceptionReporter.call(exception, 'MCP request failed')
          end
        end
      end
    end
  end
end
