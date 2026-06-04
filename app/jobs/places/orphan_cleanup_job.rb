# frozen_string_literal: true

class Places::OrphanCleanupJob < ApplicationJob
  queue_as :places
  BATCH = 500

  # Pass a user id to drain that user's orphan suggested places, or nil to drain
  # ownerless (user_id IS NULL) orphans that no per-user pass can reach.
  def perform(user_id)
    if user_id.nil?
      drain('ownerless', ownerless_victims_sql, [name_bind])
      return
    end

    return unless User.exists?(id: user_id)

    drain("user=#{user_id}", user_victims_sql, victim_binds(user_id))
  end

  private

  def drain(scope, sql, binds)
    total = 0
    loop do
      deleted = delete_batch(sql, binds)
      break if deleted.zero?

      total += deleted
      Rails.logger.info("[OrphanCleanup] #{scope} batch=#{deleted} total=#{total}")
      sleep 0.05
    end
  end

  def delete_batch(sql, binds)
    conn = Place.connection
    deleted = 0

    conn.transaction do
      victim_ids = conn.exec_query(sql, 'OrphanCleanup victims', binds).rows.map { |r| r[0] }
      break if victim_ids.empty?

      PlaceVisit.where(place_id: victim_ids).delete_all
      deleted = Place.where(id: victim_ids).delete_all
    end

    deleted
  end

  def user_victims_sql
    victims_sql('p.user_id = $1', '$2')
  end

  def ownerless_victims_sql
    victims_sql('p.user_id IS NULL', '$1')
  end

  def victims_sql(user_predicate, name_placeholder)
    <<~SQL.squish
      SELECT p.id
      FROM places p
      LEFT JOIN visits v   ON v.place_id = p.id
      LEFT JOIN taggings t ON t.taggable_id = p.id AND t.taggable_type = 'Place'
      WHERE #{user_predicate}
        AND p.source = #{Place.sources[:photon]}
        AND p.name = #{name_placeholder}
        AND (p.note IS NULL OR p.note = '')
        AND v.id IS NULL
        AND t.id IS NULL
      LIMIT #{BATCH}
    SQL
  end

  def victim_binds(user_id)
    [
      ActiveRecord::Relation::QueryAttribute.new('user_id', user_id, ActiveRecord::Type::Integer.new),
      name_bind
    ]
  end

  def name_bind
    ActiveRecord::Relation::QueryAttribute.new('name', Place::DEFAULT_NAME, ActiveRecord::Type::String.new)
  end
end
