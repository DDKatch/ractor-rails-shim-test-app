# RAILS_FEATURES.md #109: register the custom GeoPoint serializer with
# ActiveJob. add_serializers is the Rails 7+ public API; the resulting
# singleton serializer instances live in a class-ivar Set that the shim's
# make_shareable freeze covers, so worker-side argument serialization finds
# it without an IsolationError.
#
# Initializers run BEFORE Zeitwerk autoload/eager-load, so the serializer
# (and its model) are required explicitly here.
require Rails.root.join("app/models/geo_point")
require Rails.root.join("app/serializers/geo_point_serializer")

ActiveJob::Serializers.add_serializers([ GeoPointSerializer ])
