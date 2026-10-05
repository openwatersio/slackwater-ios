#!/usr/bin/env python3
"""Release CI runners occupied by a closed pull request."""
import json
import os
import subprocess


def api(path, method="GET"):
    command = ["gh", "api", "--method", method, path]
    if "/runs?" in path:
        command += ["--paginate", "--slurp"]
    output = subprocess.check_output(command, text=True)
    return json.loads(output) if output.strip() else None


def eligible(run, pr, workflow):
    cutoff = pr["closed_at"]
    return (
        run.get("workflow_id") == workflow
        and run.get("path") == ".github/workflows/ci.yml"
        and run.get("event") == "pull_request"
        # GitHub removes the pull_requests association from merged runs.
        and run.get("display_title") == f"CI · PR #{pr['number']}"
        and (run.get("head_repository") or {}).get("id") == pr["head"]["repo"]["id"]
        and run.get("head_branch") == pr["head"]["ref"]
        and run.get("head_sha") == pr["head"]["sha"]
        and run.get("status") != "completed"
        and bool(run.get("created_at")) and run["created_at"] < cutoff
        and bool(run.get("run_started_at")) and run["run_started_at"] < cutoff
    )


def cancel_closed_pr(event):
    pr = event["pull_request"]
    if event["action"] != "closed" or not pr.get("closed_at") or not pr["head"].get("repo"):
        return
    root = f"repos/{event['repository']['full_name']}"
    workflow = api(f"{root}/actions/workflows/ci.yml")["id"]
    pages = api(f"{root}/actions/workflows/ci.yml/runs?event=pull_request&head_sha={pr['head']['sha']}&per_page=100")
    for page in pages:
        for run in page["workflow_runs"]:
            if not eligible(run, pr, workflow):
                continue
            fresh = api(f"{root}/actions/runs/{run['id']}")
            if not eligible(fresh, pr, workflow) or fresh["run_attempt"] != run["run_attempt"]:
                continue
            current = api(f"{root}/pulls/{pr['number']}")
            if current["state"] != "closed" or current["closed_at"] != pr["closed_at"]:
                return
            try:
                api(f"{root}/actions/runs/{run['id']}/cancel", "POST")
            except subprocess.CalledProcessError:
                # Completion between the status read and cancel needs no cleanup.
                if api(f"{root}/actions/runs/{run['id']}")["status"] == "completed":
                    continue
                raise
            print(f"Cancelled CI run {run['id']} for closed PR #{pr['number']}.")


if __name__ == "__main__":
    with open(os.environ["GITHUB_EVENT_PATH"]) as source:
        cancel_closed_pr(json.load(source))
