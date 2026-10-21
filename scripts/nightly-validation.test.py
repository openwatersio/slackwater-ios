import contextlib
import copy
import importlib.util
import io
import sys
import subprocess
import tempfile

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

# A real history bounds selection to the trigger, even if main advances while queued.
with tempfile.TemporaryDirectory() as directory:
    def git(*args):
        return subprocess.check_output(["git", "-C", directory, *args], text=True).strip()

    git("init", "-q")
    git("config", "user.name", "Nightly test")
    git("config", "user.email", "nightly@example.test")
    commits = []
    for i in range(10):
        git("commit", "-q", "--allow-empty", "-m", f"Commit {i}")
        commits.append(git("rev-parse", "HEAD"))

    candidates = [{**run, "id": i, "head_sha": commit} for i, commit in reversed(list(enumerate(commits)))]
    candidates[1].update(status="in_progress", conclusion=None)
    candidates[2].update(status="queued", conclusion=None)
    candidates[3].update(conclusion="failure")
    candidates[4].update(conclusion="cancelled")
    # Commit 4 is green but docs-only; commit 3 is missing an iPad shard.
    app_jobs = {4: [], 3: jobs[:-1], 2: jobs, 1: jobs, 0: jobs}

    def select(candidate_pages, job_sets):
        def response(path):
            if "/workflows/ci.yml/runs?" in path:
                assert "branch=main&event=push" in path and "head_sha=" not in path
                return [{"workflow_runs": page} for page in candidate_pages]
            run_id = int(path.split("/runs/")[1].split("/")[0])
            return [{"jobs": job_sets[run_id]}]

        with patch.object(validation, "api", side_effect=response), contextlib.chdir(directory):
            return validation.select(commits[8], "example/app")

    # Traverse beyond five runs and across pages; neither trigger nor future run qualifies.
    assert select([candidates[:5], candidates[5:]], app_jobs) == commits[2]
    assert select([[{**candidates[-1], "id": 20, "head_branch": "feature"}, candidates[-2]]], app_jobs) == commits[1]
    assert select([[{**candidates[-1], "id": 20, "event": "pull_request"}, candidates[-2]]], app_jobs) == commits[1]
    # A failed newer run for the same SHA supersedes an old success.
    assert select([[{**run, "id": 20, "head_sha": commits[2], "conclusion": "failure"},
                    candidates[-3], candidates[-2]]], app_jobs) == commits[1]
    for pages in ([], [candidates[:5]]):
        try:
            select(pages, app_jobs)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted history with no validated candidate")
print("nightly latest-green selection checks passed")
