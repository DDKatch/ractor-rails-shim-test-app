require "test_helper"
require "rails/generators"
require "fileutils"

# Generators audit (RAILS_FEATURES.md #58): run a real generator into a
# sandboxed destination_root (never into app/).
class GeneratorsAuditTest < ActiveSupport::TestCase
  test "the helper generator writes files under a custom destination_root" do
    dest = Rails.root.join("tmp/generator_audit")
    FileUtils.rm_rf(dest)
    FileUtils.mkdir_p(dest)

    capture_io do
      Rails::Generators.invoke("helper", [ "audit_demo" ], destination_root: dest.to_s)
    end

    assert File.exist?(dest.join("app/helpers/audit_demo_helper.rb")),
           "helper generator should have written app/helpers/audit_demo_helper.rb under the destination root"
  ensure
    FileUtils.rm_rf(dest)
  end
end
