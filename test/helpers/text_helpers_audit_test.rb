require "test_helper"

# Text helpers audit (RAILS_FEATURES.md row 100): truncate/pluralize/
# highlight/excerpt are string-level in main mode. NB: highlight DOES run
# sanitize by default (Nokogiri) — the worker-side kino probe passes
# sanitize: false because sanitize is ⛔ in workers (row 120).
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
