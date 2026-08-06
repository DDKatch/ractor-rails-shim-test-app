require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "page_title" do
    result = page_title("Test")
    assert_kind_of ActiveSupport::SafeBuffer, result
  end

  test "time_ago returns string" do
    result = time_ago(Time.current)
    assert_kind_of String, result
  end

  test "time_ago with nil" do
    result = time_ago(nil)
    assert_equal "just now", result
  end

  test "badge_count with zero" do
    result = badge_count(0)
    assert_equal "", result
  end

  test "badge_count with number" do
    result = badge_count(5)
    assert_includes result, "5"
  end

  test "truncate_with_length" do
    result = truncate_with_length("Hello World", length: 5)
    assert result.length <= 5
  end
end
