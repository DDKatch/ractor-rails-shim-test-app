require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "valid comment" do
    comment = Comment.new(body: "Nice post!", user: users(:one), post: posts(:one))
    assert comment.valid?
  end

  test "invalid without body" do
    comment = Comment.new(user: users(:one), post: posts(:one))
    assert_not comment.valid?
    assert_includes comment.errors[:body], "can't be blank"
  end

  test "body too short" do
    comment = Comment.new(body: "x", user: users(:one), post: posts(:one))
    assert_not comment.valid?
  end

  test "body too long" do
    comment = Comment.new(body: "x" * 1001, user: users(:one), post: posts(:one))
    assert_not comment.valid?
  end

  test "belongs to user" do
    comment = comments(:one)
    assert_equal users(:one), comment.user
  end

  test "belongs to post" do
    comment = comments(:one)
    assert_equal posts(:one), comment.post
  end

  test "scope recent" do
    comments = Comment.recent
    assert comments.first.created_at >= comments.last.created_at
  end

  test "scope by_user" do
    user = users(:one)
    results = Comment.by_user(user)
    assert results.all? { |c| c.user == user }
  end
end
