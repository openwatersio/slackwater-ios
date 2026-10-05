require "yaml"
require "json"

root = File.expand_path("..", __dir__)
workflow = YAML.safe_load(File.read("#{root}/.github/workflows/ci.yml"), aliases: true)
app = workflow.fetch("jobs").fetch("app")
shards = app.fetch("strategy").fetch("matrix").fetch("shard")
raise "keep the five release validation shards" unless shards.map { |s| s.fetch("name") } == %w[offline list transition detail rest]
raise "rest must remain a catch-all" if shards.last.key?("only")
selectors = shards.flat_map { |s| %w[only skip].flat_map { |key| s.fetch(key, "").split(",") } }

tests = JSON.parse(File.read("#{root}/TestPlans/Slackwater.xctestplan")).fetch("testTargets").flat_map do |entry|
  target = entry.fetch("target").fetch("name")
  Dir.glob("#{root}/#{target}/*.swift").flat_map do |path|
    source = File.read(path)
    klass = source[/class (\w+)\s*:\s*(?:XCTestCase|ScreenshotTestCase|ShotWalk)\b/, 1]
    next [] unless klass
    source.scan(/func (test\w+)\s*\(/).flatten.map { |method| "#{target}/#{klass}/#{method}" }
  end
end
matches = ->(test, selector) { test == selector || test.start_with?("#{selector}/") }
selectors.uniq.each do |selector|
  raise "stale selector #{selector}" unless tests.any? { |test| matches.call(test, selector) }
end
# A class or method introduced tomorrow must still run exactly once.
(tests + ["SlackwaterUITests/NewTests/testNew", "SlackwaterUITests/SettingsLayoutTests/testNew"]).each do |test|
  owners = shards.select do |shard|
    only = shard.fetch("only", "").split(",")
    skip = shard.fetch("skip", "").split(",")
    (only.empty? || only.any? { |selector| matches.call(test, selector) }) &&
      skip.none? { |selector| matches.call(test, selector) }
  end
  raise "#{test} runs in #{owners.map { |s| s.fetch('name') }}" unless owners.size == 1
end
raise "hosted runners need one worker" unless app.fetch("steps").select { |s| s["env"]&.key?("SLACKWATER_WORKERS") }.all? { |s| s.fetch("env").fetch("SLACKWATER_WORKERS") == 1 }
raise "docs-only workflows must not cancel app validation" if workflow.key?("concurrency")
%w[build app].each do |job|
  raise "cancel only obsolete PR validation" unless workflow.fetch("jobs").fetch(job).dig("concurrency", "cancel-in-progress") == "${{ github.event_name == 'pull_request' }}"
end
puts "#{tests.size} test methods run exactly once across five shards; new classes and Settings methods reach rest"
