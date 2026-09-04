#!/usr/bin/env ruby
# Collect pinned dependency notices for the development artifact, not a release SBOM.
require 'json'
require 'digest'
require 'fileutils'

runtime = File.expand_path('../Runtime', __dir__)
lock = JSON.parse(File.read(File.join(runtime, 'Package.resolved')))
expected = %w[mlx-swift mlx-swift-lm swift-asn1 swift-collections swift-crypto swift-jinja swift-numerics swift-syntax swift-transformers yyjson]
abort 'Unexpected dependency closure; repeat the license review' unless lock.fetch('pins').map { |pin| pin.fetch('identity') }.sort == expected.sort
destination = File.join(runtime, '.generated/Notices')
FileUtils.mkdir_p(destination)
receipt = []
lock.fetch('pins').each do |pin|
  name = pin.fetch('identity')
  checkout = File.join(runtime, '.build/checkouts', name)
  revision = IO.popen(['/usr/bin/git', '-C', checkout, 'rev-parse', 'HEAD'], &:read).strip
  abort "Wrong checkout: #{name}" unless revision == pin.fetch('state').fetch('revision')
  paths = Dir.glob(File.join(checkout, '{LICENSE*,NOTICE*,ACKNOWLEDGMENTS.md}'))
  if name == 'mlx-swift'
    paths += Dir.glob(File.join(checkout, 'Source/Cmlx/{mlx,mlx-c,metal-cpp,json,fmt}/{LICENSE*,ACKNOWLEDGMENTS.md}'))
  end
  abort "Missing license: #{name}" unless paths.any? { |path| File.basename(path).start_with?('LICENSE') }
  paths.sort.each do |path|
    relative = path.delete_prefix(checkout + '/')
    target = File.join(destination, name, relative)
    FileUtils.mkdir_p(File.dirname(target))
    if File.exist?(target)
      abort "Existing notice differs: #{name}/#{relative}" unless Digest::SHA256.file(target).hexdigest == Digest::SHA256.file(path).hexdigest
    else
      FileUtils.cp(path, target)
    end
    receipt << { package: name, revision: revision, path: relative, sha256: Digest::SHA256.file(path).hexdigest }
  end
end
FileUtils.cp(File.join(runtime, '.generated/LICENSE-mlx-audio-swift'), File.join(destination, 'LICENSE-mlx-audio-swift'))
File.write(File.join(destination, 'receipt.json'), JSON.pretty_generate(receipt) + "\n")
puts "Collected #{receipt.length} pinned license/notice files plus the Qwen subset's MIT license."
