# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'dawarich places rake tasks' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == 'dawarich:cleanup_suggested_places' }
  end

  after do
    Rake::Task['dawarich:cleanup_suggested_places'].reenable
    Rake::Task['dawarich:backfill_place_names'].reenable
  end

  describe 'dawarich:cleanup_suggested_places' do
    it 'enqueues OrphanCleanupJob for each user' do
      create(:user)
      create(:user)
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      expected_count = User.count

      Rake::Task['dawarich:cleanup_suggested_places'].invoke

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count do |j|
        j[:job] == Places::OrphanCleanupJob
      end).to eq(expected_count)
    end
  end

  describe 'dawarich:backfill_place_names' do
    it 'enqueues BulkNameFetchingJob once' do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      Rake::Task['dawarich:backfill_place_names'].invoke

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j[:job] == Places::BulkNameFetchingJob }).to eq(1)
    end
  end
end
