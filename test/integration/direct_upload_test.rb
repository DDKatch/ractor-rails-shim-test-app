require "test_helper"

# Direct uploads audit (RAILS_FEATURES.md #40): the server side of direct
# uploads — the ActiveStorage DirectUploadsController endpoint that mints the
# signed upload URL, and the pending-blob creation it performs. (The JS client
# side is not wired in this app — there are no javascript tags in the layout;
# documented in RAILS_FEATURES.md.)
class DirectUploadTest < ActionDispatch::IntegrationTest
  test "the direct-upload endpoint creates a blob and returns an upload URL" do
    checksum = Digest::MD5.base64digest("direct upload bytes")
    post rails_direct_uploads_path, params: {
      blob: {
        filename: "avatar.png",
        byte_size: 18,
        checksum: checksum,
        content_type: "image/png"
      }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    upload_url = body.dig("direct_upload", "url")
    assert upload_url.present?, "expected a signed upload URL under direct_upload.url in the response (got #{response.body})"
    assert_equal "avatar.png", body["filename"]

    blob = ActiveStorage::Blob.order(:id).last
    assert_equal "avatar.png", blob.filename.to_s
    assert_equal "image/png", blob.content_type
  end

  test "create_before_direct_upload! builds a pending blob server-side" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "direct.txt",
      byte_size: 11,
      content_type: "text/plain",
      checksum: Digest::MD5.base64digest("hello direct")
    )
    assert blob.persisted?
    assert_equal "direct.txt", blob.filename.to_s
    assert_predicate blob.key, :present?
  end
end
