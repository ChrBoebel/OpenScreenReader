# The app's worker sandbox for developer scripts. Mirrors WorkerSandbox.arguments in
# OpenScreenReaderApp/WorkerSandbox.swift: the same deny-default profile (read from its
# byte-identical copy Runtime/Dictation/worker.sb) with the same canonical parameters.
module WorkerSandbox
  PROFILE = File.expand_path('../Runtime/Dictation/worker.sb', __dir__)

  # `sandbox-exec` command up to and including the executable; nil when a path does not exist.
  # The executable may read RESOURCES, MODEL_ROOT (defaults to RESOURCES) and its own prefix,
  # PYTHON_HOME, two levels above the resolved binary; it may not write, fork or use the network.
  def self.command(resources:, executable:, model_root: nil)
    # Seatbelt matches resolved paths; realpath keeps /private, like the app's canonicalPath.
    root, models, interpreter = [resources, model_root || resources, executable].map { |path| File.realpath(path) }
    home = File.dirname(File.dirname(interpreter))
    # An executable directly below / would make the whole disk readable.
    return nil if home == '/'
    ['/usr/bin/sandbox-exec', '-p', File.read(PROFILE),
     '-D', "RESOURCES=#{root}", '-D', "MODEL_ROOT=#{models}",
     '-D', "PYTHON=#{interpreter}", '-D', "PYTHON_HOME=#{home}",
     executable.to_s]
  rescue SystemCallError
    nil
  end
end
