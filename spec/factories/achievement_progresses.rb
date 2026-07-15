# frozen_string_literal: true

FactoryBot.define do
  factory :achievement_progress, class: 'Achievements::Progress' do
    user
    achievement_key { 'explorer_germany' }
  end
end
