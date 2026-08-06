require "test_helper"

class ApiPostsControllerTest < ActionDispatch::IntegrationTest
  test "index returns json" do
    get api_posts_path, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert data.first.key?("title")
  end

  test "show returns json" do
    get api_post_path(posts(:one)), as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal posts(:one).title, data["title"]
  end

  test "create persists post" do
    assert_difference "Post.count", 1 do
      post api_posts_path, params: { post: { title: "API Post", body: "Created via JSON API" } }, as: :json
    end
    assert_response :created
    data = JSON.parse(response.body)
    assert_equal "Api Post", data["title"]
  end

  test "update modifies post" do
    patch api_post_path(posts(:one)), params: { post: { title: "Updated Title" } }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "Updated Title", data["title"]
  end

  test "destroy removes post" do
    assert_difference "Post.count", -1 do
      delete api_post_path(posts(:one)), as: :json
    end
    assert_response :no_content
  end

  test "create with invalid data returns errors" do
    post api_posts_path, params: { post: { title: "", body: "" } }, as: :json
    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert data.key?("errors")
  end
end
