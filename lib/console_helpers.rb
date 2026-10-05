# Console helpers (RAILS_FEATURES.md #59). Included into Object from
# config/application.rb's `console` hook, so every method here is callable at
# the top level of a `bin/rails console` session (e.g. `app_stats`).
# `extend self` also exposes them as module-level methods (ConsoleHelpers.app_stats).
module ConsoleHelpers
  extend self

  def app_stats
    {
      users: User.count,
      posts: Post.count,
      comments: Comment.count,
      categories: Category.count
    }
  end

  def make_user(email = "console-#{SecureRandom.hex(4)}@example.com")
    User.create!(email: email, password: "password123")
  end

  def make_post(user, title: "Console post", body: "Created from the console via ConsoleHelpers.")
    Post.create!(user: user, title: title, body: body)
  end
end
