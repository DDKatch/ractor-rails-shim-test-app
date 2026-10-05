require "test_helper"

# Text helpers audit (RAILS_FEATURES.md row 100): pure-Ruby
# ActionView::Helpers::TextHelper methods (no Nokogiri involvement —
# highlight/excerpt/truncate/pluralize are string-level).
class TextHelpersAuditTest < ActiveSupport::TestCase
  include ActionView::Helpers::TextHelper

  test "truncate shortens with ellipsis" do
    assert_equal "he...", truncate("hello world", length: 5)
  end

  test "pluralize inflects with count" do
    assert_equal "2 comments", pluralize(2, "comment")
    assert_equal "1 comment", pluralize(1, "comment")
  end

  test "highlight wraps matches in mark" do
    assert_includes highlight("a b c", "b"), "<mark>"
  end

  test "excerpt trims around the phrase" do
    assert_equal "a b c", excerpt("a b c", "b")
  end
end
