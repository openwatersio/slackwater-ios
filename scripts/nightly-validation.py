#!/usr/bin/env python3
"""Select and validate an immutable nightly candidate with full main CI."""
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
    validate_jobs(run, repository)
    print(f"Full main CI validated {sha} (run {run['id']}, attempt {run['run_attempt']}).")


def select(anchor, repository):
    ancestors = set(subprocess.check_output(["git", "rev-list", anchor], text=True).splitlines())
    pages = api(f"repos/{repository}/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=100")
    runs = sorted((run for page in pages for run in page["workflow_runs"]), key=lambda run: run["id"], reverse=True)
    seen = set()
    for run in runs:
        sha = run["head_sha"]
        if run["head_branch"] != "main" or run["event"] != "push" or sha not in ancestors or sha in seen:
            continue
        # An older success must not override a newer failed or pending run for the same SHA.
        seen.add(sha)
        if run["status"] != "completed" or run["conclusion"] != "success":
            continue
        try:
            validate_jobs(run, repository)
        except ValueError as error:
            print(f"Skipping CI run {run['id']} ({sha}): {error}", file=sys.stderr)
            continue
        print(f"Selected {sha} from full main CI run {run['id']} (attempt {run['run_attempt']}).", file=sys.stderr)
        return sha
    raise ValueError("no completed successful main CI run with full app validation in the trigger history")


def validate_jobs(run, repository):
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


BLOCKED = 3


if __name__ == "__main__":
    selecting = sys.argv[1] == "--select"
    sha = sys.argv[2] if selecting else sys.argv[1]
    try:
        if selecting:
            print(select(sha, os.environ["GITHUB_REPOSITORY"]))
        else:
            validate(sha, os.environ["GITHUB_REPOSITORY"])
    except ValueError as error:
        # A refusal releases nothing and is no release defect; main's CI run shows why.
        print(f"::warning::Nightly blocked for {sha}: {error}", file=sys.stderr if selecting else sys.stdout)
        sys.exit(BLOCKED)
    except (KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Nightly could not validate {sha}: {error}")
