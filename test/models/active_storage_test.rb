require "test_helper"

class ActiveStorageTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "avatar-test-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  teardown do
    @user&.avatar&.purge_later rescue nil
    @user&.destroy rescue nil
  end

  test "user responds to avatar" do
    assert_respond_to @user, :avatar
  end

  test "avatar is not attached by default" do
    assert_not @user.avatar.attached?
  end

  test "attach avatar from io" do
    @user.avatar.attach(
      io: StringIO.new("hello avatar"),
      filename: "avatar.txt",
      content_type: "text/plain"
    )

    assert @user.avatar.attached?
    assert_equal "avatar.txt", @user.avatar.blob.filename.to_s
    assert_equal 12, @user.avatar.blob.byte_size
    assert_equal "text/plain", @user.avatar.blob.content_type
  end

  test "attach avatar from fixture file" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("PNG fake content for test"),
      "image/png",
      original_filename: "avatar.png"
    )
    @user.avatar.attach(file)

    assert @user.avatar.attached?
    assert_equal "avatar.png", @user.avatar.blob.filename.to_s
    assert_equal "image/png", @user.avatar.blob.content_type
  end

  test "reattach replaces previous avatar" do
    @user.avatar.attach(
      io: StringIO.new("first"),
      filename: "first.txt",
      content_type: "text/plain"
    )
    first_blob = @user.avatar.blob

    @user.avatar.attach(
      io: StringIO.new("second"),
      filename: "second.txt",
      content_type: "text/plain"
    )

    assert @user.avatar.attached?
    assert_equal "second.txt", @user.avatar.blob.filename.to_s
    assert_not_equal first_blob.id, @user.avatar.blob.id
  end

  test "purge removes avatar" do
    @user.avatar.attach(
      io: StringIO.new("purge me"),
      filename: "purge.txt",
      content_type: "text/plain"
    )
    assert @user.avatar.attached?

    @user.avatar.purge
    assert_not @user.avatar.attached?
  end

  test "avatar persists across reload" do
    @user.avatar.attach(
      io: StringIO.new("persist me"),
      filename: "persist.txt",
      content_type: "text/plain"
    )

    reloaded = User.find(@user.id)
    assert reloaded.avatar.attached?
    assert_equal "persist.txt", reloaded.avatar.blob.filename.to_s
  end

  test "blob checksum is computed" do
    content = "checksum test content"
    @user.avatar.attach(
      io: StringIO.new(content),
      filename: "checksum.txt",
      content_type: "text/plain"
    )

    expected = Digest::MD5.base64digest(content)
    assert_equal expected, @user.avatar.blob.checksum
  end

  test "avatar variant generates a processed thumbnail" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/avatar.png"), "image/png"
    )
    @user.avatar.attach(file)
    assert @user.avatar.attached?
    original_size = @user.avatar.blob.byte_size

    # Variants audit (RAILS_FEATURES.md #39): process a 100x100 thumbnail via
    # the mini_magick processor (pinned in config/application.rb).
    variant = @user.avatar_thumbnail

    # The processed variant's TRANSFORMED blob is `variant.image` (`variant.blob`
    # is the original blob the variant derives from).
    assert variant.image.present?
    assert variant.image.byte_size.positive?
    assert_not_equal original_size, variant.image.byte_size,
                     "the processed variant should be re-encoded (different byte size than the original)"
  end

  test "variant processing records the variation" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/avatar.png"), "image/png"
    )
    @user.avatar.attach(file)

    variant = @user.avatar_thumbnail
    # VariantRecord references the ORIGINAL blob the variant derives from.
    record = ActiveStorage::VariantRecord.find_by(blob_id: variant.blob.id)
    assert_not_nil record, "processing a variant must record the variation"
  end

  test "multiple users can have avatars independently" do
    other = User.create!(
      email: "other-avatar-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @user.avatar.attach(
      io: StringIO.new("user1 avatar"),
      filename: "u1.txt",
      content_type: "text/plain"
    )
    other.avatar.attach(
      io: StringIO.new("user2 avatar"),
      filename: "u2.txt",
      content_type: "text/plain"
    )

    assert_equal "u1.txt", @user.reload.avatar.blob.filename.to_s
    assert_equal "u2.txt", other.reload.avatar.blob.filename.to_s

    other.avatar.purge rescue nil
    other.destroy rescue nil
  end

  # --- rows 125 + 126 + 127 (main mode) -------------------------------------

  test "public service resolves and routes upload/download (row 125)" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("public blob bytes"),
      filename: "public.txt",
      content_type: "text/plain",
      service_name: "test_public"
    )

    assert_equal "test_public", blob.service_name
    assert ActiveStorage::Blob.services.fetch(:test_public).public?,
           "the test_public disk service must be public (row 125)"
    assert_equal "public blob bytes", blob.download, "download must round-trip from the public service (row 127)"
    assert_not_equal ActiveStorage::Blob.service.root.to_s, blob.service.root.to_s,
                     "the public service must use its own storage root"
  ensure
    blob&.purge rescue nil
  end

  test "analyze marks a text blob analyzed via NullAnalyzer (row 126)" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("plain text to analyze"),
      filename: "notes.txt",
      content_type: "text/plain"
    )
    refute blob.analyzed?
    blob.analyze
    assert blob.reload.analyzed?, "analyze must mark the blob analyzed (row 126)"
  ensure
    blob&.purge rescue nil
  end
end
