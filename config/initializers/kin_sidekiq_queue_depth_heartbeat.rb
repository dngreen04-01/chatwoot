# frozen_string_literal: true

# Layer 3 — emits Sidekiq queue depth as a JSON log line once per interval.
# Consumed by the `sidekiq_queue_depth` log-based metric defined in
# personal-kin/infra/terraform/log_metrics.tf. If that metric or its alert
# policy is renamed, update this file and the Ops Agent config in lockstep.
#
# Note: when Sidekiq scales to >1 server process, each process emits its own
# heartbeat. The log-based metric applies ALIGN_PERCENTILE_99 / REDUCE_MAX per
# minute, so duplicate emissions collapse into a single data point, not sum.

Sidekiq.configure_server do |config|
  config.on(:startup) do
    interval = ENV.fetch('KIN_SIDEKIQ_QUEUE_DEPTH_INTERVAL_SECONDS', 60).to_i

    task = Concurrent::TimerTask.new(execution_interval: interval, run_now: true) do
      stats = Sidekiq::Stats.new
      Rails.logger.info({
        sidekiq_queue_depth: stats.enqueued,
        sidekiq_enqueued_per_queue: stats.queues
      }.to_json)
    rescue StandardError => e
      Rails.logger.warn("[kin] sidekiq queue depth heartbeat failed: #{e.class}: #{e.message}")
    end

    task.execute
  end
end
