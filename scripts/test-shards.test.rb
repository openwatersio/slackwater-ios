require "yaml"
require "json"

root = File.expand_path("..", __dir__)
workflow = YAML.safe_load(File.read("#{root}/.github/workflows/ci.yml"), aliases: true)
run_name = workflow.fetch("run-name")
raise "CI run name must preserve the PR marker and complete expression" unless run_name.include?("format('CI · PR \#{0}', github.event.number)") && run_name.end_with?("}}")
app = workflow.fetch("jobs").fetch("app")
shards = app.fetch("strategy").fetch("matrix").fetch("shard")
raise "keep the six release validation shards" unless shards.map { |s| s.fetch("name") } == %w[offline list transition detail premium rest]
raise "rest must remain a catch-all" if shards.last.key?("only")
# Nightly releases only commits whose every app job passed, so it must name every shard.
nightly = File.read("#{root}/scripts/nightly-validation.py")[/for shard in \(([^)]*)\)/, 1].to_s.scan(/"(\w+)"/).flatten
raise "nightly-validation.py requires shards #{nightly}, not the matrix's" unless nightly == shards.map { |s| s.fetch("name") }
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
(tests + ["SlackwaterUITests/NewTests/testNew", "SlackwaterUITests/SettingsLayoutTests/testNew",
          "SlackwaterUITests/PrintableTablesUITests/testNew"]).each do |test|
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

# The Studio path: one job per device on the self-hosted runners, named as
# Nightly's validator expects, and gated so exactly one path runs.
jobs = workflow.fetch("jobs")
studio = jobs.fetch("studio") { raise "missing the studio job" }
raise "studio must target the Studio's labels" unless studio.fetch("runs-on") == %w[self-hosted macOS studio]
devices_expr = studio.fetch("strategy").fetch("matrix").fetch("device")
raise "studio must pick devices the way app does" unless devices_expr == %q(${{ fromJSON(github.event_name == 'push' && '["iPhone", "iPad"]' || '["iPhone"]') }})
studio_devices = devices_expr.scan(/'(\[[^\]]*\])'/).flatten.flat_map { |list| JSON.parse(list) }.uniq
raise "studio devices are #{studio_devices}, not iPhone and iPad" unless studio_devices.sort == %w[iPad iPhone]
studio_jobs = File.read("#{root}/scripts/nightly-validation.py")[/^STUDIO_JOBS = frozenset\(\{([^}]*)\}\)/, 1].to_s.scan(/"([^"]+)"/).flatten
names = studio_devices.map { |device| studio.fetch("name").gsub("${{ matrix.device }}", device) }
raise "studio names #{names} are not nightly-validation.py's #{studio_jobs}" unless names.sort == studio_jobs.sort && !names.empty?
studio_env = studio.fetch("steps").flat_map { |s| (s["env"] || {}).keys } + (studio["env"] || {}).keys
# Steps can also set env through $GITHUB_ENV, so read their scripts too.
studio_runs = studio.fetch("steps").map { |s| s.fetch("run", "") }.join("\n")
%w[SLACKWATER_WORKERS SLACKWATER_NO_CLONE TEST_RUNNER_SLACKWATER_PERF_SCALE SLACKWATER_SIM_OS].each do |var|
  raise "studio must leave #{var} to scripts/test.sh" if studio_env.include?(var) || studio_runs.include?(var)
end
# Both paths assert the same Xcode, the one the xcode-27 image carries.
raise "the workflow must pin CI_XCODE_VERSION" unless workflow.dig("env", "CI_XCODE_VERSION").to_s.match?(/\A\d+\.\d+(\.\d+)?\z/)
[["studio", studio], ["build", jobs.fetch("build")]].each do |label, job|
  xcode_check = job.fetch("steps")[1].fetch("run", "")
  raise "#{label} must check xcodebuild -version right after checkout" unless job.fetch("steps")[0].fetch("uses", "").start_with?("actions/checkout@") && xcode_check.include?("xcodebuild -version") && xcode_check.include?('"Xcode $CI_XCODE_VERSION"')
end
raise "studio must clean its slot first and last" unless [studio.fetch("steps")[2], studio.fetch("steps").last].all? { |s| s.fetch("run", "").include?("cleanup-slot.sh") } && studio.fetch("steps").last["if"] == "always()"
# Between jobs the Studio runs install.sh's copies of the runner scripts, so
# every job compares them with the checkout, right after the first cleanup.
drift = studio.fetch("steps")[3]
drift_run = drift.fetch("run", "")
raise "studio must check its installed runner scripts after the first cleanup" unless drift["name"] == "Installed runner scripts match the checkout" &&
  drift_run.include?('dirname "$ACTIONS_RUNNER_HOOK_JOB_STARTED"') && drift_run.include?("cmp -s") &&
  drift_run.include?("sh scripts/ci-runner/install.sh") && drift_run.include?('[ -z "${ACTIONS_RUNNER_HOOK_JOB_STARTED:-}" ]') &&
  %w[hook-job-started.sh cleanup-slot.sh reregister.sh].all? { |script| drift_run.include?(script) }
# build.if and studio.if must stay exact complements, or a run takes both
# paths or neither. An unquoted `true` compares a string output to a boolean
# and is never equal, so it would silently route every run hosted.
raise "studio must run exactly when route picks it" unless studio.fetch("if") == "needs.route.outputs.studio == 'true'"
raise "the hosted build must yield to the Studio" unless jobs.fetch("build").fetch("if") == "needs.changes.outputs.app == 'true' && needs.route.outputs.studio != 'true'"
# The route's trust rule must match scripts/ci-runner/hook-job-started.sh.
trusted = jobs.fetch("route").fetch("steps").first.fetch("env").fetch("TRUSTED")
raise "route must trust a push to main or a person's same-repository, non-Dependabot pull request" unless trusted == "${{ (github.event_name == 'push' && github.ref == 'refs/heads/main') || (github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository && github.event.pull_request.user.type == 'User' && !startsWith(github.event.pull_request.head.ref, 'dependabot/')) }}"
raise "Required checks must wait for both paths" unless (%w[route studio build app] - jobs.fetch("required").fetch("needs")).empty?

%w[build app studio].each do |job|
  raise "cancel only obsolete PR validation" unless workflow.fetch("jobs").fetch(job).dig("concurrency", "cancel-in-progress") == "${{ github.event_name == 'pull_request' }}"
end
# Main attempts must not share pending slots; PR attempts must share them.
run_or_ref = "${{ github.event_name == 'push' && github.run_id || github.ref }}"
%w[build app studio].each do |job|
  template = workflow.fetch("jobs").fetch(job).dig("concurrency", "group")
  # The Studio's iPhone job shares the hosted build's group, so a PR that
  # switches paths between pushes still cancels the other path's old job.
  expected = "ci-#{job == 'studio' ? 'build' : job}-#{run_or_ref}"
  expected += "-${{ matrix.shard.name }}-${{ matrix.device }}" if job == "app"
  expected += "${{ matrix.device == 'iPad' && '-ipad' || '' }}" if job == "studio"
  raise "main #{job} groups must be unique per run" unless template == expected
  group = ->(event, run, ref) { template.sub(run_or_ref, event == "push" ? run.to_s : ref) }
  raise "main attempts share a pending slot" if group.call("push", 1, "refs/heads/main") == group.call("push", 2, "refs/heads/main")
  raise "obsolete PR attempts cannot cancel" unless group.call("pull_request", 1, "refs/pull/1/merge") == group.call("pull_request", 2, "refs/pull/1/merge")
  raise "unrelated PRs share a slot" if group.call("pull_request", 1, "refs/pull/1/merge") == group.call("pull_request", 2, "refs/pull/2/merge")
end
puts "main groups preserve pending siblings; PR groups cancel obsolete attempts"
puts "#{tests.size} test methods run exactly once across six shards; new classes and split-class methods reach rest"
