#!/usr/bin/env ruby
# Private packaging spike only. No downloads, publishing, or release approval.
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'find'

abort 'Usage: ruby scripts/package-development-app.rb RELEASE_APP --development-only [--dmg]' unless
  (ARGV.length == 2 || (ARGV.length == 3 && ARGV[2] == '--dmg')) && ARGV[1] == '--development-only'
repo = File.expand_path('..', __dir__)
app = File.realpath(ARGV[0])
abort 'Expected OpenScreenReader.app' unless File.basename(app) == 'OpenScreenReader.app' && File.file?(File.join(app, 'Contents/MacOS/OpenScreenReader'))
root = File.join(Dir.home, 'Library/Application Support/OpenScreenReader')
runtime = File.join(root, 'SupertonicRuntime')
receipt = JSON.parse(File.read(File.join(runtime, 'installation-receipt.json')))
manifest_path = File.join(repo, 'docs/research/supertonic-comparison-manifest.json')
manifest = JSON.parse(File.read(manifest_path))
model = File.join(root, 'DevelopmentModels/supertonic-3-3cadd1ee')
manifest.fetch('files').each do |entry|
  path = File.join(model, entry.fetch('path'))
  abort 'Model path escapes its root' unless File.realpath(path).start_with?(File.realpath(model) + '/')
  abort 'Pinned model size mismatch' unless File.size(path) == entry.fetch('bytes')
  valid = entry['sha256'] ? Digest::SHA256.file(path).hexdigest == entry['sha256'] :
    Digest::SHA1.hexdigest("blob #{File.size(path)}\0" + File.binread(path)) == entry.fetch('git_blob')
  abort 'Pinned model hash mismatch' unless valid
end
receipt.fetch('files').each do |relative, expected|
  path = File.join(runtime, relative)
  abort 'Runtime receipt path escapes root' if relative.split('/').include?('..') || relative.start_with?('/')
  abort "Runtime receipt mismatch: #{relative}" unless File.file?(path) && Digest::SHA256.file(path).hexdigest == expected
end
abort 'Install the current project worker first' unless Digest::SHA256.file(File.join(runtime, 'worker.py')).hexdigest == Digest::SHA256.file(File.join(repo, 'Runtime/Supertonic/worker.py')).hexdigest
python_binary = File.realpath(File.join(runtime, 'venv/bin/python3'))
python = File.dirname(File.dirname(python_binary))
abort 'Missing CPython license' unless File.file?(File.join(python, 'lib/python3.12/LICENSE.txt'))

FileUtils.mkdir_p(File.join(repo, '.build'))
stage = Dir.mktmpdir('packaging-', File.join(repo, '.build'))
target = File.join(stage, 'OpenScreenReader.app')
FileUtils.cp_r(app, target)
speech = File.join(target, 'Contents/Resources/Speech')
abort 'Input bundle already contains Speech resources' if File.exist?(speech)
dest = File.join(speech, 'SupertonicRuntime')
FileUtils.mkdir_p(dest)
%w[worker.py upstream].each { |name| FileUtils.cp_r(File.join(runtime, name), dest) }
FileUtils.cp(manifest_path, File.join(dest, 'model-manifest.json'))
FileUtils.mkdir_p(File.join(speech, 'DevelopmentModels'))
FileUtils.cp_r(model, File.join(speech, 'DevelopmentModels'))

# Copy the interpreter and standard library, never unrelated packages from the
# developer's base interpreter. The pinned venv is the sole package closure.
py_dest = File.join(dest, 'python')
FileUtils.mkdir_p(File.join(py_dest, 'bin'))
FileUtils.cp(python_binary, File.join(py_dest, 'bin/python3'))
Find.find(File.join(python, 'lib')) do |source|
  relative = source.delete_prefix(python + '/')
  if %w[site-packages __pycache__ pkgconfig].include?(File.basename(source))
    Find.prune if File.directory?(source)
    next
  end
  destination = File.join(py_dest, relative)
  if File.symlink?(source)
    link = File.readlink(source)
    abort 'Absolute base-interpreter symlink needs a packaging decision' if link.start_with?('/')
    File.symlink(link, destination)
  elsif File.directory?(source)
    FileUtils.mkdir_p(destination)
  else
    FileUtils.cp(source, destination)
  end
end
FileUtils.cp_r(File.join(runtime, 'venv/lib/python3.12/site-packages'), File.join(py_dest, 'lib/python3.12'))

# Seal native code from the inside out. This is ad-hoc signing, not Developer ID.
files = Dir.glob(File.join(speech, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) && !File.symlink?(path) }
files.each do |path|
  magic = File.binread(path, 4).to_s.unpack1('H*')
  next unless %w[cffaedfe cefaedfe feedfacf feedface cafebabe bebafeca].include?(magic)
  abort 'Nested ad-hoc signing failed' unless system('/usr/bin/codesign', '--force', '--sign', '-', path, out: File::NULL, err: File::NULL)
end
Find.find(speech) do |path|
  next unless File.symlink?(path)
  abort 'Bundle contains an external or broken symlink' unless File.realpath(path).start_with?(speech + '/')
end
hashes = files.sort.to_h { |path| [path.delete_prefix(speech + '/'), Digest::SHA256.file(path).hexdigest] }
File.write(File.join(dest, 'installation-receipt.json'), JSON.pretty_generate(
  purpose: 'Private offline packaging experiment. Not approved for redistribution.',
  worker_protocol: 2, model_revision: manifest.fetch('revision'), packages: receipt.fetch('packages'), files: hashes
) + "\n")
FileUtils.cp(File.join(repo, 'LICENSE'), File.join(target, 'Contents/Resources/LICENSE-OpenScreenReader'))
File.write(File.join(target, 'Contents/Resources/DEVELOPMENT-PREVIEW.txt'),
  "Private packaging experiment. Not notarized or approved for distribution.\n" +
  "Model: Supertonic 3, #{manifest.fetch('revision')}, BigScience Open RAIL-M.\n" +
  "Full CPython/native-library provenance and license-chain review remain release gates.\n")
abort 'Bundle signing failed' unless system('/usr/bin/codesign', '--force', '--sign', '-', '--options', 'runtime', target)
abort 'Bundle verification failed' unless system('/usr/bin/codesign', '--verify', '--deep', '--strict', target)
puts "PRIVATE DEVELOPMENT BUNDLE: #{target}"
puts 'No download or publication. Test relocation and offline speech before installation.'
if ARGV[2] == '--dmg'
  File.symlink('/Applications', File.join(stage, 'Applications'))
  image = stage + '.dmg'
  abort 'Development DMG creation failed' unless system('/usr/bin/hdiutil', 'create', '-volname',
    'OpenScreenReader Development', '-srcfolder', stage, '-format', 'UDZO', image)
  puts "PRIVATE DEVELOPMENT DMG: #{image}"
end
