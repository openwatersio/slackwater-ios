require "yaml"
workflow = YAML.safe_load(File.read(File.expand_path("../.github/workflows/nightly.yml", __dir__)), aliases: true)
release = workflow.fetch("jobs").fetch("release")
checkout = release.fetch("steps").find { |step| step["uses"]&.start_with?("actions/checkout@") }
raise "nightly must check out the immutable trigger commit" unless checkout.dig("with", "ref") == "${{ github.sha }}"
raise "nightly requires Actions read permission" unless release.dig("permissions", "actions") == "read"
raise "nightly requires release write permission" unless release.dig("permissions", "contents") == "write"
puts "nightly workflow checks passed"
