# frozen_string_literal: true

class PendingImports::CleanupJob < ApplicationJob
  queue_as :default

  def perform
    # Expired and never claimed — purge blob + destroy record
    PendingImport.expired.where(claimed_at: nil).find_each do |pi|
      pi.file.purge if pi.file.attached?
      pi.destroy
    end

    # Claimed more than 7 days ago — destroy record but DO NOT purge the blob
    # (it's shared with the user's Import via blob reassignment). Detach first.
    PendingImport.where('claimed_at < ?', 7.days.ago).find_each do |pi|
      pi.file.detach if pi.file.attached?
      pi.destroy
    end
  end
end
