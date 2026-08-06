require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid user" do
    user = User.new(email: "test@test.com", password: "password123", password_confirmation: "password123")
    assert user.valid?
  end

  test "invalid without email" do
    user = User.new(password: "password123", password_confirmation: "password123")
    assert_not user.valid?
  end

  test "has many posts" do
    user = users(:one)
    assert_respond_to user, :posts
  end

  test "has many comments" do
    user = users(:one)
    assert_respond_to user, :comments
  end

  test "scope recent orders by created_at desc" do
    users = User.recent
    assert users.first.created_at >= users.last.created_at
  end
end
