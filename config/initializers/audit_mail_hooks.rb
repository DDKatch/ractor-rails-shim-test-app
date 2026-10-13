# frozen_string_literal: true

# RAILS_FEATURES.md #113: a boot-registered delivery interceptor. The shim
# snapshots the mail gem's hook registries at prepare time, so this hook runs
# in worker Ractors too — /stats/mail_hooks_probe asserts the header appears
# on messages delivered from a worker.
class AuditMailInterceptor
  def self.delivering_email(message)
    message["X-Audit-Interceptor"] = "registered-in-main"
  end
end

ActionMailer::Base.register_interceptor(AuditMailInterceptor)
