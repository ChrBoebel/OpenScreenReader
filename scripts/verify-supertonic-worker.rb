#!/usr/bin/env ruby
# Real installed worker check. Fixed public text/audio stay in memory only.
require 'open3'
require 'json'
require 'base64'
require 'timeout'

root = File.join(Dir.home, 'Library/Application Support/OpenScreenReader')
runtime = File.join(root, 'SupertonicRuntime')
model = File.join(root, 'DevelopmentModels/supertonic-3-3cadd1ee')
python = File.join(runtime, 'venv/bin/python3')
profile = '(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (literal "/dev/null"))'
base = ['/usr/bin/sandbox-exec', '-p', profile, python, '-I', '-B']
worker = base + [File.join(runtime, 'worker.py'), '--model', model]
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
first_audio = nil
frames = 0
peak = 0.0
ready = false
complete = false
Open3.popen3(*worker) do |input, output, error, process|
  begin
    Timeout.timeout(90) do
      input.puts(JSON.generate(text: 'Hallo Welt. Dies ist ein lokaler Sprachtest.', language: 'de'))
      input.flush
      while (line = output.gets(140_002))
        abort 'Oversized/truncated packet' if line.bytesize > 140_001 || !line.end_with?("\n")
        packet = JSON.parse(line)
        case packet.fetch('kind')
        when 'ready'
          abort 'Invalid ready' if ready || packet['sampleRate'] != 44_100
          ready = true
        when 'audio'
          abort 'Invalid audio format' unless ready && packet['sampleRate'] == 44_100
          first_audio ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          pcm = Base64.strict_decode64(packet.fetch('pcm'))
          abort 'Invalid PCM size' if pcm.empty? || pcm.bytesize > 96_000 || pcm.bytesize % 4 != 0
          samples = pcm.unpack('e*')
          abort 'Non-finite PCM' unless samples.all?(&:finite?)
          frames += samples.length
          abort 'Exceeded fixture audio bound' if frames > 44_100 * 120
          peak = [peak, samples.map(&:abs).max].max
          input.puts('next')
          input.flush
        when 'end'
          complete = true
          break
        else
          abort 'Generic worker failure'
        end
      end
      input.close
      abort 'Incomplete/silent worker' unless complete && ready && peak > 0.0001 && process.value.success?
      abort 'Unexpected content diagnostics' unless error.read.empty?
    end
  ensure
    Process.kill('KILL', process.pid) if process.alive?
  end
end
puts JSON.generate(first_audio_seconds: first_audio.round(3), audio_seconds: (frames / 44_100.0).round(3), peak: peak.round(4))

invalid_output, invalid_error, status = Open3.capture3(*worker, stdin_data: "{\"text\":\"Private test sentinel\",\"language\":\"invalid\"}\n")
abort 'Invalid request leaked or succeeded' unless !status.success? && invalid_error.empty? && JSON.parse(invalid_output) == {'kind' => 'error'}

# Verify enforcement, not just the existence of a sandbox profile. Neither
# forbidden operation transmits content; the connection target is loopback.
probe = <<~PYTHON
  import socket
  for operation in (
      lambda: socket.create_connection(('127.0.0.1', 9), timeout=1),
      lambda: open('/private/tmp/osr-supertonic-forbidden-write', 'xb')
  ):
      try:
          operation()
      except PermissionError:
          continue
      raise RuntimeError('Sandbox did not deny operation')
  print('PASS: network and file writes denied')
PYTHON
abort 'Privacy probe failed' unless system(*base, '-c', probe)
puts 'PASS: real Supertonic PCM, bounded protocol, generic errors, and privacy enforcement'
