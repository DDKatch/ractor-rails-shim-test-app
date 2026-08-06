Comment.delete_all
Post.delete_all
Category.delete_all
User.delete_all

# Categories
tech = Category.create!(name: "Technology", description: "Posts about technology, programming, and software development.")
life = Category.create!(name: "Life", description: "Posts about daily life, experiences, and reflections.")
random = Category.create!(name: "Random", description: "A catch-all category for uncategorized posts.")

# User
user = User.where(email: "test@example.com").first_or_create!(
  password: "password123",
  password_confirmation: "password123"
)

# Posts
5.times do |i|
  Post.create!(
    title: "Post #{i}",
    body: "Body of post #{i}. This is a longer body to meet the minimum length validation.",
    user: user,
    category: [tech, life, random].sample
  )
end

# Comments
Post.all.each do |post|
  rand(0..3).times do
    Comment.create!(
      body: "This is a comment on #{post.title}.",
      user: user,
      post: post
    )
  end
end

puts "Seeded #{Category.count} categories, #{User.count} user(s), #{Post.count} post(s), #{Comment.count} comment(s)."
puts "Login: test@example.com / password123"
