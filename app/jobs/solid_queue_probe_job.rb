# RAILS_FEATURES.md #110: the Solid Queue probe job. With the :solid_queue
# adapter, `perform_later` from a worker Ractor writes the solid_queue_jobs
# row (a DB write); the job itself PERFORMS in the separate dispatcher
# process (`bin/jobs`, main Ractor, threaded). The perform lands an
# AuditLog row so an external observer can verify the dispatcher actually
# executed the job.
class SolidQueueProbeJob < ApplicationJob
  queue_as :default

  def perform(stamp)
    AuditLog.create!(action: "solid_queue_probe",
                     metadata: { "stamp" => stamp })
  end
end
