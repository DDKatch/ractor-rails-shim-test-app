require "test_helper"

# Downloads audit (RAILS_FEATURES.md #16): send_data + send_file.
class DownloadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "dl-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @post = Post.create!(title: "Download Post", body: "Body for the downloads audit.", user: @user)
  end

  teardown do
    @user&.destroy rescue nil
  end

  test "posts_csv streams a CSV attachment via send_data" do
    get posts_csv_download_path
    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"].to_s)
    assert_match(/id,title,comments_count/, response.body)
    assert_match(/Download Post/, response.body)
  end

  test "report streams a file from disk via send_file" do
    get report_download_path
    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"].to_s)
    assert_match(/Ractor Test App report/, response.body)
    assert response.body.length > 0, "send_file response body must not be empty"
  end
end
