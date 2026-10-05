require_relative "application_system_test_case"

# System tests (RAILS_FEATURES.md #56): full-stack browser-style drives through
# capybara (rack_test driver — no JS).
class PostsSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      email: "system-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @post = Post.create!(title: "System Test Post", body: "Body seen by the system test.", user: @user)
  end

  teardown do
    @user&.destroy rescue nil
  end

  test "visiting the posts index shows the post" do
    visit posts_path
    assert_selector "h1", text: "Posts"
    assert_text "System Test Post"
  end

  test "signing in through the form and reading a post" do
    visit new_user_session_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

    visit post_path(@post)
    assert_selector "h1", text: "System Test Post"
  end
end
