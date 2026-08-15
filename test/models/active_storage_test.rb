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
end