# RAILS_FEATURES.md #109: a custom, non-ActiveModel argument type for the
# custom-serializer probe. Plain Ruby Struct subclass (no AR) — eager-loaded
# with the app, so the shim's make_shareable freeze covers it and workers can
# construct/inspect instances.
GeoPoint = Struct.new(:lat, :lng) do
  def to_s
    format("(%.4f, %.4f)", lat, lng)
  end
end
