import importlib.util
import sys
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
source = Path(__file__).with_name("cancel-closed-ci.py")
assert source.exists(), "Closed pull requests do not cancel their obsolete CI runs"
spec = importlib.util.spec_from_file_location("cleanup", source)
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)

pr = dict(number=617, state="closed", closed_at="2026-10-05T17:15:06Z",
          head=dict(ref="test/deterministic-state", sha="a" * 40, repo=dict(id=123)))
event = dict(action="closed", repository=dict(full_name="example/app"), pull_request=pr)
run = dict(id=99, workflow_id=42, path=".github/workflows/ci.yml", event="pull_request",
           display_title="CI · PR #617", head_branch="test/deterministic-state",
           head_sha="a" * 40, head_repository=dict(id=123), status="in_progress",
           created_at="2026-10-05T16:43:23Z", run_started_at="2026-10-05T16:43:23Z",
           run_attempt=1, pull_requests=[])


def exercise(candidate=run, current=pr, refreshed=None, listed=None, completes_on_cancel=False):
    cancelled = []
    reads = []

    def api(path, method="GET"):
        reads.append((path, method))
        if path.endswith("/cancel"):
            assert method == "POST"
            if completes_on_cancel:
                raise cleanup.subprocess.CalledProcessError(1, ["gh", "api"])
            cancelled.append(int(path.split("/")[-2]))
            return None
        if path.endswith("/pulls/617"):
            return current
        if path.endswith("/workflows/ci.yml"):
            return dict(id=42)
        if "event=pull_request" in path:
            assert "per_page=100" in path
            return listed if listed is not None else [{"workflow_runs": [candidate]}]
        if path.endswith("/runs/99"):
            if completes_on_cancel and any(path.endswith("/cancel") for path, _ in reads):
                return {**candidate, "status": "completed"}
            return refreshed if refreshed is not None else candidate
        raise AssertionError(path)

    with patch.object(cleanup, "api", side_effect=api):
        cleanup.cancel_closed_pr(event)
    return cancelled


assert exercise() == [99]  # Merged runs can have an empty pull_requests association.
for change in (
    dict(workflow_id=43), dict(path=".github/workflows/nightly.yml"), dict(event="push"),
    dict(display_title="CI · PR #618"), dict(display_title="A PR title without a marker"),
    dict(head_repository=dict(id=124)), dict(head_branch="another-branch"),
    dict(head_sha="b" * 40), dict(status="completed"),
    dict(created_at=pr["closed_at"]), dict(run_started_at=pr["closed_at"]),
    dict(run_started_at="2026-10-05T17:16:00Z"), dict(run_started_at=None),
):
    assert exercise(candidate={**run, **change}) == [], change
assert exercise(current={**pr, "state": "open", "closed_at": None}) == []
assert exercise(current={**pr, "closed_at": "2026-10-05T17:20:00Z"}) == []
assert exercise(refreshed={**run, "run_attempt": 2}) == []
assert exercise(refreshed={**run, "status": "completed"}) == []
assert exercise(listed=[{"workflow_runs": []}, {"workflow_runs": [run]}]) == [99]
assert exercise(completes_on_cancel=True) == []

with patch.object(cleanup, "api", return_value=None) as api:
    cleanup.cancel_closed_pr({**event, "action": "reopened"})
    api.assert_not_called()

with patch.object(cleanup.subprocess, "check_output", return_value='[{"workflow_runs": []}]') as command:
    assert cleanup.api("repos/example/app/actions/workflows/ci.yml/runs?event=pull_request") == [{"workflow_runs": []}]
    assert command.call_args.args[0] == ["gh", "api", "--method", "GET", "repos/example/app/actions/workflows/ci.yml/runs?event=pull_request", "--paginate", "--slurp"]
with patch.object(cleanup.subprocess, "check_output", return_value=""):
    assert cleanup.api("repos/example/app/actions/runs/99/cancel", "POST") is None

print("Closed-PR CI cancellation checks passed")
