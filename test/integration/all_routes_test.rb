# frozen_string_literal: true

require "test_helper"
require "securerandom"

# Visits every routable action in the dummy app and fails loudly if any of them
# raises an exception or returns a server error (>= 500). This turns runtime /
# Ractor-compatibility errors that would otherwise only show up in logs into
# concrete, reproducible test failures with the offending route + backtrace.
#
# The dummy app's committed fixtures are intentionally not used here: the
# `users` fixture is empty and collides with Devise's unique-email index, which
# makes the shared fixture loader blow up before any test body runs. Instead we
# create the few records we need inline so this test is self-contained.
#
#   bin/rails test test/integration/all_routes_test.rb
class AllRoutesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Don't pull in the broken shared fixtures (see note above).
  self.fixture_table_names = [] if respond_to?(:fixture_table_names=)

  # Routes we deliberately do not exercise (mounted Rack apps / internal Rails
  # endpoints that need a non-HTML contract or would mutate global state).
  SKIP_PATH_PREFIXES = %w[
    /rails/active_storage
    /rails/conductor
    /rails/mailers
    /cable
  ].freeze

  setup do
    @user = User.create!(
      email: "route-test-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
    @post = Post.create!(title: "Route Test", body: "Body")
    sign_in @user
  end

  test "every route responds without a server error" do
    failures = []

    Rails.application.routes.routes.each do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      # Only test routes backed by a real controller#action (skip mounted apps).
      next unless controller && action

      path = build_path(route, controller)
      next if path.nil?
      next if SKIP_PATH_PREFIXES.any? { |p| path.start_with?(p) }

      verb = primary_verb(route)
      next unless verb
      # The auto-loop only does GETs (safe, no side effects). State-changing
      # routes (POST/PUT/PATCH/DELETE) are exercised by the dedicated flow
      # tests below, with the params they actually need.
      next unless verb == "GET"

      begin
        dispatch_request(verb, path)
        status = response.response_code
        if status >= 500
          failures << "#{verb} #{path} -> HTTP #{status}"
        end
      rescue => ex
        root = ex
        root = root.cause while root.respond_to?(:cause) && root.cause
        failures << "#{verb} #{path} -> #{ex.class}: #{ex.message}\n    #{root.backtrace.first(5).join("\n    ")}"
      end
    end

    assert failures.empty?,
           "The following routes failed:\n\n#{failures.join("\n\n")}"
  end

  # The auto-loop above drives each route with its verb but without the params a
  # real auth flow needs, so the Devise sign-IN (Warden session write) and
  # sign-OUT paths are only brushed, not actually exercised. This test drives
  # the full flow with valid credentials so those state-changing controller
  # actions (session/cookie serialization, Warden hooks) really run.
  test "Devise sign-in and sign-out flow works" do
    sign_out @user

    # Render the login form.
    get new_user_session_path
    assert_response :success

    # POST valid credentials -> Warden authenticates and writes the session.
    post user_session_path, params: {
      user: { email: @user.email, password: "password" }
    }
    assert_response :redirect
    follow_redirect!
    assert_response :success

    # Sign out (Devise 5 default: DELETE /users/sign_out).
    delete destroy_user_session_path
    assert_response :redirect
    follow_redirect!
  end

  # The auto-loop only GETs, so the create/delete (state-changing) paths need
  # their own exercise. This drives a real POST (DB write) and DELETE so the
  # controller actions, strong params, and Kaminari/AR paths all run.
  test "creating and deleting a post works" do
    assert_difference("Post.count", 1) do
      post posts_path, params: {
        post: { title: "Created in test", body: "Body" }
      }
    end
    assert_response :redirect
    created = Post.find_by!(title: "Created in test")
    follow_redirect!
    assert_response :success

    assert_difference("Post.count", -1) do
      delete post_path(created)
    end
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # Exercises the new form (GET) so the `form_with` render path (same form used
  # by create/update) actually runs, not just the auto-loop's < 500 check.
  test "new post form renders" do
    get new_post_path
    assert_response :success
  end

  # Exercises the edit form (GET) and the PATCH update (state-changing write),
  # so the update action, strong params, and form rendering all run.
  test "editing and updating a post works" do
    get edit_post_path(@post)
    assert_response :success

    patch post_path(@post), params: {
      post: { title: "Updated in test", body: "Updated body" }
    }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal "Updated in test", @post.reload.title
  end

  private

  # Build a concrete request path from a route's path spec, substituting any
  # dynamic segments (:id, :format, ...) with sane sample values.
  def build_path(route, controller)
    spec = route.path.spec.to_s
    return nil if spec.empty? || spec == "(.:format)"

    # Drop optional groups like (.:format) or (/edit).
    spec = spec.gsub(/\(.*?\)/, "")
    spec = spec.gsub(/:format/, "")
    spec = spec.gsub(/:id\b/, sample_id_for(controller).to_s)
    # Remaining dynamic segments (e.g. :token, :page) get a placeholder.
    spec = spec.gsub(/:\w+/, "1")
    spec = spec.gsub(%r{/+}, "/")
    spec = spec.sub(%r{/$}, "")
    spec.empty? ? "/" : spec
  end

  # A plausible :id for the controller's model so show/edit render real records.
  def sample_id_for(controller)
    klass = controller.camelize.singularize.safe_constantize
    if klass && klass < ActiveRecord::Base
      klass.first&.id || 1
    else
      1
    end
  end

  # The HTTP verb to use. Prefer GET when available so we render pages;
  # otherwise use the route's primary verb.
  def primary_verb(route)
    source = route.verb.is_a?(String) ? route.verb : route.verb.source
    verbs = source.scan(/[A-Z]+/).uniq
    verbs.include?("GET") ? "GET" : verbs.first
  end

  def dispatch_request(verb, path)
    case verb
    when "GET" then get path
    when "POST" then post path
    when "PUT" then put path
    when "PATCH" then patch path
    when "DELETE" then delete path
    else get path
    end
  end
end
