require "yaml"

workflow = YAML.safe_load(File.read(File.expand_path("../.github/workflows/sync-appstore-releases.yml", __dir__)), aliases: true)
raise "sync CLI requires this workflow name" unless workflow["name"] == "Sync App Store releases"
triggers = workflow["on"] || workflow[true]
raise "sync must check hourly" unless triggers.dig("schedule", 0, "cron") == "43 * * * *"
raise "manual sync must default to dry run" unless triggers.dig("workflow_dispatch", "inputs", "dry_run", "default") == true
job = workflow.dig("jobs", "sync")
raise "sync must run only on trusted main" unless job["if"] == "github.repository == 'openwatersio/slackwater-ios' && github.ref == 'refs/heads/main'"
raise "sync lacks protected credentials" unless job["environment"] == "testflight"
raise "sync must use Ubuntu" unless job["runs-on"] == "ubuntu-24.04"
raise "sync must serialize runs" unless workflow.dig("concurrency", "cancel-in-progress") == false
raise "sync lacks release permissions" unless job.dig("permissions", "contents") == "write"
checkout = job["steps"].find { |s| s["uses"]&.start_with?("actions/checkout@") }
raise "sync needs all Nightly tags" unless checkout.dig("with", "fetch-depth") == 0
raise "reruns must use current reviewed notes" unless checkout.dig("with", "ref") == "refs/heads/main"
raise "sync should fetch only release sources" unless checkout.dig("with", "sparse-checkout").include?("docs/release-notes")
owner = job["steps"].find { |s| s["name"] == "Require an owner for manual dispatch or rerun" }
raise "owner gate must cover reruns while allowing unattended schedules" unless owner["if"] == "github.event_name == 'workflow_dispatch' || github.run_attempt > 1"
puts "App Store release sync workflow checks passed"
