require "test_helper"

# Action Controller probes (RAILS_FEATURES.md rows 89, 91, 92, 93, 94):
# conditional GET, cookie jars, head, HTTP basic auth, /up health endpoint.
class FeaturesControllerTest < ActionDispatch::IntegrationTest
  test "conditional_get returns 200 with ETag, then 304 on If-None-Match" do
    get "/features/conditional_get"
    assert_response :success
    etag = response.headers["ETag"]
    assert_not_nil etag, "expected an ETag header from fresh_when"

    get "/features/conditional_get", headers: { "HTTP_IF_NONE_MATCH" => etag }
    assert_response :not_modified
  end

  test "cookie jars round-trip signed and encrypted values" do
    get "/features/cookie_jar"
    assert_response :success
    body = JSON.parse(response.body)

    assert_not_empty body["signed_read"], "signed cookie did not round-trip"
    assert_match(/\Asig-\d+\z/, body["signed_read"])
    assert_match(/\Aenc-\d+\z/, body["encrypted_read"], "encrypted cookie did not decrypt back")
  end

  test "head probe returns 204 with an empty body" do
    get "/features/head"
    assert_response :no_content
    assert_empty response.body
  end

  test "basic auth rejects wrong credentials and accepts correct ones" do
    get "/features/basic_auth"
    assert_response :unauthorized

    get "/features/basic_auth", headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("audit", "secret") }
    assert_response :success
    assert_equal true, JSON.parse(response.body)["basic_auth"]
  end

  test "/up health endpoint answers 200" do
    get rails_health_check_path
    assert_response :success
  end

  test "form_probe renders collection_select, date_select, file_field and the error wrapper" do
    get "/features/form_probe"
    assert_response :success
    assert_select "select[name='post[category_id]']"
    assert_select "select[name^='post[scheduled_at']"
    assert_select "input[type='file'][name='post[attachment]']"
    assert_select "div.field_with_errors textarea#post_body"
  end

  test "form_echo echoes submitted values including the uploaded file" do
    post "/features/form_echo",
         params: {
           post: {
             title: "Echo Title", category_id: "1", scheduled_at: "2026-10-06 10:00",
             attachment: fixture_file_upload("avatar.png", "image/png")
           }
         }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Echo Title", body["title"]
    assert_equal "avatar.png", body.dig("attachment", "filename")
    assert_operator body.dig("attachment", "byte_size"), :>, 0
  end
end
