require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "valid category" do
    category = Category.new(name: "Science", description: "Science posts")
    assert category.valid?
  end

  test "invalid without name" do
    category = Category.new(description: "No name")
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Category.create!(name: "Unique", description: "Test")
    duplicate = Category.new(name: "Unique", description: "Another")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "name is normalized" do
    category = Category.create!(name: "  test cat  ", description: "Test")
    assert_equal "Test Cat", category.reload.name
  end

  test "scope alphabetical" do
    categories = Category.alphabetical
    assert categories.first.name <= categories.last.name
  end

  test "has many posts" do
    category = Category.new(name: "Test")
    assert_respond_to category, :posts
  end
end
