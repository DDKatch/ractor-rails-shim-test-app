require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  # --- Postgres types (row 82) ------------------------------------------------

  test "jsonb metadata round-trips and containment queries work" do
    stamp = SecureRandom.hex(2)
    log = AuditLog.create!(
      action: "probe",
      metadata: { "tag" => stamp, "depth" => { "nested" => true } }
    )
    assert_equal true, log.reload.metadata["depth"]["nested"]

    found = AuditLog.where("metadata @> ?", { tag: stamp }.to_json)
    assert_equal 1, found.count
  end

  test "string-array trace_ids round-trips and ANY() queries work" do
    stamp = SecureRandom.hex(2)
    log = AuditLog.create!(action: "probe", trace_ids: [ "abc", stamp ])
    assert_equal [ "abc", stamp ], log.reload.trace_ids

    found = AuditLog.where("? = ANY(trace_ids)", stamp)
    assert_equal 1, found.count
    assert_equal [ "abc", stamp ], found.first.trace_ids
  end
end
