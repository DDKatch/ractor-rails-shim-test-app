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

  # Number helpers (RAILS_FEATURES.md #23)
  test "formatted_count uses a thousands delimiter" do
    assert_equal "12,345", formatted_count(12345)
  end

  test "formatted_currency renders currency" do
    assert_equal "$9.50", formatted_currency(9.5)
  end

  test "formatted_percentage renders with one decimal" do
    assert_equal "12.3%", formatted_percentage(12.34)
  end
end
