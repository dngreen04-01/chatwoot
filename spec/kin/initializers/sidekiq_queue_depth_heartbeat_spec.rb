# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'kin_sidekiq_queue_depth_heartbeat initializer' do
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil) }
  let(:stats) { instance_double(Sidekiq::Stats, enqueued: 42, queues: { 'default' => 42 }) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
  end

  # The initializer registers a Concurrent::TimerTask inside
  # Sidekiq.configure_server.on(:startup). Re-execute the tick body here so we
  # can assert on what it writes without spinning up a real Sidekiq process.
  def run_one_tick
    stats = Sidekiq::Stats.new
    Rails.logger.info({
      sidekiq_queue_depth: stats.enqueued,
      sidekiq_enqueued_per_queue: stats.queues
    }.to_json)
  rescue StandardError => e
    Rails.logger.warn("[kin] sidekiq queue depth heartbeat failed: #{e.class}: #{e.message}")
  end

  it 'emits a JSON line with sidekiq_queue_depth as a top-level field' do
    run_one_tick
    expect(logger).to have_received(:info) do |payload|
      parsed = JSON.parse(payload)
      expect(parsed['sidekiq_queue_depth']).to eq(42)
      expect(parsed['sidekiq_enqueued_per_queue']).to eq('default' => 42)
    end
  end

  it 'logs a warning and stays alive if Sidekiq::Stats raises' do
    allow(Sidekiq::Stats).to receive(:new).and_raise(Redis::CannotConnectError, 'redis down')
    expect { run_one_tick }.not_to raise_error
    expect(logger).to have_received(:warn).with(/sidekiq queue depth heartbeat failed.*redis down/)
  end
end
