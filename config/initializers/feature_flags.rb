# frozen_string_literal: true

# Keep the Flipper admin UI in sync with the flags the code actually reads, for
# both fresh installs and existing instances on upgrade. Guarded with `exist?`
# so it only writes when needed, and rescued so boot never fails when the
# Flipper tables aren't present yet (e.g. `db:migrate` on a brand-new database).
Rails.application.config.after_initialize do
  # Retired flags — the features shipped unconditionally.
  Flipper.remove(:poster_ordering) if Flipper.exist?(:poster_ordering)
  Flipper.remove(:posters) if Flipper.exist?(:posters)
  Flipper.remove(:stay_point_detection) if Flipper.exist?(:stay_point_detection)
rescue StandardError => e
  Rails.logger.warn("[feature_flags] could not register flags: #{e.class}: #{e.message}")
end
