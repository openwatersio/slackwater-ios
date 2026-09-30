require "yaml"

path = File.expand_path("../.github/workflows/promote-nightly.yml", __dir__)
workflow = YAML.safe_load(File.read(path), aliases: true)
triggers = workflow["on"] || workflow[true]
raise "missing required build input" unless triggers.dig("workflow_dispatch", "inputs", "build", "required") == true
raise "push is not limited to main" unless triggers.dig("push", "branches") == ["main"]
raise "push is not limited to promotion records" unless triggers.dig("push", "paths") == ["docs/release-promotions/*.json"]

prepare = workflow.dig("jobs", "prepare")
release = workflow.dig("jobs", "release")
raise "prepare cannot create pull requests" unless prepare.dig("permissions", "pull-requests") == "write"
raise "prepare cannot push its branch" unless prepare.dig("permissions", "contents") == "write"
raise "release cannot create GitHub releases" unless release.dig("permissions", "contents") == "write"
raise "prepare lacks protected credentials" unless prepare["environment"] == "testflight"
raise "release lacks protected credentials" unless release["environment"] == "testflight"

puts "promotion workflow checks passed"
