# Probe controller for the full Rails-guides sweep (RAILS_FEATURES.md
# rows 89, 91, 92, 93): conditional GET, cookie jars, head, HTTP basic
# auth. Each action is dispatched by test/integration/ractor_server_test.rb
# in :ractor mode as well.
class FeaturesController < ApplicationController
  # RAILS_FEATURES.md #100: text helpers. Included at boot (main-Ractor
  # class definition) — `include` from a worker would mutate a shared
  # class and raise Ractor::UnsafeError.
  include ActionView::Helpers::TextHelper

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

  # RAILS_FEATURES.md #79: strict_loading. From a worker Ractor: a
  # strict_loading relation marks the record so accessing a NON-preloaded
  # association raises ActiveRecord::StrictLoadingViolationError, while
  # preloaded associations (includes) stay readable. Read-only probe.
  def strict_loading_probe
    strict_post = Post.strict_loading.order(:id).first
    return head(:not_found) unless strict_post

    violation = nil
    begin
      strict_post.comments.to_a
    rescue ActiveRecord::StrictLoadingViolationError => e
      violation = e.class.name
    end

    preloaded = Post.strict_loading.includes(:user, :comments).order(:id).first
    preloaded_ok = preloaded.user.nil? || preloaded.user.is_a?(User)
    preloaded.comments.to_a

    plain_post = Post.order(:id).first
    plain_ok = plain_post.comments.to_a.is_a?(Array)

    render json: {
      violation_raised: violation == "ActiveRecord::StrictLoadingViolationError",
      violation_class: violation,
      preloaded_ok: preloaded_ok,
      plain_ok: plain_ok
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #77: async queries (load_async). From a worker Ractor:
  # the query is scheduled on the per-Ractor executor (Concurrent futures —
  # the same Thread-in-Ractor class as the async job adapter) and the
  # relation materializes when the future completes.
  def load_async_probe
    rel = Post.order(:id).load_async
    rows = rel.to_a
    render json: {
      row_count: rows.size,
      non_empty: rows.any?,
      loaded: rel.loaded?
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md rows 83 + 82: advanced migrations + Postgres jsonb.
  # From a worker Ractor: create an archive against an existing post (FK),
  # find it via a jsonb containment query, and prove the check constraint
  # bites when validations are bypassed. Cleaned up after.
  def audit_archive_probe
    post = Post.order(:id).first
    return head(:not_found) unless post

    stamp = SecureRandom.hex(2)
    archive = AuditArchive.create!(
      label: "audit probe #{stamp}",
      post: post,
      payload: { "tag" => stamp, "n" => 1 }
    )

    found = AuditArchive.where("payload @> ?", { tag: stamp }.to_json)
    found_count = found.count

    check_violation = false
    begin
      bad = AuditArchive.new(label: "", post: post)
      bad.save(validate: false)
    rescue ActiveRecord::StatementInvalid => e
      check_violation = e.message.include?("audit_archives_label_check")
    end

    archive.destroy!

    # Row 82: Postgres types on AuditLog — jsonb containment + array ANY().
    log = AuditLog.create!(action: "audit probe",
                           metadata: { "tag" => stamp },
                           trace_ids: [ "abc", stamp ])
    log_jsonb_count = AuditLog.where("metadata @> ?", { tag: stamp }.to_json).count
    log_array_count = AuditLog.where("? = ANY(trace_ids)", stamp).count
    log.destroy!

    render json: {
      created: archive.id.present?,
      jsonb_found_count: found_count,
      jsonb_query_ok: found_count == 1,
      check_violation: check_violation,
      log_jsonb_ok: log_jsonb_count == 1,
      log_array_ok: log_array_count == 1
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #80: composite primary keys from a worker Ractor.
  # region_stats has PK (region, year) — no synthetic id. Exercise
  # tuple find, update by PK, and the duplicate-PK violation; cleaned
  # up after.
  def composite_pk_probe
    stat = RegionStat.create!(region: "EU", year: 2026, visits: 10)
    created = stat.persisted?
    found = RegionStat.find([ "EU", 2026 ])
    find_by_pk_ok = found.visits == 10
    found.update!(visits: 42)
    update_ok = found.reload.visits == 42

    dup_violation = false
    begin
      RegionStat.create!(region: "EU", year: 2026, visits: 99)
    rescue ActiveRecord::RecordNotUnique => e
      dup_violation = e.message.include?("region_stats_pkey")
    end

    stat.destroy!

    render json: {
      created: created,
      find_by_pk_ok: find_by_pk_ok,
      update_ok: update_ok,
      dup_violation: dup_violation
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #97: custom form builder + fields_for. Renders a
  # form via LabeledFormBuilder (custom labeled-field markup) with a
  # fields_for block on the Post comments association (nested-attribute
  # naming). Returns JSON verdicts about the generated HTML.
  def builder_form_probe
    @post = Post.new
    html = render_to_string(layout: false)

    render json: {
      custom_builder_ok: html.include?("labeled-field") && html.include?("post_title"),
      fields_for_ok: html.include?("post[comments_attributes][0][body]"),
      html_length: html.length
    }
  rescue => e
    render json: { error: "#{e.class}: #{e.message}" }, status: 500
  end

  # RAILS_FEATURES.md #100: text helpers from a worker Ractor. Pure-Ruby
  # ActionView::Helpers::TextHelper — the same call shape the worker-side
  # view rendering already uses (posts index/cards use truncate +
  # pluralize); highlight and excerpt added here for deterministic
  # assertions.
  def text_helpers_probe
    fmt = ->(e) { "ERR:#{e.class}: #{e.message[0, 80]}" }
    tr = (truncate("hello world", length: 5) rescue fmt.call($!))
    pl = (pluralize(2, "comment") rescue fmt.call($!))
    # highlight sanitizes by default (Nokogiri — row 120 ⛔ in workers), so
    # opt out here; the HTML-wrapping itself is a plain gsub.
    hl = (highlight("a b c", "b", sanitize: false) rescue fmt.call($!))
    ex = (excerpt("a b c", "b") rescue fmt.call($!))

    render json: {
      truncate_ok: tr == "he...",
      pluralize_ok: pl == "2 comments",
      highlight_ok: hl.include?("<mark>"),
      excerpt_ok: ex == "a b c",
      tr: tr, pl: pl, hl: hl, ex: ex
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
