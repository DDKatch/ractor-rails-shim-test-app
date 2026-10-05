require "csv"

# Action Controller file downloads (RAILS_FEATURES.md #16): exercises
# `send_data` (in-memory CSV of all posts) and `send_file` (report rendered
# to disk under tmp/ then streamed back).
class DownloadsController < ApplicationController
  def posts_csv
    csv = CSV.generate(headers: true) do |out|
      out << %w[id title comments_count]
      Post.order(:id).find_each do |post|
        out << [ post.id, post.title, post.comments_count ]
      end
    end
    send_data csv, filename: "posts-#{Date.current.iso8601}.csv", type: "text/csv", disposition: "attachment"
  end

  def report
    path = Rails.root.join("tmp/generated-report.txt")
    File.write(path, <<~TEXT)
      Ractor Test App report
      Generated: #{Time.current.iso8601}
      Posts: #{Post.count}
      Users: #{User.count}
    TEXT
    send_file path, filename: "report.txt", type: "text/plain", disposition: "attachment"
  end
end
