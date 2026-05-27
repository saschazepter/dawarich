# frozen_string_literal: true

module PendingImportClaimable
  extend ActiveSupport::Concern

  private

  def claim_pending_import_for(user)
    ticket = session.delete(:pending_import_ticket)
    return if ticket.blank?

    pending = PendingImport.claimable.find_by(claim_ticket: ticket)
    if pending
      PendingImports::Claim.new(pending, user).call
      flash[:notice] = "Importing #{pending.original_filename}... You'll see it in your dashboard shortly."
    else
      flash[:alert] = 'Your import link has expired or already been used. You can re-upload from your dashboard.'
    end
  end
end
