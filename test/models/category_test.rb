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

  # --- default_scope / unscoped (row 78) ----------------------------------------

  test "default_scope orders Category.all; unscoped removes it" do
    zulu = Category.create!(name: "Probe Zulu #{SecureRandom.hex(2)}")
    alpha = Category.create!(name: "Probe Alpha #{SecureRandom.hex(2)}")

    pattern = "%Probe%"

    # default_scope orders by name: alpha (created second) must come first.
    scoped_names = Category.where("name LIKE ?", pattern).map(&:name)
    assert scoped_names.index(alpha.name) < scoped_names.index(zulu.name),
           "default_scope must order by name (alpha before zulu, row 78)"

    # unscoped removes the default scope: natural (id) order puts zulu first.
    unscoped_names = Category.unscoped.where("name LIKE ?", pattern).map(&:name)
    assert unscoped_names.index(zulu.name) < unscoped_names.index(alpha.name),
           "unscoped must drop the default order (zulu before alpha, row 78)"

    alpha.destroy!
    zulu.destroy!
  end
end
