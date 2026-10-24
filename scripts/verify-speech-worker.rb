#!/usr/bin/env ruby
# Real, content-free diagnostic output. Audio and the fixed test phrase stay in memory.
require 'open3'
require 'json'
require 'base64'
require 'timeout'
require_relative 'worker_sandbox'

abort 'Usage: ruby scripts/verify-speech-worker.rb WORKER MODEL_DIRECTORY' unless ARGV.length == 2
worker, model = ARGV.map { |path| File.expand_path(path) }
# The app's deny-default worker profile: reads only the worker folder, its prefix and the model.
sandbox = WorkerSandbox.command(resources: File.dirname(worker), executable: worker, model_root: model)
abort 'Missing worker or model directory' unless sandbox
environment = { 'PATH' => '/usr/bin:/bin', 'HF_HUB_OFFLINE' => '1', 'HF_HUB_DISABLE_TELEMETRY' => '1' }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
first_audio = nil
sample_count = 0
peak = 0.0
complete = false
Open3.popen3(environment, *sandbox, '--model', model,
             unsetenv_others: true, chdir: File.dirname(worker)) do |input, output, error, process|
  begin
    input.puts(JSON.generate(text: 'Hallo Welt. Dies ist ein lokaler Sprachtest.'))
    input.flush
    Timeout.timeout(120) do
      output.each_line do |line|
        abort 'Oversized packet' if line.bytesize > 140_000
        packet = JSON.parse(line)
        case packet.fetch('kind')
        when 'ready'
          abort 'Wrong sample rate' unless packet['sampleRate'] == 24_000
        when 'audio'
          first_audio ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          pcm = Base64.strict_decode64(packet.fetch('pcm'))
          abort 'Invalid PCM size' if pcm.empty? || pcm.bytesize > 96_000 || pcm.bytesize % 4 != 0
          samples = pcm.unpack('e*')
          abort 'Non-finite PCM' unless samples.all?(&:finite?)
          peak = [peak, samples.map(&:abs).max].max
          sample_count += samples.length
          input.puts('next')
          input.flush
        when 'end'
          complete = true
          break
        else
          abort 'Worker reported an error; no content diagnostics retained.'
        end
      end
    end
    input.close
    abort 'Worker did not complete successfully' unless complete && process.value.success?
    abort 'Worker produced no audible signal' unless sample_count > 0 && peak > 0.0001
    puts JSON.pretty_generate(sandbox: 'Runtime/Dictation/worker.sb', network: 'denied', file_writes: 'denied except /dev/null',
                              first_audio_seconds: first_audio.round(3), samples: sample_count,
                              audio_seconds: (sample_count / 24_000.0).round(3), peak: peak.round(4))
  ensure
    Process.kill('KILL', process.pid) if process.alive?
  end
end
