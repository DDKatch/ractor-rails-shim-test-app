require "test_helper"

# Active Record toolkit audit (RAILS_FEATURES.md rows 62–65, 70, 73–76):
# enum, dirty tracking, batch processing, aggregates/grouping,
# insert_all/upsert_all, signed_id round-trip.
class ActiveRecordToolkitTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "toolkit-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @category = Category.create!(name: "Toolkit #{SecureRandom.hex(2)}")
    @post = Post.create!(title: "Toolkit Post", body: "Body for the toolkit test, long enough.", user: @user, category: @category)
  end

  teardown do
    @user&.destroy
  end

  # --- enum (row 65) ---------------------------------------------------------

  test "enum: default value, scopes, and invalid-value validation" do
    assert_equal "draft", @post.state
    @post.moderated!
    assert_predicate @post.reload, :moderated?
    assert_includes Post.moderated.ids, @post.id
    assert_raises(ArgumentError) { @post.state = 42 }
    assert_raises(ArgumentError) { @post.state = "bogus" }
  end

  # --- dirty tracking (row 73) ----------------------------------------------

  test "dirty tracking: new mutations and saved_changes" do
    assert_not_predicate @post, :changed?
    @post.title = "Dirty Title"
    assert_predicate @post, :changed?
    assert_equal "Toolkit Post", @post.changes["title"]&.first
    @post.save!
    assert_empty @post.changed
    assert_equal "Toolkit Post", @post.saved_changes["title"]&.first
  end

  # --- batch processing (row 62) --------------------------------------------

  test "find_each and in_batches iterate every post" do
    titles = []
    Post.find_each(batch_size: 1) { |p| titles << p.title }
    assert_includes titles, @post.reload.title

    Post.in_batches(of: 1) do |batch|
      assert_kind_of ActiveRecord::Relation, batch
    end
  end

  # --- aggregates & grouping (rows 63–64) ------------------------------------

  test "aggregates: count/sum/average/minimum/maximum" do
    assert_operator Post.count, :>=, 1
    assert_kind_of BigDecimal, Post.average(:comments_count)
    assert_kind_of Integer, Post.minimum(:comments_count)
    assert_kind_of Integer, Post.maximum(:comments_count)
    assert_kind_of Integer, Post.sum(:comments_count)
  end

  test "grouping: group/having/distinct + pluck/pick/ids/exists?" do
    @post.comments.create!(body: "agg comment", user: @user)
    grouped = Comment.group(:post_id).count
    assert_equal 1, grouped[@post.id]

    with_comments = Comment.group(:post_id).having("COUNT(id) > 0").count
    assert_equal 1, with_comments[@post.id]

    assert_includes Post.distinct.pluck(:state), "draft"
    assert_equal Post.first.title, Post.order(:id).pick(:title)
    assert_includes Post.ids, @post.id
    assert Post.exists?(@post.id)
    assert_not Post.where(id: -1).exists?
  end

  # --- insert_all / upsert_all (row 76) --------------------------------------

  test "insert_all and upsert_all bulk-write" do
    now = Time.current
    rows = Array.new(3) do |i|
      { title: "Bulk #{i} #{SecureRandom.hex(2)}", body: "Bulk body #{i} long enough for validation bypass.",
        state: 0, comments_count: 0, user_id: @user.id, created_at: now, updated_at: now }
    end
    assert_equal 3, Post.insert_all!(rows).count

    upsert_rows = rows.map { |r| r.merge(title: "Upserted #{r[:title]}") }
    assert_equal 3, Post.upsert_all(upsert_rows, unique_by: :id).count
  end

  # --- signed_id (row 75, explicit) -------------------------------------------

  test "signed_id round-trips via find_signed" do
    sig = @post.signed_id(expires_in: 1.hour)
    assert_equal @post.id, Post.find_signed(sig)&.id
    assert_nil Post.find_signed("totally-invalid-signature")
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      Post.find_signed!("totally-invalid-signature")
    end
  end
end
