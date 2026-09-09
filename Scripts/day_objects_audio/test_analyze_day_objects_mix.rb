#!/usr/bin/env ruby
# Compile the CLI and its behavioral checks together; no audio files are read.
require 'tmpdir'
require 'fileutils'

root = File.expand_path('../..', __dir__)
diagnostics = File.join(root, 'StepsTrader/Experiments/DayObjects/Sound/Diagnostics')
Dir.mktmpdir('day-objects-cli-tests-') do |directory|
  main = File.join(directory, 'main.swift')
  source = File.read(File.join(__dir__, 'analyze_day_objects_mix.swift'))
  checks = File.read(File.join(__dir__, 'test_analyze_day_objects_mix.swift'))
  File.write(main, source + "\n" + checks)
  binary = File.join(directory, 'cli-tests')
  sources = %w[DayObjectsLoudnessAnalyzer.swift DayObjectsMixQualityReport.swift DayObjectsMixQualityAnalyzer.swift]
  args = ['xcrun', 'swiftc', '-D', 'DEBUG', '-D', 'DAY_OBJECTS_ANALYZER_COMPILED',
          '-D', 'DAY_OBJECTS_ANALYZER_TESTING', *sources.map { |name| File.join(diagnostics, name) }, main, '-o', binary]
  abort('CLI test compilation failed') unless system(*args)
  abort('CLI behavioral tests failed') unless system(binary)
end
