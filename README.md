# PoC Release Pipeline

[![CI](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml?query=branch%3Amain)
[![Release](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml/badge.svg)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/andrmarin/poc_release_pipeline?label=latest%20release)](https://github.com/andrmarin/poc_release_pipeline/releases/latest)

Proof-of-concept CI/CD pipeline (GitHub Actions) for a future desktop application.
The "application" is a ZIP of text files; the pipeline around it is the deliverable.
Full requirements and rationale: [PLAN.md](docs/PLAN.md).

## How it works

| Environment | Trigger | Output |
|---|---|---|
| development | every PR / merge to `main` (`ci.yml`) | Actions artifact, 7-day retention |
| staging | manual dispatch of `release.yml` | Actions artifact, 30-day retention |
| production | manual dispatch of `release.yml`, reviewer-approved | Git tag + GitHub Release (ZIP + `.sha256`) |

Every ZIP contains `src/` plus a generated `build.info`
(`environment`, `build_timestamp`, `version`, `commit`, `workflow_run`).
Versions are computed, never typed: `v<YYYY.MM.DD>.<run_number>` with the run number
zero-padded to 4 digits, e.g. `v2026.06.12.0045` — fixed-width components keep the
Releases page (which sorts by tag-name string) in chronological order
(`-staging` suffix for staging, `-dev+<sha>` for development).

## Day-to-day

**Feature:** branch from `main` → PR → one review + green `build`/`test` checks →
squash-merge. Done; CI publishes the development artifact.

**Staging release:** `gh workflow run release.yml --ref main -f environment=staging`
(or Actions → Release → Run workflow). Builds `main` HEAD, verifies, uploads the artifact.

**Production release:** `gh workflow run release.yml --ref main -f environment=production`.
After a required reviewer approves the pending deployment, the workflow builds, verifies,
uploads everything to a *draft* release (a failed upload creates no tag and the draft is
auto-deleted), then publishes it — which creates the tag — and finally re-downloads the
published asset and verifies it again (smoke test). If the latest production tag is not
an ancestor of `main` (an unmerged hotfix), the release fails on purpose.

**Hotfix (production broken, `main` has unreleased features):**

```sh
git switch -c hotfix/fix-thing v2026.06.12.0045   # branch from the LAST PRODUCTION TAG
# ...fix, push, open PR into main — this is the one review...
gh workflow run release.yml --ref hotfix/fix-thing -f environment=production
# after release: merge the same, already-approved PR into main (forward merge)
```

## Local build & verify

```sh
ENVIRONMENT=development scripts/build.sh   # creates dist/sample-app-...zip + .sha256
scripts/verify.sh dist/*.zip development   # checksum, contents, build.info, behavior
```

Requires bash, `sha256sum`, and either `zip`/`unzip` or Python.

## Simulating failures (negative-path drills)

Repository variables named `SIM_FAIL_<STAGE>` inject controlled failures into the release
pipeline so failure behavior can be tested on demand — no commits or branches needed.
Currently implemented:

| Variable | Effect when `true` |
|---|---|
| `SIM_FAIL_UPLOAD` | the "Upload artifact" step itself reads a deliberately empty path (`SIM_FAIL_UPLOAD-is-armed/*`) and fails; `dist/` and all prior steps are untouched |

```sh
gh variable set SIM_FAIL_UPLOAD --body true    # arm the drill
gh workflow run release.yml --ref main -f environment=staging
gh variable set SIM_FAIL_UPLOAD --body false   # disarm
```

Expected outcome: `build` fails at "Upload artifact"; `test`/`publish`/`smoke` are skipped;
no artifact, tag, or release is produced. Safety: the `guard` job refuses **production**
dispatches while a simulation variable is enabled. Future failure points must follow the
same convention (`SIM_FAIL_BUILD`, `SIM_FAIL_PUBLISH`, ...) including the production guard.

## Bootstrap (one command, no manual UI setup)

```sh
scripts/setup-github.sh --approvers user1,user2
```

Creates the public repo (if missing), pushes `main`, and converges: squash-only merges,
branch ruleset (PR + approval + codeowner review + `build`/`test` checks, no force-push),
tag ruleset (released `v*` tags immutable; on org-owned repos creation is also restricted
to the release workflow), `staging`/`production`
environments (deployments from `main` + `hotfix/*`, production approvers with
prevent-self-review), and read-only default Actions permissions. Idempotent — re-run anytime.

Solo testing: `--allow-self-review` lets you approve your own production releases;
re-run without it once the team is onboarded. Admins can bypass PR requirements
(merge only, never direct push) — remove that bypass from `protect-main` when the
team grows. Update [.github/CODEOWNERS](.github/CODEOWNERS) as reviewers join.
