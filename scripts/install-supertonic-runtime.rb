#!/usr/bin/env ruby
# Explicit local development installation. No downloads, replacement, or app-time setup.
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

abort 'Usage: ruby scripts/install-supertonic-runtime.rb VERIFIED_COMPARISON_ROOT PYTHON UV' unless ARGV.length == 3
source, python, uv = ARGV.map { |path| File.expand_path(path) }
repo = File.expand_path('..', __dir__)
manifest_path = File.join(repo, 'docs/research/supertonic-comparison-manifest.json')
manifest = JSON.parse(File.read(manifest_path))
root = File.join(Dir.home, 'Library/Application Support/OpenScreenReader')
destination = File.join(root, 'SupertonicRuntime')
model = File.join(root, 'DevelopmentModels/supertonic-3-3cadd1ee')
abort 'Existing Supertonic installation left untouched' if File.exist?(destination) || File.exist?(model)
abort 'Missing explicit local Python/uv executable' unless [python, uv].all? { |path| File.executable?(path) }
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
stage = Dir.mktmpdir('.supertonic-staging-', root)
venv = File.join(stage, 'venv')
abort "Inspect incomplete staging at #{stage}" unless system(uv, 'venv', '--offline', '--python', python, venv)
packages = %w[onnxruntime==1.23.2 numpy==2.2.6 coloredlogs==15.0.1 flatbuffers==25.12.19 humanfriendly==10.0 mpmath==1.3.0 packaging==26.3 protobuf==7.36.1 sympy==1.14.0]
abort "Offline package cache incomplete; inspect #{stage}" unless system(uv, 'pip', 'install', '--offline', '--only-binary', ':all:', '--python', File.join(venv, 'bin/python3'), *packages)
FileUtils.cp(File.join(repo, 'Runtime/Supertonic/worker.py'), stage)
FileUtils.cp(manifest_path, File.join(stage, 'model-manifest.json'))
FileUtils.mkdir(File.join(stage, 'upstream'))
%w[helper.py LICENSE README.md].each { |name| FileUtils.cp(File.join(source, 'upstream', name), File.join(stage, 'upstream', name)) }
hashes = Dir.glob(File.join(stage, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort.to_h do |path|
  [path.delete_prefix(stage + '/'), Digest::SHA256.file(path).hexdigest]
end
File.write(File.join(stage, 'installation-receipt.json'), JSON.pretty_generate(
  purpose: 'Supertonic development default; not portable or release-approved',
  model_revision: manifest.fetch('revision'), source_revision: manifest.fetch('runtime_source').fetch('revision'),
  external_python: File.realpath(python), packages: packages, files: hashes
) + "\n")
model_stage = Dir.mktmpdir('.supertonic-model-', File.dirname(model))
manifest.fetch('files').each do |entry|
  target = File.join(model_stage, entry.fetch('path'))
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(File.join(source, 'model', entry.fetch('path')), target)
end
File.rename(model_stage, model)
File.rename(stage, destination)
puts 'PASS: pinned Supertonic runtime installed offline; existing Qwen runtime untouched'
puts 'Development only: Python base interpreter remains external; release packaging is not complete'
