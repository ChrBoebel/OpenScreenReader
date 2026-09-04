#!/usr/bin/env ruby
# Explicit developer action; never called by the app and never downloads content.
require 'fileutils'
require 'digest'
require 'json'
require 'tmpdir'

abort 'Usage: ruby scripts/install-development-runtime.rb XCODE_RELEASE_PRODUCTS_DIRECTORY' unless ARGV.length == 1
products = File.expand_path(ARGV[0])
repo = File.expand_path('..', __dir__)
root = File.join(Dir.home, 'Library/Application Support/OpenScreenReader')
destination = File.join(root, 'DevelopmentRuntime')
model = File.join(root, 'DevelopmentModels/qwen3-tts-0.6b-customvoice-4bit-08c72cad')
abort 'Existing runtime left untouched; inspect before replacing it' if File.exist?(destination)
abort 'Model verification failed' unless system('/bin/bash', File.join(__dir__, 'download-qwen.sh'), model, '--verify-only')
tokenizer_hash = '39c94a2d71ba8b0d33757e052581c63feaca79f7639421baedd595493d4fccc3'
abort 'Prepare the pinned tokenizer first' unless File.file?(File.join(model, 'tokenizer.json')) &&
  Digest::SHA256.file(File.join(model, 'tokenizer.json')).hexdigest == tokenizer_hash
abort 'Collect runtime notices first' unless File.file?(File.join(repo, 'Runtime/.generated/Notices/receipt.json'))
files = %w[OpenScreenReaderSpeechWorker mlx-swift_Cmlx.bundle swift-transformers_Hub.bundle swift-crypto_Crypto.bundle]
files.each { |file| abort "Missing build product: #{file}" unless File.exist?(File.join(products, file)) }
stage = Dir.mktmpdir('.runtime-staging-', root)
begin
  files.each { |file| FileUtils.cp_r(File.join(products, file), File.join(stage, file)) }
  FileUtils.cp_r(File.join(repo, 'Runtime/.generated/Notices'), File.join(stage, 'Notices'))
  FileUtils.cp(File.join(repo, 'Runtime/Package.resolved'), File.join(stage, 'Package.resolved'))
  hashes = Dir.glob(File.join(stage, '**/*')).select { |path| File.file?(path) }.sort.to_h do |path|
    [path.delete_prefix(stage + '/'), Digest::SHA256.file(path).hexdigest]
  end
  File.write(File.join(stage, 'installation-receipt.json'), JSON.pretty_generate(
    purpose: 'Local development only; not release-approved',
    model_revision: '08c72cad5e2fd0f41730c8bd1f28149585e46361',
    tokenizer_sha256: tokenizer_hash, files: hashes
  ) + "\n")
  File.rename(stage, destination)
rescue
  warn "Installation stopped; inspect staging directory #{stage}. Existing runtime was not replaced."
  raise
end
puts 'Development runtime installed with pinned model verification and third-party notices.'
