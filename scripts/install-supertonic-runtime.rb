#!/usr/bin/env ruby
# Explicit local development installation. No downloads, replacement, or app-time setup.
# BUILT_SPEECH_RUNTIME comes from:
#   python3 scripts/build-python-runtime.py --runtime speech --architecture "$(uname -m)" --cache DIR --output DIR
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

abort 'Usage: ruby scripts/install-supertonic-runtime.rb VERIFIED_COMPARISON_ROOT BUILT_SPEECH_RUNTIME' unless ARGV.length == 2
source, built = ARGV.map { |path| File.expand_path(path) }
repo = File.expand_path('..', __dir__)
manifest_path = File.join(repo, 'docs/research/supertonic-comparison-manifest.json')
manifest = JSON.parse(File.read(manifest_path))
root = File.join(Dir.home, 'Library/Application Support/OpenScreenReader')
destination = File.join(root, 'SupertonicRuntime')
model = File.join(root, 'DevelopmentModels/supertonic-3-3cadd1ee')
abort 'Existing Supertonic installation left untouched' if File.exist?(destination) || File.exist?(model)
inventory = JSON.parse(File.read(File.join(built, 'installed-packages.json')))
provenance = JSON.parse(File.read(File.join(built, 'runtime-provenance.json')))
lock = File.join(repo, provenance.fetch('lock'))
abort 'Not a speech runtime from scripts/build-python-runtime.py' unless inventory['runtime'] == 'speech' &&
  File.file?(File.join(built, 'THIRD-PARTY-NOTICES.txt')) && File.executable?(File.join(built, 'bin/python3'))
abort 'Runtime was built from a different lock; rebuild it' unless Digest::SHA256.file(lock).hexdigest == provenance.fetch('lock_sha256')
manifest.fetch('files').each do |entry|
  path = File.join(source, 'model', entry.fetch('path'))
  abort 'Pinned model size mismatch' unless File.file?(path) && File.size(path) == entry.fetch('bytes')
  valid = if entry['sha256']
    Digest::SHA256.file(path).hexdigest == entry['sha256']
  else
    Digest::SHA1.hexdigest("blob #{File.size(path)}\0" + File.binread(path)) == entry.fetch('git_blob')
  end
  abort 'Pinned model hash mismatch' unless valid
end
helper = File.join(source, 'upstream/helper.py')
abort 'Pinned helper mismatch' unless Digest::SHA256.file(helper).hexdigest == manifest.fetch('runtime_source').fetch('sha256')
abort 'Missing upstream MIT license' unless Digest::SHA256.file(File.join(source, 'upstream/LICENSE')).hexdigest ==
  '0dfe0d0ba84416fe3879d9a34f4909d8d0137c78d1e95834177b0414ac096fa2'
FileUtils.mkdir_p(root)
stage = Dir.mktmpdir('.supertonic-staging-', root)
# The development layout keeps the historical venv/ path; it is a self-contained interpreter.
FileUtils.cp_r(built, File.join(stage, 'venv'), preserve: true)
FileUtils.cp(File.join(repo, 'Runtime/Supertonic/worker.py'), stage)
FileUtils.cp(manifest_path, File.join(stage, 'model-manifest.json'))
FileUtils.mkdir(File.join(stage, 'upstream'))
%w[helper.py LICENSE README.md].each { |name| FileUtils.cp(File.join(source, 'upstream', name), File.join(stage, 'upstream', name)) }
hashes = Dir.glob(File.join(stage, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) && !File.symlink?(path) }.sort.to_h do |path|
  [path.delete_prefix(stage + '/'), Digest::SHA256.file(path).hexdigest]
end
packages = inventory.fetch('packages').map { |item| "#{item.fetch('name')}==#{item.fetch('version')}" }
File.write(File.join(stage, 'installation-receipt.json'), JSON.pretty_generate(
  purpose: 'Supertonic local development installation',
  model_revision: manifest.fetch('revision'), source_revision: manifest.fetch('runtime_source').fetch('revision'),
  runtime_lock: provenance.fetch('lock'), python: inventory.fetch('python').fetch('version'), packages: packages, files: hashes
) + "\n")
model_stage = Dir.mktmpdir('.supertonic-model-', FileUtils.mkdir_p(File.dirname(model)).first)
manifest.fetch('files').each do |entry|
  target = File.join(model_stage, entry.fetch('path'))
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(File.join(source, 'model', entry.fetch('path')), target)
end
File.rename(model_stage, model)
File.rename(stage, destination)
puts 'PASS: pinned Supertonic runtime installed offline from a reproducible hash-locked build'
