require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "index page loads" do
    get posts_path
    assert_response :success
    assert_includes response.body, "Posts"
  end

  test "show page loads" do
    get post_path(posts(:one))
    assert_response :success
  end

  test "new requires authentication" do
    get new_post_path
    assert_response :redirect
    assert_includes response.location, "sign_in"
  end

  test "create requires authentication" do
    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Test", body: "Test body here" } }
    end
    assert_response :redirect
  end

  test "edit requires authentication" do
    get edit_post_path(posts(:one))
    assert_response :redirect
  end

  test "destroy requires authentication" do
    assert_no_difference "Post.count" do
      delete post_path(posts(:one))
    end
    assert_response :redirect
  end

  test "search by title" do
    get posts_path(q: "First")
    assert_response :success
    assert_includes response.body, "First Post"
  end

  test "posts_plain loads" do
    get posts_plain_path
    assert_response :success
  end
end
