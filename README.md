# PoC Release Pipeline

Proof-of-concept CI/CD pipeline (GitHub Actions) for a future desktop application.
The "application" is a ZIP of text files; the pipeline around it is the deliverable.
Full requirements and rationale: [PLAN.md](PLAN.md).

## How it works

| Environment | Trigger | Output |
|---|---|---|
| development | every PR / merge to `main` (`ci.yml`) | Actions artifact, 7-day retention |
| staging | manual dispatch of `release.yml` | Actions artifact, 30-day retention |
| production | manual dispatch of `release.yml`, reviewer-approved | Git tag + GitHub Release (ZIP + `.sha256`) |

Every ZIP contains `src/` plus a generated `build.info`
(`environment`, `build_timestamp`, `version`, `commit`, `workflow_run`).
Versions are computed, never typed: `v<YYYY.MM.DD>.<run_number>`
(`-staging` suffix for staging, `-dev+<sha>` for development).

## Day-to-day

**Feature:** branch from `main` → PR → one review + green `build`/`test` checks →
squash-merge. Done; CI publishes the development artifact.

**Staging release:** `gh workflow run release.yml --ref main -f environment=staging`
(or Actions → Release → Run workflow). Builds `main` HEAD, verifies, uploads the artifact.

**Production release:** `gh workflow run release.yml --ref main -f environment=production`.
After a required reviewer approves the pending deployment, the workflow builds, verifies,
creates the tag and the GitHub Release, then re-downloads the published asset and
verifies it again (smoke test). If the latest production tag is not an ancestor of
`main` (an unmerged hotfix), the release fails on purpose.

**Hotfix (production broken, `main` has unreleased features):**

```sh
git switch -c hotfix/fix-thing v2026.06.12.45   # branch from the LAST PRODUCTION TAG
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
