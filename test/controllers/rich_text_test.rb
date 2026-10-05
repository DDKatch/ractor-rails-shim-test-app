require "test_helper"

# Action Text audit (RAILS_FEATURES.md row 120): has_rich_text write +
# render. The render path routes through rails-html-sanitizer
# (Nokogiri) — allowed in the MAIN ractor only.
class RichTextTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "rt-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @post = Post.create!(title: "Rich Post", body: "Body for the rich text audit, long enough.", user: @user)
  end

  teardown do
    @user&.destroy
  end

  test "rich text write, sanitize and render" do
    get "/features/rich_text", params: { body: "<div><b>Bold</b> intro <script>alert(1)</script></div>" }
    assert_response :success
    assert_includes response.body, "<b>Bold</b>"
    assert_not_includes response.body, "<script", "script tags must be sanitized out"
  end

  test "rich text persists on the record" do
    @post.update!(content: "<p>Second visit</p>")
    get "/features/rich_text"
    assert_response :success
    assert_includes response.body, "Second visit"
  end
end
