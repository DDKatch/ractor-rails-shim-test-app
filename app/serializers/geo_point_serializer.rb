# RAILS_FEATURES.md #109: custom ActiveJob argument serializer for GeoPoint.
# Registered at boot via config/initializers/geo_serializers.rb
# (ActiveJob::Serializers.add_serializers). Stateless — the singleton
# instance is created by add_serializers (`.instance`) and deep-frozen with
# the app graph, so the workers' serializer lookup reads shareable state.
class GeoPointSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize(point)
    super("lat" => point.lat, "lng" => point.lng)
  end

  def deserialize(hash)
    GeoPoint.new(hash["lat"], hash["lng"])
  end

  def klass
    GeoPoint
  end
end
