#!/usr/bin/env ruby
# Explicit listening comparison only, never invoked by the app. Only the fixed
# public fixture below can be exported; no OCR text or user audio is accepted.
require 'open3'
require 'json'
require 'base64'
require 'timeout'
require 'tmpdir'
require 'digest'

abort 'Usage: ruby scripts/compare-german-voices.rb WORKER MODEL_DIRECTORY' unless ARGV.length == 2
worker, model = ARGV.map { |path| File.expand_path(path) }
abort 'Missing local worker or model' unless File.executable?(worker) && File.file?(File.join(model, 'tokenizer.json'))
abort 'Pinned model verification failed' unless system('/bin/bash', File.join(__dir__, 'download-qwen.sh'), model, '--verify-only')
abort 'Unexpected prepared tokenizer' unless Digest::SHA256.file(File.join(model, 'tokenizer.json')).hexdigest ==
  '39c94a2d71ba8b0d33757e052581c63feaca79f7639421baedd595493d4fccc3'
directory = Dir.mktmpdir('openscreenreader-stimmen-', '/private/tmp')
phrase = 'Guten Morgen. Heute lesen wir einen deutschen Text über Bücher, schöne Städte und frische Brötchen. Der nächste Zug fährt um fünfzehn Uhr dreißig nach München.'
profile = '(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (literal "/dev/null"))'
results = []
$stdout.sync = true
puts "Temporary comparison directory: #{directory}"

%w[Serena Ryan Aiden].each do |voice|
  puts "Generating #{voice}, explicit German, seed 42…"
  pcm16 = ''.b
  peak = 0.0
  complete = false
  ready = false
  Open3.popen2({ 'HF_HUB_OFFLINE' => '1', 'HF_HUB_DISABLE_TELEMETRY' => '1' },
               '/usr/bin/sandbox-exec', '-p', profile, worker, '--model', model,
               err: File::NULL) do |input, output, process|
    begin
      input.puts(JSON.generate(text: phrase, voice: voice, language: 'German', seed: 42))
      input.flush
      Timeout.timeout(120) do
        while (line = output.gets(140_002))
          abort 'Oversized or truncated packet' if line.bytesize > 140_001 || !line.end_with?("\n")
          packet = JSON.parse(line)
          case packet.fetch('kind')
          when 'ready'
            abort 'Invalid ready packet' if ready || packet['sampleRate'] != 24_000
            ready = true
          when 'audio'
            abort 'Unexpected sample rate' unless ready && packet['sampleRate'] == 24_000
            pcm = Base64.strict_decode64(packet.fetch('pcm'))
            abort 'Invalid PCM packet' if pcm.empty? || pcm.bytesize > 96_000 || pcm.bytesize % 4 != 0
            samples = pcm.unpack('e*')
            abort 'Non-finite audio' unless samples.all?(&:finite?)
            peak = [peak, samples.map(&:abs).max].max
            # No voice-dependent normalization, resampling, or inserted pauses.
            pcm16 << samples.map { |sample| ([[sample, -1.0].max, 1.0].min * 32_767).round }.pack('s<*')
            abort 'Comparison exceeded 120 seconds of audio' if pcm16.bytesize > 24_000 * 2 * 120
            input.puts('next')
            input.flush
          when 'end'
            complete = true
            break
          else
            abort 'Worker failed; no content diagnostics exported'
          end
        end
        input.close
        abort 'Incomplete or silent comparison' unless complete && ready && peak > 0.0001 && process.value.success?
      end
    ensure
      Process.kill('KILL', process.pid) if process.alive?
    end
  end
  filename = "#{voice.downcase}-de.wav"
  header = 'RIFF'.b + [36 + pcm16.bytesize].pack('V') + 'WAVEfmt '.b +
           [16, 1, 1, 24_000, 48_000, 2, 16].pack('VvvVVvv') + 'data'.b + [pcm16.bytesize].pack('V')
  File.open(File.join(directory, filename), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.binmode
    file.write(header)
    file.write(pcm16)
  end
  result = { voice: voice, language: 'German', seed: 42, file: filename,
             audio_seconds: (pcm16.bytesize / 48_000.0).round(3), peak: peak.round(4),
             sha256: Digest::SHA256.file(File.join(directory, filename)).hexdigest }
  results << result
  puts JSON.generate(result)
end
File.open(File.join(directory, 'comparison.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
  file.write(JSON.pretty_generate(purpose: 'Owner-requested fixed-text listening comparison; temporary, outside Git',
    text: phrase, model_revision: '08c72cad5e2fd0f41730c8bd1f28149585e46361',
    worker_sha256: Digest::SHA256.file(worker).hexdigest, results: results) + "\n")
end
puts "PASS: three complete local comparison files; app installation and default voice unchanged"
