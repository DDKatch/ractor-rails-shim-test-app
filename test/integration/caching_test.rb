require "test_helper"

# Fragment / russian-doll / low-level caching + invalidation audit
# (RAILS_FEATURES.md #45-#48). Test env uses :memory_store with
# perform_caching on (see config/environments/test.rb).
class CachingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @user = User.create!(email: "cache-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @post = Post.create!(title: "Cached Post", body: "Body written for the caching audit.", user: @user)
  end

  teardown do
    Rails.cache.clear
    @user&.destroy rescue nil
  end

  test "fragment caching writes on first render and hits on the second" do
    get posts_path
    assert_response :success

    events = with_cache_event_counter do
      get posts_path
    end
    assert_response :success
    assert_operator events["cache_read"], :>=, 1,
                    "expected fragment reads on the second render (events: #{events.inspect})"
    assert_equal 0, events["cache_write"],
                 "the second render must be served entirely from the fragment cache (events: #{events.inspect})"
  end

  test "russian doll: a new comment busts the post fragments but sibling inner fragments still hit" do
    Comment.create!(body: "first comment", post: @post, user: @user)
    get post_path(@post) # warm: outer + "first comment" inner fragments cached

    sibling = Post.create!(title: "Sibling Post", body: "Sibling body for the caching audit.", user: @user)
    get post_path(sibling) # warm sibling fragments

    events = with_cache_event_counter do
      travel 1.second do
        Comment.create!(body: "busting comment", post: @post, user: @user)
      end
      get post_path(@post)
    end
    assert_response :success
    # @post's outer fragment was busted (touch through comment → post.updated_at)
    # and re-rendered (cache_write), while the surviving inner fragments
    # ("first comment") still hit the cache (reads without writes).
    assert_operator events["cache_write"], :>=, 1,
                    "expected at least one busted fragment to re-render after the comment create (events: #{events.inspect})"
    assert_operator events["cache_read"], :>, events["cache_write"],
                    "expected inner russian-doll fragments to still hit after the outer bust (events: #{events.inspect})"
    assert_match "first comment", response.body
    assert_match "busting comment", response.body
  end

  test "low-level Rails.cache.fetch caches the index total" do
    get posts_path
    assert_response :success

    assert_nothing_raised do
      Rails.cache.fetch("posts/index/total_count") { flunk "low-level cache should have been warmed by the index" }
    end
  end

  test "touch invalidation: updating a post changes its cache_key" do
    old_key = @post.cache_key_with_version
    @post.update!(body: "Updated body invalidates cached fragments.")
    assert_not_equal old_key, @post.reload.cache_key_with_version,
                     "updating a post must change its cache key (fragment bust)"
  end

  test "touch invalidation: creating a comment touches the post (sweeper replacement)" do
    old_key = @post.cache_key_with_version
    travel 1.second do
      Comment.create!(body: "touch through", post: @post, user: @user)
    end
    assert_not_equal old_key, @post.reload.cache_key_with_version,
                     "comment create must touch the post (Rails 8 removed sweepers; touch-based invalidation replaces them)"
  end

  private

  # Counts ActiveSupport cache instrumentation events fired inside the block.
  # Event names: cache_read / cache_generate / cache_fetch_hit / cache_write /
  # cache_delete (.active_support).
  def with_cache_event_counter
    events = Hash.new(0)
    subscriber = ActiveSupport::Notifications.subscribe(/^cache/) do |name, *_args|
      events[name.to_s.split(".").first] += 1
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    events
  end
end
