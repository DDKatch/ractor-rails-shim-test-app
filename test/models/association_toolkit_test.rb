require "test_helper"

# Associations toolkit audit (RAILS_FEATURES.md rows 66–70):
# polymorphic, STI, HABTM, has_one :through, nested attributes,
# counter caches.
class AssociationToolkitTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "assoc-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @category = Category.create!(name: "Assoc #{SecureRandom.hex(2)}")
    @post = Post.create!(title: "Assoc Post", body: "Body for the associations test, long enough.", user: @user, category: @category)
  end

  teardown do
    @user&.destroy
  end

  # --- nested attributes (row 69) --------------------------------------------

  test "nested attributes build and destroy comments through the post" do
    post = Post.create!(
      title: "Nested Post", body: "Body for nested attributes, long enough.", user: @user,
      comments_attributes: [{ body: "nested one", user: @user }, { body: "nested two", user: @user }]
    )
    assert_equal 2, post.comments.count

    first_comment = post.comments.first
    post.update!(comments_attributes: [{ id: first_comment.id, _destroy: true }])
    assert_not Comment.exists?(first_comment.id)
    assert_equal 1, post.reload.comments.count
  end

  # --- counter cache (row 70, explicit) ----------------------------------------

  test "counter_cache increments and decrements on comment lifecycle" do
    assert_equal 0, @post.reload.comments_count
    comment = @post.comments.create!(body: "count me", user: @user)
    assert_equal 1, @post.reload.comments_count
    comment.destroy
    assert_equal 0, @post.reload.comments_count
  end

  # --- polymorphic (row 66) ------------------------------------------------------

  test "polymorphic loggable holds different record types" do
    AuditLog.create!(loggable: @post, action: "post.created")
    AuditLog.create!(loggable: @user, action: "user.signed_in")

    assert_equal "Post", AuditLog.find_by(action: "post.created").loggable_type
    assert_equal @user, AuditLog.find_by(action: "user.signed_in").loggable
    assert_equal @post, AuditLog.recent.find_by(loggable_type: "Post", action: "post.created").loggable
  end

  # --- STI (row 67) ----------------------------------------------------------------

  test "STI subclasses share the vehicles table and query per-type" do
    car = Car.create!(name: "Sti Car")
    Bicycle.create!(name: "Sti Bike")

    assert_equal "Car", car.type
    assert_includes Vehicle.all.map(&:class), Car
    assert_includes Vehicle.all.map(&:class), Bicycle
    assert_not_includes Car.all.map(&:name), "Sti Bike"
    assert_includes Bicycle.all.map(&:name), "Sti Bike"
    assert_equal [car.id], Car.where(name: "Sti Car").ids
  end

  # --- HABTM (row 68) ----------------------------------------------------------------

  test "has_and_belongs_to_many links posts and tags" do
    tag = Tag.create!(name: "habtm-#{SecureRandom.hex(3)}")
    other = Tag.create!(name: "habtm-#{SecureRandom.hex(3)}")

    @post.tags << tag
    assert_includes @post.reload.tags.ids, tag.id
    assert_includes tag.reload.posts.ids, @post.id
    assert_not_includes @post.tags.ids, other.id
  end

  # --- has_one :through (row 68) -------------------------------------------------------

  test "has_one :through reaches the category from a comment" do
    comment = @post.comments.create!(body: "through comment", user: @user)
    assert_equal @category, comment.reload.category
  end

  # --- strict_loading (row 79) ----------------------------------------------------------

  test "strict_loading raises on lazy association load; includes keeps it readable" do
    strict_post = Post.strict_loading.order(:id).first
    assert_raises(ActiveRecord::StrictLoadingViolationError) { strict_post.comments.to_a }

    preloaded = Post.strict_loading.includes(:user, :comments).order(:id).first
    assert preloaded.user.nil? || preloaded.user.is_a?(User)
    preloaded.comments.to_a

    plain_post = Post.order(:id).first
    assert plain_post.comments.to_a.is_a?(Array)
  end

  # --- load_async (row 77) ---------------------------------------------------------------

  # NB: transactional tests keep created rows invisible to the async
  # executor's separate connection, so this test commits for real
  # (use_transactional_tests = false) and cleans up after itself.
  test "load_async materializes rows from the async executor" do
    self.use_transactional_tests = false
    probe = nil
    begin
      probe = Post.create!(title: "Load Async Probe #{SecureRandom.hex(2)}",
                           body: "load async probe body")
      rel = Post.where("title LIKE ?", "%Load Async Probe%").load_async
      rows = rel.to_a
      assert rows.any?, "load_async must materialize the committed rows (row 77)"
      assert_predicate rel, :loaded?
      assert rows.map(&:title).include?(probe.title)
    ensure
      probe&.destroy!
    end
  end
end
