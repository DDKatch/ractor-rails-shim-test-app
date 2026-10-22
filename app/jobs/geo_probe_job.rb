# RAILS_FEATURES.md #109: the probe job — receives a GeoPoint through the
# custom serializer's round-trip. With the :async adapter the enqueue path
# executes via the per-Ractor executor; the perform lands the point in an
# AuditLog row so an external observer can verify the deserialize side too.
class GeoProbeJob < ApplicationJob
  queue_as :default

  def perform(point)
    AuditLog.create!(action: "geo_probe",
                     metadata: { "lat" => point.lat, "lng" => point.lng })
  end
end
