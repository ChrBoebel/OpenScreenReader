#!/usr/bin/env ruby
# Explicit development update of the project-owned worker only. No downloads.
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

abort 'Usage: ruby scripts/update-supertonic-worker.rb' unless ARGV.empty?
runtime = File.join(Dir.home, 'Library/Application Support/OpenScreenReader/SupertonicRuntime')
worker = File.join(runtime, 'worker.py')
receipt_path = File.join(runtime, 'installation-receipt.json')
source = File.expand_path('../Runtime/Supertonic/worker.py', __dir__)
abort 'Missing development runtime' unless [worker, receipt_path].all? { |path| File.file?(path) }
receipt = JSON.parse(File.read(receipt_path))
abort 'Installed worker differs from its receipt; left untouched' unless
  Digest::SHA256.file(worker).hexdigest == receipt.fetch('files').fetch('worker.py')
receipt['files']['worker.py'] = Digest::SHA256.file(source).hexdigest
receipt['worker_protocol'] = 2
Dir.mktmpdir('.worker-update-', runtime) do |stage|
  FileUtils.cp(worker, File.join(stage, 'previous-worker.py'))
  FileUtils.cp(receipt_path, File.join(stage, 'previous-receipt.json'))
  FileUtils.cp(source, File.join(stage, 'worker.py'))
  File.write(File.join(stage, 'receipt.json'), JSON.pretty_generate(receipt) + "\n")
  begin
    File.rename(File.join(stage, 'worker.py'), worker)
    File.rename(File.join(stage, 'receipt.json'), receipt_path)
  rescue StandardError
    FileUtils.cp(File.join(stage, 'previous-worker.py'), worker)
    FileUtils.cp(File.join(stage, 'previous-receipt.json'), receipt_path)
    raise
  end
end
puts 'PASS: project worker and receipt updated; model, helper, interpreter and packages untouched'
