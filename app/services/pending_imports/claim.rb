# frozen_string_literal: true

module PendingImports
  class Claim
    def initialize(pending_import, user)
      @pending = pending_import
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        import = @user.imports.build(name: unique_name)
        import.file.attach(@pending.file.blob)
        import.save!

        @pending.update!(
          claimed_at: Time.current,
          claimed_by_user_id: @user.id
        )

        import
      end
    end

    private

    def unique_name
      base = @pending.original_filename
      return base unless @user.imports.exists?(name: base)

      basename = File.basename(base, File.extname(base))
      ext = File.extname(base)
      "#{basename}_#{Time.current.strftime('%Y%m%d_%H%M%S')}#{ext}"
    end
  end
end
