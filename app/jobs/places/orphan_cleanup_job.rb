# frozen_string_literal: true

class Places::OrphanCleanupJob < ApplicationJob
  queue_as :default
  BATCH = 500

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    total = 0
    loop do
      deleted = delete_batch(user)
      break if deleted.zero?

      total += deleted
      Rails.logger.info("[OrphanCleanup] user=#{user.id} batch=#{deleted} total=#{total}")
      sleep 0.05
    end
  end

  private

  def delete_batch(user)
    conn = Place.connection
    deleted = 0

    conn.transaction do
      victim_ids = conn.exec_query(victims_sql, 'OrphanCleanup victims', victim_binds(user.id)).rows.map { |r| r[0] }
      break if victim_ids.empty?

      PlaceVisit.where(place_id: victim_ids).delete_all
      deleted = Place.where(id: victim_ids).delete_all
    end

    deleted
  end

  def victims_sql
    <<~SQL.squish
      SELECT p.id
      FROM places p
      LEFT JOIN visits v   ON v.place_id = p.id
      LEFT JOIN taggings t ON t.taggable_id = p.id AND t.taggable_type = 'Place'
      WHERE p.user_id = $1
        AND p.source = #{Place.sources[:photon]}
        AND p.name = '#{Place::DEFAULT_NAME}'
        AND (p.note IS NULL OR p.note = '')
        AND v.id IS NULL
        AND t.id IS NULL
      LIMIT #{BATCH}
    SQL
  end

  def victim_binds(user_id)
    [ActiveRecord::Relation::QueryAttribute.new('user_id', user_id, ActiveRecord::Type::Integer.new)]
  end
end
