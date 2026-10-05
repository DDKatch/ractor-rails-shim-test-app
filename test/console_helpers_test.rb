require "test_helper"

# Console helpers audit (RAILS_FEATURES.md #59).
class ConsoleHelpersTest < ActiveSupport::TestCase
  test "app_stats returns row counts for every audited model" do
    stats = ConsoleHelpers.app_stats
    assert_equal %i[users posts comments categories], stats.keys
    assert_kind_of Integer, stats[:posts]
  end

  test "make_user + make_post create records" do
    user = ConsoleHelpers.make_user
    post = ConsoleHelpers.make_post(user)
    assert user.persisted?
    assert_equal user.id, post.user_id
  ensure
    user&.destroy rescue nil
  end
end
