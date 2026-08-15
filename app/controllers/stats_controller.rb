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
end
