# frozen_string_literal: true

require 'bundler/setup'
require 'rake/testtask'
require 'yard'

# Define test task using Minitest
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.ruby_opts << '-rtest_helper'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

# Define whitespace lint task
desc "Check for trailing whitespace"
task :lint_whitespace do
  puts "Checking for trailing whitespace..."
  # Scan all lib, test, Rakefile, Gemfile, gemspec, and markdown files
  files = Dir.glob("{lib,test}/**/*") + Dir.glob("*.{gemspec,md,rb}") + ["Gemfile", "Rakefile"]
  errors = []

  files.each do |file|
    next if File.directory?(file)
    next if file.end_with?('~') # Ignore backup files
    File.foreach(file).with_index do |line, index|
      if line =~ /[ \t]+$/
        errors << "#{file}:#{index + 1} has trailing whitespace"
      end
    end
  end

  if errors.any?
    puts errors.join("\n")
    fail "Found trailing whitespace in #{errors.size} lines."
  else
    puts "No trailing whitespace found."
  end
end

# Define YARD documentation task
YARD::Rake::YardocTask.new(:yard) do |t|
  # Options are read from .yardopts automatically
end

# Set default task to run both whitespace linting and unit tests
task default: [:lint_whitespace, :test]
