import contextlib
import copy
import importlib.util
import io
import sys

sys.dont_write_bytecode = True
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("validation", Path(__file__).with_name("nightly-validation.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)
sha = "a" * 40
run = dict(id=123, run_attempt=2, head_sha=sha, head_branch="main", event="push", status="completed", conclusion="success")
names = ["Build for testing"] + [f"App tests · {s}{d}" for s in ("offline", "list", "transition", "detail", "rest") for d in ("", " · iPad")]
jobs = [dict(id=i, run_attempt=1, name=n, status="completed", conclusion="success") for i, n in enumerate(names)]


def check(candidate, app_jobs, accepted):
    responses = [[{"workflow_runs": candidate}], [{"jobs": app_jobs[:5]}, {"jobs": app_jobs[5:]}]]
    with patch.object(validation, "api", side_effect=responses) as api, contextlib.redirect_stdout(io.StringIO()):
        try:
            validation.validate(sha, "example/app")
        except ValueError:
            assert not accepted
        else:
            assert accepted
        assert f"head_sha={sha}&branch=main&event=push" in api.call_args_list[0].args[0]
        if len(api.call_args_list) == 2:
            assert "/runs/123/jobs?filter=all&" in api.call_args_list[1].args[0]


check([run], jobs, True)
# Failed-job reruns retain untouched successes and use the newest shard result.
check([run], jobs + [{**jobs[-1], "id": 100, "run_attempt": 2}], True)
check([run], jobs + [{**jobs[-1], "id": 100, "run_attempt": 2, "conclusion": "failure"}], False)
check([run], [{**jobs[-1], "id": 100, "run_attempt": 2, "conclusion": "failure"}] + jobs, False)
check([], jobs, False)
check([run], [], False)  # Docs-only green is not full app validation.
check([run], jobs[:-1], False)  # Missing iPad shard.
for conclusion in ("failure", "cancelled", None):
    check([{**run, "conclusion": conclusion}], jobs, False)
check([{**run, "status": "in_progress"}], jobs, False)
check([{**run, "head_sha": "b" * 40}], jobs, False)
check([{**run, "event": "pull_request"}], jobs, False)
check([{**run, "head_branch": "feature"}], jobs, False)
for status, conclusion in (("completed", "failure"), ("completed", "cancelled"), ("queued", None), ("completed", "skipped")):
    changed = copy.deepcopy(jobs)
    changed[-1].update(status=status, conclusion=conclusion)
    check([run], changed, False)
print("nightly exact-commit validation checks passed")
