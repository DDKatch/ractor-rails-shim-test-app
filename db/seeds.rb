User.where(email: "test@example.com").first_or_create!(password: "password123", password_confirmation: "password123")
Post.delete_all
10.times { |i| Post.create!(title: "Post #{i}", body: "Body of post #{i}.") }
puts "Seeded #{User.count} user(s), #{Post.count} post(s)."
puts "Login: test@example.com / password123"
