require "yaml"

workflow = YAML.safe_load(File.read(File.expand_path("../.github/workflows/promote-nightly.yml", __dir__)), aliases: true)
triggers = workflow["on"] || workflow[true]
raise "missing required build input" unless triggers.dig("workflow_dispatch", "inputs", "build", "required") == true
raise "promotion must be dispatch-only" unless triggers.keys == ["workflow_dispatch"]
raise "promotion must run in one job" unless workflow["jobs"].keys == ["promote"]
job = workflow.dig("jobs", "promote")
raise "promotion lacks protected credentials" unless job["environment"] == "testflight"
raise "promotion requests PR permissions" if job.dig("permissions", "pull-requests")
install = job["steps"].index { |step| step["run"] == "sudo apt-get update && sudo apt-get install -y zsh" }
invocation = job["steps"].index { |step| step["run"]&.include?('zsh scripts/promote-nightly.sh "$BUILD"') }
raise "promotion must install zsh before using it" unless install && invocation && install < invocation
puts "promotion workflow checks passed"
