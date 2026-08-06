require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "valid post" do
    post = Post.new(title: "Valid Title", body: "This is a valid body with enough characters.")
    assert post.valid?
  end

  test "invalid without title" do
    post = Post.new(body: "This is a valid body with enough characters.")
    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "invalid without body" do
    post = Post.new(title: "Valid Title")
    assert_not post.valid?
    assert_includes post.errors[:body], "can't be blank"
  end

  test "title too short" do
    post = Post.new(title: "AB", body: "This is a valid body with enough characters.")
    assert_not post.valid?
    assert_includes post.errors[:title], "is too short (minimum is 3 characters)"
  end

  test "body too short" do
    post = Post.new(title: "Valid Title", body: "Short")
    assert_not post.valid?
    assert_includes post.errors[:body], "is too short (minimum is 10 characters)"
  end

  test "title is normalized on save" do
    post = Post.create!(title: "  hello world  ", body: "This is a valid body with enough characters.")
    assert_equal "Hello World", post.reload.title
  end

  test "belongs to user optionally" do
    post = Post.new(title: "Test", body: "Valid body here.")
    assert_nil post.user
  end

  test "belongs to category optionally" do
    post = Post.new(title: "Test", body: "Valid body here.")
    assert_nil post.category
  end

  test "has many comments" do
    post = posts(:one)
    assert_respond_to post, :comments
  end

  test "scope recent orders by created_at desc" do
    posts = Post.recent
    assert posts.first.created_at >= posts.last.created_at
  end

  test "scope by_title searches" do
    post = Post.create!(title: "Ruby Tips", body: "Useful Ruby tips and tricks.", user: users(:one))
    results = Post.by_title("ruby")
    assert_includes results, post
  end

  test "destroying post destroys comments" do
    post = posts(:one)
    comment_count = post.comments.count
    assert comment_count > 0, "Fixtures should have comments"
    assert_difference "Comment.count", -comment_count do
      post.destroy
    end
  end
end
