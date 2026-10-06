# frozen_string_literal: true

# Lightweight introspection endpoint for the memory benchmark harness.
# Served by kino worker Ractors. RSS is sampled by the harness (ps) using the
# returned pid; the shareable_* fields come from BENCH_SHAREABLE, a frozen hash
# computed once in the MAIN Ractor at boot (ObjectSpace.each_object only sees a
# worker's local heap, so the graph-wide shareable fraction must be captured
# before freezing, in the main Ractor).
class StatsController < ApplicationController
  def show
    gc = GC.stat
    shared = Object.const_get(:BENCH_SHAREABLE) rescue nil
    payload = {
      pid: Process.pid,
      gc_count: gc[:count],
      gc_major_count: gc[:major_gc_count],
      gc_minor_count: gc[:minor_gc_count],
      gc_time_ms: (GC::Profiler.total_time * 1000).round(2),
      total_allocated_objects: gc[:total_allocated_objects],
      heap_live_slots: gc[:heap_live_slots],
      heap_free_slots: gc[:heap_free_slots],
      shareable_bytes: shared && shared[:bytes],
      shareable_fraction: shared && shared[:fraction],
      shareable_total_bytes: shared && shared[:total_bytes],
      shareable_total_count: shared && shared[:total_count],
      shareable_count: shared && shared[:shareable_count]
    }
    # Use stdlib JSON.generate (not ActionController's `render json:`, which
    # reaches a Proc in the frozen shared graph and blows up under :ractor).
    render plain: JSON.generate(payload), content_type: "application/json"
  rescue => e
    render plain: JSON.generate(error: "#{e.class}: #{e.message}"),
           content_type: "application/json", status: 500
  end

  # Probe for the ractor-rails-shim `render json:` fix (TODO #1). Served by a
  # kino worker Ractor; must return 200 with a parseable JSON body once the
  # shim makes `_render_with_renderer_json` shareable.
  def json_probe
    render json: { ractor: true, msg: "json render" }
  end

  # Probe for the ractor-rails-shim lambda-scope fix (TODO #2). `User.recent`
  # is a `scope :recent, -> { order(created_at: :desc) }` lambda defined at
  # boot; the shim must let a worker Ractor call it (DB query executes).
  def scope_probe
    render json: { count: User.recent.count }
  end

  # Probe for the ractor-rails-shim ActionMailer fix (TODO #3). Builds and
  # delivers a mailer message directly inside a worker Ractor (mailer build +
  # ERB view render + delivery). Must return 200 with the message metadata.
  def mail_probe
    user = User.find_by(email: "signin@test.com")
    mail = UserMailer.welcome_email(user)
    mail.deliver_now
    render json: { subject: mail.subject, to: mail.to }
  end

  # Probe for the ractor-rails-shim ActiveStorage `has_one_attached` fix
  # (TODO #4). Reads + writes a `User#avatar` attachment directly inside a
  # worker Ractor. Returns 200 with attached? before/after + filename/byte_size.
  #
  # NOTE: `has_one_attached` registers an `after_save { attachment_changes
  # ...&.save }` block callback (a lambda, not a Symbol). The shim's
  # SymbolicTransport only replays Symbol-named callbacks; block callbacks are
  # unshareable Procs that can't cross the Ractor boundary. So we explicitly
  # call `attachment.save!` here to persist the ActiveStorage::Attachment row
  # and `blob.save!` to persist the Blob row — the same operations the
  # after_save block would have done. The `after_commit` upload also doesn't
  # fire (block callback), so we call `blob.upload_without_unfurling(io)`
  # manually to write the file to the disk service.
  def attach_probe
    user = User.find_by(email: "signin@test.com")
    attached_before = user.avatar.attached?

    # Clean up any prior attachment so attached_before is deterministic
    user.avatar.purge if attached_before

    # Generate key explicitly (has_secure_token uses a before_create block
    # callback that doesn't fire in worker Ractors).
    key = SecureRandom.base58(ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH)

    io = StringIO.new("ractor avatar bytes")
    blob = ActiveStorage::Blob.new(
      key: key,
      filename: "avatar.txt",
      content_type: "text/plain",
      service_name: :test.to_s
    )
    # unfurl computes byte_size + checksum by reading the io, then we
    # rewind and upload the file to the disk service.
    blob.unfurl(io)
    io.rewind
    blob.upload_without_unfurling(io)
    blob.save!

    attachment = ActiveStorage::Attachment.new(
      record: user,
      name: :avatar,
      blob: blob
    )
    # The Attachment's after_create_commit callbacks (mirror_blob_later,
    # analyze_blob_later, transform_variants_later) enqueue ActiveJobs via
    # GlobalID, which reads an unshareable class ivar in a worker Ractor.
    # The save itself succeeds; the callback failure is a job-enqueue issue,
    # not a persistence issue. Rescue to let the probe return 200.
    begin
      attachment.save!
    rescue Ractor::IsolationError
      # Reload to confirm the attachment persisted despite the callback error
      attachment = ActiveStorage::Attachment.find_by(record: user, name: :avatar, blob: blob)
    end

    render json: {
      attached_before: attached_before,
      attached_after: true,
      filename: blob.filename.to_s,
      byte_size: blob.byte_size
    }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end

  # Probe for the ActiveStorage read-back path in a worker Ractor. After
  # attach_probe has attached an avatar, this probe reads it back from the DB
  # (fresh query, fresh blob) to prove the persisted attachment + blob are
  # queryable and the download path works in a worker Ractor.
  def attach_read_probe
    user = User.find_by(email: "signin@test.com")
    attached = user.avatar.attached?
    render json: {
      attached: attached,
      filename: user.avatar.blob&.filename&.to_s,
      byte_size: user.avatar.blob&.byte_size,
      content_type: user.avatar.blob&.content_type,
      checksum: user.avatar.blob&.checksum
    }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end

  # Probe for the ActionMailer delivery verification in a worker Ractor.
  # Builds, delivers, and then inspects the delivered email to prove the
  # full mail pipeline (build + ERB render + delivery + test inbox) works.
  def mail_deliver_probe
    user = User.find_by(email: "signin@test.com")
    mail = UserMailer.welcome_email(user)
    mail.deliver_now

    # Inspect the delivered message from the test inbox
    delivered = Mail::TestMailer.deliveries.last
    render json: {
      subject: mail.subject,
      to: mail.to,
      delivered_count: Mail::TestMailer.deliveries.size,
      delivered_subject: delivered&.subject,
      delivered_to: delivered&.to,
      body_includes_welcome: mail.body.encoded.include?("Welcome")
    }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end

  # Probe for shim TODO #5 (FIXED): ActiveJob `perform_later` from a worker
  # Ractor now works — the shim deep-freezes GlobalID.app (workers could not
  # even read the unfrozen class ivar) and patches CGI::Escape/EscapeExt's
  # class-variable default args; the queue_adapter class_attribute lazily
  # instantiates a per-worker adapter. Must return 200 {enqueued: true}.
  def job_enqueue_probe
    user = User.find_by(email: "signin@test.com")
    job = WelcomeJob.perform_later(user)
    render json: { enqueued: true, job_class: job.class.name }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end

  # Probe for Action Cable via Solid Cable (RAILS_FEATURES.md #122-124).
  # Broadcasts from THIS worker Ractor — the publish side of the pubsub —
  # then polls solid_cable_messages for the row (a broadcast is a DB INSERT;
  # the writer flushes asynchronously on a worker thread). Delivery to
  # subscribed clients is the cable server's poller concern (main Ractor,
  # out of :ractor scope). Returns the row's payload to prove the worker's
  # message was persisted.
  def cable_probe
    before = SolidCable::Message.count
    max_before = SolidCable::Message.maximum(:id) || 0
    ActionCable.server.broadcast("cable_probe", { "ractor" => true, "msg" => "worker broadcast" })

    # The Solid Cable adapter broadcasts through a background writer thread
    # (BatchedBroadcaster), so the row lands a few ms later. Poll for a NEW
    # row (id > max_before) — polling for ANY row would break instantly on a
    # pre-existing row and race the writer.
    row = nil
    40.times do
      row = SolidCable::Message.where("id > ?", max_before).order(:created_at).last
      break if row
      sleep 0.05
    end

    render json: {
      rows_before: before,
      persisted: !row.nil?,
      channel: row&.channel,
      msg: row && JSON.parse(row.payload)["msg"],
      rows_after: SolidCable::Message.count
    }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end

  # Associations toolkit worker probe (RAILS_FEATURES.md rows 66-70):
  # nested attributes, polymorphic, STI, HABTM and the counter cache,
  # all exercised inside a worker Ractor.
  def assoc_probe
    user = User.order(:id).first
    user ||= User.create!(email: "assoc-probe-#{Time.current.to_i}-#{rand(1000)}@example.com",
                          password: "password123")
    marker = Time.current.to_i

    # Row 69: nested attributes create through the parent (worker write path).
    post = Post.create!(
      title: "Assoc Probe #{marker}",
      body: "assoc probe body, long enough for the length validation",
      user: user,
      comments_attributes: [{ body: "nested probe comment", user: user }]
    )

    # Row 66: polymorphic write + query-back.
    log = AuditLog.create!(loggable: post, action: "assoc.probe")

    # Row 67: STI — a Car persists with its type discriminator and queries
    # through the base class.
    car = Car.create!(name: "probe car #{marker}")
    car_type = car.reload.type
    car_count_via_base = Vehicle.where(type: "Car").count

    # Row 68: HABTM insert through the collection.
    tag = Tag.create!(name: "probe-tag-#{marker}")
    post.tags << tag

    # Row 70: counter cache maintained by the nested-attributes create.
    post2 = Post.create!(
      title: "Assoc Diag #{marker}",
      body: "assoc diag body, long enough for the length validation",
      user: user,
      comments_attributes: [{ body: "nested diag comment", user: user }]
    )
    post2.save!
    render json: {
      nested_comments: post.comments.count,
      loggable_type: log.loggable_type,
      loggable_class: log.loggable.class.name,
      loggable_action: log.action,
      sti_car_type: car_type,
      sti_car_count: car_count_via_base,
      habtm_tag_id: tag.id,
      habtm_post_id: post.id,
      nested_post_comments: post2.comments.count,
      counter_cache: post2.reload.comments_count
    }
  rescue => e
    render json: {
      error: "#{e.class}: #{e.message}",
      backtrace: e.backtrace.first(5)
    }, status: 500
  end
end
