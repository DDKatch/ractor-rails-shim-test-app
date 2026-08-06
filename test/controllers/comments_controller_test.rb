require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @post = posts(:one)
    sign_in users(:one)
  end

  test "create comment" do
    assert_difference "Comment.count", 1 do
      post post_comments_path(@post), params: { comment: { body: "Great post!" } }
    end
    assert_redirected_to @post
  end

  test "destroy comment" do
    comment = comments(:one)
    assert_difference "Comment.count", -1 do
      delete post_comment_path(@post, comment)
    end
    assert_redirected_to @post
  end

  test "create requires authentication" do
    sign_out users(:one)
    assert_no_difference "Comment.count" do
      post post_comments_path(@post), params: { comment: { body: "Comment" } }
    end
    assert_response :redirect
  end
end
