#!/usr/bin/env ruby
# Mechanically stage a minimal MIT-licensed upstream subset; never load a model.
require 'digest'
require 'fileutils'
require 'tmpdir'

abort 'Usage: ruby scripts/prepare-runtime.rb PINNED_UPSTREAM_TAR_GZ' unless ARGV.length == 1
archive = File.expand_path(ARGV[0])
expected = '086e188dc8e4957c34ee703a130e4b7accc70049c0ef65cd7e7cc8ed590c8bbc'
abort 'Unexpected upstream archive hash' unless Digest::SHA256.file(archive).hexdigest == expected
destination = File.expand_path('../Runtime/.generated', __dir__)
abort 'Generated runtime already exists; inspect it before replacing' if File.exist?(destination)

Dir.mktmpdir('osr-runtime-source-') do |temporary|
  abort 'Cannot unpack source' unless system('/usr/bin/tar', '-xzf', archive, '-C', temporary)
  source = File.join(temporary, 'mlx-audio-swift-bf14ae0c26e4e85553dd989571cae29d70fa6735')
  groups = {
    'Core' => ['Sources/MLXAudioCore/DSP.swift', 'Sources/MLXAudioCore/Generation/GenerationTypes.swift'],
    'Codecs' => %w[Conv Seanet Transformer Quantization].map { |name| "Sources/MLXAudioCodecs/Mimi/#{name}.swift" },
    'Qwen' => Dir.glob(File.join(source, 'Sources/MLXAudioTTS/Models/Qwen3TTS/*.swift')).map { |path| path.delete_prefix(source + '/') } + ['Sources/MLXAudioTTS/Generation.swift']
  }
  # Everything is pinned before any copied source is compiled or executed.
  groups.each do |group, paths|
    FileUtils.mkdir_p(File.join(destination, group))
    paths.each { |path| FileUtils.cp(File.join(source, path), File.join(destination, group, File.basename(path))) }
  end
  FileUtils.cp(File.join(source, 'LICENSE'), File.join(destination, 'LICENSE-mlx-audio-swift'))
end

qwen = File.join(destination, 'Qwen/Qwen3TTS.swift')
content = File.read(qwen)
def replace_once(content, pattern, replacement)
  abort 'Upstream patch no longer matches exactly once' unless content.scan(pattern).length == 1
  content.sub(pattern, replacement)
end
content = replace_once(content, /^import HuggingFace\n/, '')
content = replace_once(content, /^import Tokenizers\n/, "import Tokenizers\nimport Hub\n")
content = replace_once(content, /AutoTokenizer.from\(modelFolder: modelDir\)/,
  'AutoTokenizer.from(modelFolder: modelDir, hubApi: HubApi(hfToken: "", useOfflineMode: true))')
content = replace_once(content, /    public static func fromPretrained\([\s\S]*?(?=    public static func fromModelDirectory)/, '')
content = replace_once(content, /        \/\/ Generate tokenizer.json if missing[\s\S]*?(?=        \/\/ Load tokenizer)/,
  "        guard fm.fileExists(atPath: modelDir.appendingPathComponent(\"tokenizer.json\").path) else {\n            throw AudioGenerationError.modelNotInitialized(\"Prepare tokenizer before launching the worker\")\n        }\n\n")
content = replace_once(content, /        } else if fm.fileExists\(atPath: speechTokenizerPath.path\) \{[\s\S]*?(?=        } else \{)/, '')
# Install-time, data-only conversion remains explicitly callable, never automatic.
content = replace_once(content, /    private static func generateTokenizerJson\(/, '    public static func generateTokenizerJson(')
File.write(qwen, "// Modified for OpenScreenReader: local-only loading; install-time tokenizer preparation.\n" + content)
puts 'Pinned offline Qwen subset staged; no model loaded.'
