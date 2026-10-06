# Rake tasks audit (RAILS_FEATURES.md #57): custom app rake tasks, exercised
# by test/tasks/posts_task_test.rb. Batch processing (RAILS_FEATURES.md #62):
# `stats` iterates posts with find_each and reports the batched title count.
namespace :posts do
  desc "Print post/comment/user counts + the find_each-batched title census"
  task stats: :environment do
    titled = 0
    Post.find_each(batch_size: 100) { |post| titled += 1 if post.title.present? }
    puts "Posts: #{Post.count}, Comments: #{Comment.count}, Users: #{User.count}, Titled: #{titled}"
  end

  desc "Recount the denormalized comments_count column for every post"
  task recount_comments: :environment do
    Post.find_each { |post| Post.reset_counters(post.id, :comments) }
    puts "Recounted comments_count for #{Post.count} posts"
  end
end
