require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "index page loads" do
    get categories_path
    assert_response :success
    assert_includes response.body, "Technology"
  end

  test "show page loads" do
    get category_path(categories(:tech))
    assert_response :success
  end

  test "new requires authentication" do
    get new_category_path
    assert_response :redirect
    assert_includes response.location, "sign_in"
  end

  test "create requires authentication" do
    assert_no_difference "Category.count" do
      post categories_path, params: { category: { name: "Test", description: "Test" } }
    end
    assert_response :redirect
  end

  test "edit requires authentication" do
    get edit_category_path(categories(:tech))
    assert_response :redirect
  end

  test "update requires authentication" do
    patch category_path(categories(:tech)), params: { category: { name: "Updated" } }
    assert_response :redirect
  end

  test "destroy requires authentication" do
    assert_no_difference "Category.count" do
      delete category_path(categories(:tech))
    end
    assert_response :redirect
  end
end
