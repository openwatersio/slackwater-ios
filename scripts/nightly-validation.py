#!/usr/bin/env python3
"""Require full main CI validation of the immutable nightly candidate."""
import json
import os
import subprocess
import sys


def api(path):
    return json.loads(subprocess.check_output(
        ["gh", "api", "--paginate", "--slurp", path], text=True))


def validate(sha, repository):
    pages = api(f"repos/{repository}/actions/workflows/ci.yml/runs?head_sha={sha}&branch=main&event=push&per_page=100")
    runs = [run for page in pages for run in page["workflow_runs"]]
    if not runs:
        raise ValueError("no main CI run")
    run = runs[0]
    if (run["head_sha"] != sha or run["head_branch"] != "main" or run["event"] != "push"
            or run["status"] != "completed" or run["conclusion"] != "success"):
        raise ValueError("latest main CI run is not successful and complete for this commit")
    # Retain earlier successful jobs when only failed jobs were rerun.
    pages = api(f"repos/{repository}/actions/runs/{run['id']}/jobs?filter=all&per_page=100")
    jobs = [job for page in pages for job in page["jobs"]]
    required = {"Build for testing"} | {
        f"App tests · {shard}{suffix}"
        for shard in ("offline", "list", "transition", "detail", "rest")
        for suffix in ("", " · iPad")
    }
    latest = {}
    for job in jobs:
        previous = latest.get(job["name"])
        if previous is None or (job["run_attempt"], job["id"]) > (previous["run_attempt"], previous["id"]):
            latest[job["name"]] = job
    successful = {job["name"] for job in latest.values()
                  if job["status"] == "completed" and job["conclusion"] == "success"}
    missing = required - successful
    if missing:
        raise ValueError("missing successful app validation: " + ", ".join(sorted(missing)))
    print(f"Full main CI validated {sha} (run {run['id']}, attempt {run['run_attempt']}).")


BLOCKED = 3


if __name__ == "__main__":
    try:
        validate(sys.argv[1], os.environ["GITHUB_REPOSITORY"])
    except ValueError as error:
        # A refusal releases nothing and is no release defect; main's CI run shows why.
        print(f"::warning::Nightly blocked for {sys.argv[1]}: {error}")
        sys.exit(BLOCKED)
    except (KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Nightly could not validate {sys.argv[1]}: {error}")
