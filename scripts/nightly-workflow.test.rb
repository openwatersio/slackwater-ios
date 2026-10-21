require "yaml"
workflow = YAML.safe_load(File.read(File.expand_path("../.github/workflows/nightly.yml", __dir__)), aliases: true)
release = workflow.fetch("jobs").fetch("release")
checkouts = release.fetch("steps").select { |step| step["uses"]&.start_with?("actions/checkout@") }
raise "release validation must come from the trigger commit" unless checkouts.first.dig("with", "ref") == "${{ github.sha }}"
checkout = checkouts.last
raise "nightly must check out the selected green commit" unless checkout.dig("with", "ref") == "${{ needs.authorize.outputs.sha }}"
authorize = workflow.fetch("jobs").fetch("authorize")
raise "selection needs Actions read permission" unless authorize.dig("permissions", "actions") == "read"
raise "selection must export the commit to release" unless authorize.dig("outputs", "sha") == "${{ steps.select.outputs.sha }}"
raise "no candidate must skip release" unless release.fetch("if").include?("needs.authorize.outputs.sha != ''")
raise "nightly requires Actions read permission" unless release.dig("permissions", "actions") == "read"
raise "nightly requires release write permission" unless release.dig("permissions", "contents") == "write"
puts "nightly workflow checks passed"
