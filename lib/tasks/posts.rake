# Rake tasks audit (RAILS_FEATURES.md #57): custom app rake tasks, exercised
# by test/tasks/posts_task_test.rb.
namespace :posts do
  desc "Print post/comment/user counts"
  task stats: :environment do
    puts "Posts: #{Post.count}, Comments: #{Comment.count}, Users: #{User.count}"
  end

  desc "Recount the denormalized comments_count column for every post"
  task recount_comments: :environment do
    Post.find_each { |post| Post.reset_counters(post.id, :comments) }
    puts "Recounted comments_count for #{Post.count} posts"
  end
end
