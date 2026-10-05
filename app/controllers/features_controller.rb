# Probe controller for the full Rails-guides sweep (RAILS_FEATURES.md
# rows 89, 91, 92, 93): conditional GET, cookie jars, head, HTTP basic
# auth. Each action is dispatched by test/integration/ractor_server_test.rb
# in :ractor mode as well.
class FeaturesController < ApplicationController
  # RAILS_FEATURES.md #92: HTTP basic auth.
  http_basic_authenticate_with name: "audit", password: "secret", only: :basic_auth

  # RAILS_FEATURES.md #91: conditional GET via stale? (ETag +
  # Last-Modified from the record's cache_key). stale? issues the 304
  # itself and returns false when the client's copy is still fresh.
  def conditional_get
    post = Post.order(:id).first
    return head(:not_found) unless post

    head :ok if stale?(post, last_modified: post.updated_at)
  end

  # RAILS_FEATURES.md #93: signed / encrypted / permanent cookie jars
  # (MessageVerifier / MessageEncryptor round-trips).
  def cookie_jar
    marker = Time.current.to_i
    cookies.signed[:audit_signed] = "sig-#{marker}"
    cookies.encrypted[:audit_encrypted] = { value: "enc-#{marker}", expires: 1.hour }
    render json: { signed_read: cookies.signed[:audit_signed], encrypted_read: cookies.encrypted[:audit_encrypted] }
  end

  # RAILS_FEATURES.md #89: head with a custom status.
  def head_probe
    head :no_content
  end

  # RAILS_FEATURES.md #92: authenticated variant.
  def basic_auth
    render json: { basic_auth: true }
  end
end
