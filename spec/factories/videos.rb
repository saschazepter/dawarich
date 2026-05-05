# frozen_string_literal: true

FactoryBot.define do
  factory :video do
    association :user
    track { nil }
    start_at { 2.days.ago }
    end_at { 1.day.ago }
    status { :created }
    config { {} }
  end
end
