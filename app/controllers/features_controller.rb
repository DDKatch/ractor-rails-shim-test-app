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

  # RAILS_FEATURES.md #98-99, #101: form probe — collection_select,
  # date_select, file_field (multipart), and the fields_with_errors
  # wrapper (the probe record carries a :body error on purpose).
  def form_probe
    @post = Post.new(title: "Probe")
    @post.valid? # body missing -> fields_with_errors wraps the body field
    @categories = Category.all
  end

  # Echo endpoint for form_probe: returns the submitted values (including
  # the uploaded file's metadata) as JSON.
  def form_echo
    attrs = params.require(:post)
    upload = attrs[:attachment]
    render json: {
      title: attrs[:title],
      category_id: attrs[:category_id],
      scheduled_at: attrs[:scheduled_at],
      attachment: upload.present? ? { filename: upload.original_filename, byte_size: upload.size, content_type: upload.content_type } : nil
    }
  end

  # RAILS_FEATURES.md rows 1+98: worker-side model validations. `valid?` must
  # replay the captured validator descriptors in the worker: false with a
  # populated errors object for an invalid record, true for a valid one. This
  # is the row-1 data-integrity guarantee — before the fix, worker `valid?`
  # returned true with ZERO errors (invalid records saved in workers).
  def validations_probe
    valid_record = Post.new(title: "Valid Title", body: "A long enough body")
    invalid_record = Post.new(title: "Valid Title", body: nil)
    render json: {
      valid_record_valid: valid_record.valid?,
      invalid_record_valid: invalid_record.valid?,
      invalid_error_attributes: invalid_record.errors.details.keys.sort.map(&:to_s)
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #65: ActiveRecord enum — default value, bang methods,
  # predicates, the class-level values reader and per-value scopes, all
  # exercised in a worker Ractor (real defs + shared EnumType registration).
  def enum_probe
    record = Post.new(title: "Enum Probe", body: "A long enough body")
    record.moderated!
    render json: {
      default_state: Post.new.state,
      bang_state: record.state,
      pred_moderated: record.moderated?,
      pred_draft: record.draft?,
      states_moderated: Post.states["moderated"],
      scope_moderated_count: Post.moderated.count,
      scope_not_draft_count: Post.not_draft.count,
      invalid_raises: begin
        Post.new.state = :bogus
        false
      rescue ArgumentError
        true
      end
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #73: dirty tracking — instance-level state (changed?,
  # changes, saved_changes, attribute_was) exercised in a worker Ractor.
  def dirty_probe
    record = Post.order(:id).last
    record.title = "Dirty Probe #{Time.current.to_i}"
    rendered = {
      changed_after_mutate: record.changed?,
      changes_title: record.changes["title"].is_a?(Array) && record.changes["title"].size == 2,
      title_was: record.title_was.present?,
      changed_list_includes_title: record.changed.include?("title")
    }
    record.save!
    rendered[:changed_after_save] = record.changed?
    rendered[:saved_changes_title] = record.saved_changes["title"].is_a?(Array) && record.saved_changes["title"].size == 2
    render json: rendered
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #62: batch processing — find_each / find_in_batches /
  # in_batches exercised in a worker Ractor.
  def batch_probe
    counts = { find_each: 0, find_in_batches: 0, in_batches_ids: 0 }
    Post.find_each(batch_size: 10) { counts[:find_each] += 1 }
    Post.find_in_batches(batch_size: 10) { |batch| counts[:find_in_batches] += batch.size }
    Post.in_batches(of: 10) { |relation| counts[:in_batches_ids] += relation.ids.size }
    render json: counts.merge(total: Post.count)
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #129: CurrentAttributes round-trip through a request.
  def current_attrs
    render json: { request_id: Current.request_id }
  end

  # RAILS_FEATURES.md #120: rich text (Action Text) — write + sanitize +
  # render. The render path goes through rails-html-sanitizer (Nokogiri),
  # which is the permanent worker limitation.
  def rich_text
    post = Post.order(:id).last
    return head(:not_found) unless post

    if params[:body].present?
      post.update!(content: params[:body])
    end
    @post = post
  end
end
