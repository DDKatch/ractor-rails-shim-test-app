# frozen_string_literal: true

# RAILS_FEATURES.md #81: abstract base for models on the `secondary` database
# (config/database.yml). `connects_to` registers a writing + a reading role, so
# the probe can also exercise `connected_to(role: :reading)`.
class SecondaryRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :secondary, reading: :secondary }
end
