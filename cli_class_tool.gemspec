# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'cli_class_tool'

  # Extract version dynamically from git, falling back to 0.1.0 if not in a git repo or no tags exist
  version_str = `git describe --tags 2>/dev/null`.chomp().gsub(/^v/, "").gsub(/-([0-9]+)-g/, '-\1.g')
  s.version     = version_str.empty? ? '0.1.0' : version_str

  # Extract date dynamically from git, falling back to today's date if no commits exist
  date_str = `git show HEAD --format='format:%ci' -s 2>/dev/null | awk '{ print $1}'`.chomp()
  s.date        = date_str.empty? ? Time.now.strftime('%Y-%m-%d') : date_str

  s.summary     = "A lightweight object-oriented framework for class-based command-line interface (CLI) applications."
  s.description = "CLIClassTool decouples the generic execution, logging, and action routing engine from project-specific business logic."
  s.authors     = ["Nicolas Morey-Chaisemartin"]
  s.email       = 'nmoreychaisemartin@suse.de'
  s.homepage    = 'https://github.com/nmorey/cli_class_tool'
  s.license     = 'GPL-3.0-or-later'
  s.required_ruby_version = '>= 2.7'

  s.files       = [
    "LICENSE",
    "README.md"
  ] + Dir['lib/**/*.rb'].keep_if { |file| File.file?(file) }

  # Permissive development dependencies to use pre-installed system gems
  s.add_development_dependency 'rake', '>= 12.0'
  s.add_development_dependency 'minitest', '>= 5.0'
  s.add_development_dependency 'yard', '>= 0.8'
  s.add_development_dependency 'redcarpet', '>= 3.0'
  s.add_development_dependency 'rdoc', '>= 6.0'
end
