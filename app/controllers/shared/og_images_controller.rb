# frozen_string_literal: true

class Shared::OgImagesController < ApplicationController
  layout false
  skip_before_action :verify_authenticity_token

  def html
    @link = SharedLink.active.find_by(id: params[:id])
    return head(:not_found) unless @link

    @private = @link.magic_phrase.present?
    @resource = @link.resource
    render :html
  end

  def show
    @link = SharedLink.active.find_by(id: params[:id])
    return head(:not_found) unless @link

    if @link.magic_phrase.blank? && @link.og_image_state == 'ready' && @link.og_image.attached?
      redirect_to rails_blob_url(@link.og_image, disposition: 'inline'), allow_other_host: false
    else
      redirect_to ActionController::Base.helpers.asset_url('og_default.png')
    end
  end
end
