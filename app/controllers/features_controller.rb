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

  # RAILS_FEATURES.md #63/#64: aggregates (sum/average/min/max/pluck/pick/
  # ids/exists?) and grouping (group/having/distinct) exercised in a worker
  # Ractor.
  def aggregate_probe
    render json: {
      sum_id: Post.sum(:id),
      average_id: Post.average(:id)&.to_i,
      min_le_max: Post.minimum(:id) <= Post.maximum(:id),
      pluck_count: Post.limit(3).pluck(:title).size,
      pick_present: Post.order(:id).pick(:title).present?,
      ids_integer: Post.ids.first.is_a?(Integer),
      exists: Post.exists?,
      none_exists: Post.where("1 = 0").exists?,
      group_states: Post.group(:state).count.size,
      having_states: Post.group(:state).having("COUNT(id) > 0").count.size,
      distinct_titles: Post.distinct.count(:title)
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #75: signed_id — sign + find_signed round-trip exercised
  # in a worker Ractor (MessageVerifier path, previously only implied via
  # Devise/ActiveStorage).
  def signed_id_probe
    post = Post.order(:id).first
    return head(:not_found) unless post

    sid = post.signed_id(expires_in: 1.hour)
    render json: {
      roundtrip: Post.find_signed(sid)&.id == post.id,
      invalid_returns_nil: Post.find_signed("totally-invalid-signature").nil?,
      bang_raises: begin
        Post.find_signed!("totally-invalid-signature")
        false
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        true
      end
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #76: insert_all / upsert_all — bulk-write tags in a
  # worker Ractor (skips validations/callbacks, straight INSERT/UPSERT).
  def bulk_probe
    now = Time.current
    base = "Bulk #{now.to_i} #{rand(10_000)}"
    rows = Array.new(3) { |i| { name: "#{base} insert #{i}", created_at: now, updated_at: now } }
    inserted = Tag.insert_all!(rows)

    # Upsert: insert a row, then upsert the same unique name with a new
    # timestamp — the second write must UPDATE, not duplicate.
    unique_name = "#{base} upsert"
    Tag.insert_all!([{ name: unique_name, created_at: now, updated_at: now }])
    upserted = Tag.upsert_all([{ name: unique_name, created_at: now, updated_at: now }], unique_by: :name)

    # The unique index on name must fire for a duplicate bulk INSERT. Run the
    # expected-conflict insert inside a nested transaction (savepoint) so the
    # aborted statement doesn't poison an enclosing transaction (e.g. a
    # transactional test that visits this route).
    conflict_raises = false
    Tag.transaction(requires_new: true) do
      begin
        Tag.insert_all!([{ name: rows.first[:name], created_at: now, updated_at: now }])
      rescue ActiveRecord::RecordNotUnique
        conflict_raises = true
        raise ActiveRecord::Rollback
      end
    end

    render json: {
      inserted_count: inserted.count,
      upserted_count: upserted.count,
      no_duplicate_after_upsert: Tag.where(name: unique_name).count == 1,
      unique_conflict_raises: conflict_raises
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #107 + #108: ActiveJob resilience declarations and
  # enqueue options from a worker Ractor. The retry_on / discard_on configs
  # live in the rescue_handlers class_attribute — the probe reports what is
  # readable from the worker (nil = unreadable, an audit finding). The
  # enqueued DiscardJob is discarded silently on perform (discard_on
  # ArgumentError), so the async adapter's delayed execution stays quiet.
  def job_resilience_probe
    job = DiscardJob.set(queue: "low", wait: 2.seconds).perform_later
    retry_handlers = (FlakyJob.rescue_handlers.map { |entry| entry[0] } rescue nil)
    discard_handlers = (DiscardJob.rescue_handlers.map { |entry| entry[0] } rescue nil)

    render json: {
      enqueued: job.is_a?(DiscardJob),
      queue: job.queue_name,
      scheduled_in_future: job.scheduled_at.is_a?(Time) && job.scheduled_at > Time.current,
      priority: job.priority,
      retry_handlers: retry_handlers,
      discard_handlers: discard_handlers
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #71: optimistic locking (lock_version). Rails turns it
  # on automatically once the column exists; no code needed on the model.
  # From a worker Ractor: a dedicated probe row is created, two copies are
  # loaded, the first save wins and bumps lock_version, the second save must
  # raise ActiveRecord::StaleObjectError (and must NOT touch the row). The
  # row is destroyed afterwards so the probe never disturbs other kino
  # probes (e.g. the create-proof row asserted via LIKE below).
  def optimistic_lock_probe
    probe = Post.create!(title: "Optimistic Probe #{Time.current.to_i}",
                         body: "optimistic locking probe body")
    winner = Post.find(probe.id)
    loser = Post.find(probe.id)
    starting_version = winner.lock_version

    winner.update!(title: "Optimistic Winner #{Time.current.to_i}")

    stale_raised = false
    stale_error = nil
    begin
      loser.update!(title: "Optimistic Loser")
    rescue ActiveRecord::StaleObjectError => e
      stale_raised = true
      stale_error = e.class.name
    end

    fresh = Post.find(probe.id)
    # NB: destroy via the FRESH copy — `probe` is stale after the winning
    # save and would itself raise StaleObjectError on destroy!
    # (Which is the feature under test working on the destroy path too.)
    fresh.destroy!
    render json: {
      # NB: ClassMethods#locking_enabled? returns the truthy COLUMN (lock
      # optimistically && columns_hash[locking_column]), so coerce to bool.
      locking_enabled: !Post.locking_enabled?.nil?,
      starting_version: starting_version,
      stale_raised: stale_raised,
      stale_error: stale_error,
      winner_lock_version: fresh.lock_version,
      version_incremented: fresh.lock_version == starting_version + 1,
      winner_title_present: fresh.title.to_s.start_with?("Optimistic Winner"),
      loser_title_absent: !fresh.title.to_s.start_with?("Optimistic Loser")
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #72: pessimistic locking (with_lock). From a worker
  # Ractor: create a dedicated probe row, run a with_lock transaction (SELECT
  # ... FOR UPDATE + update inside the held lock), verify the update
  # persisted, and confirm the generated SQL really carries FOR UPDATE. The
  # row is destroyed afterwards so the probe never disturbs other kino
  # probes.
  def pessimistic_lock_probe
    probe = Post.create!(title: "Pessimistic Probe #{Time.current.to_i}",
                         body: "pessimistic locking probe body")

    probe.with_lock do
      probe.update!(title: "Pessimistic Winner #{Time.current.to_i}")
    end

    fresh = Post.find(probe.id)
    fresh.destroy!
    render json: {
      with_lock_completed: true,
      winner_title_present: fresh.title.to_s.start_with?("Pessimistic Winner"),
      lock_sql_includes_for_update: Post.order(:id).lock.to_sql.upcase.include?("FOR UPDATE"),
      winner_lock_version: fresh.lock_version
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #74: attribute normalization (normalizes). From a
  # worker Ractor: the class-level normalize_value_for and an instance
  # assignment both route through the NormalizedValueType holding the
  # normalizer Proc — the same shareability class as scope lambdas. No
  # persistence: read-only assignment on an existing user, then reload.
  def normalizes_probe
    normalized_class = User.normalize_value_for(:email, " CRUISE@EXAMPLE.COM\n")
    user = User.order(:id).first
    return head(:not_found) unless user

    original = user.email
    user.email = " #{original} "
    normalized_instance = user.email
    user.reload

    render json: {
      class_level_normalized: normalized_class,
      class_level_ok: normalized_class == "cruise@example.com",
      instance_normalized: normalized_instance,
      instance_ok: normalized_instance == original.to_s.strip.downcase
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #78: default_scope / unscoped. Category has an
  # ORDER-based default_scope (order(:name)). From a worker Ractor: two
  # dedicated probe rows created zulu-first, so name order (default scope)
  # and id order (unscoped) disagree — proving the scope is applied by
  # `all`-style reads and removed by `unscoped`. Rows destroyed after.
  def default_scope_probe
    stamp = SecureRandom.hex(2)
    zulu = Category.create!(name: "Probe Zulu #{stamp}")
    alpha = Category.create!(name: "Probe Alpha #{stamp}")

    pattern = "%Probe%"
    scoped_names = Category.where("name LIKE ?", pattern).map(&:name)
    unscoped_names = Category.unscoped.where("name LIKE ?", pattern).map(&:name)

    alpha.destroy!
    zulu.destroy!

    render json: {
      scoped_alpha_first: scoped_names.index(alpha.name) < scoped_names.index(zulu.name),
      unscoped_zulu_first: unscoped_names.index(zulu.name) < unscoped_names.index(alpha.name),
      orders_differ: scoped_names != unscoped_names
    }
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
