require "test_helper"

class AuditArchiveTest < ActiveSupport::TestCase
  # --- advanced migrations (row 83) -------------------------------------

  test "creates with a valid FK and jsonb payload" do
    archive = AuditArchive.create!(
      label: "audit #{SecureRandom.hex(2)}",
      post: posts(:one),
      payload: { "action" => "probe", "depth" => 2 }
    )
    assert_predicate archive, :persisted?
    assert_equal "probe", archive.payload["action"]
  end

  test "FK constraint rejects a missing post" do
    error = assert_raises(ActiveRecord::InvalidForeignKey) do
      AuditArchive.create!(label: "orphan", post_id: -42)
    end
    assert_match(/foreign key/i, error.message)
  end

  test "check constraint rejects an empty label (validations bypassed)" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      archive = AuditArchive.new(label: "")
      archive.save(validate: false)
    end
    assert_match(/audit_archives_label_check/, error.message)
  end

  test "jsonb containment query finds the archive" do
    stamp = SecureRandom.hex(2)
    AuditArchive.create!(label: "jsonb #{stamp}", payload: { "tag" => stamp, "n" => 1 })

    found = AuditArchive.where("payload @> ?", { tag: stamp }.to_json)
    assert_equal 1, found.count
    assert_equal 1, found.first.payload["n"]
  end
end
