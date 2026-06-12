# PoC Release Pipeline

[![CI](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml?query=branch%3Amain)
[![Staging](https://img.shields.io/github/deployments/andrmarin/poc_release_pipeline/staging?label=staging)](https://github.com/andrmarin/poc_release_pipeline/deployments)
[![Production](https://img.shields.io/github/deployments/andrmarin/poc_release_pipeline/production?label=production)](https://github.com/andrmarin/poc_release_pipeline/deployments)
[![Latest release](https://img.shields.io/github/v/release/andrmarin/poc_release_pipeline?label=latest%20release)](https://github.com/andrmarin/poc_release_pipeline/releases/latest)

<sub>↑ &nbsp;**CI** – development build health on `main` &nbsp;·&nbsp; **staging** / **production** – each environment's most recent release (*pending* = awaiting reviewer approval) &nbsp;·&nbsp; **latest release** – newest published version</sub>

## What is this?

A proof-of-concept CI/CD pipeline built with GitHub Actions, used as a dry run for a
future desktop application. The "application" itself is deliberately tiny — a ZIP of
text files — because **the pipeline is the deliverable**, not the app. The pipeline
builds the ZIP, tests it, and releases it through three environments:
**development → staging → production**.

Good starting points:

- New to the project? Read this page top to bottom.
- Want to ship a release? Follow [docs/HOW_TO_RELEASE.md](docs/HOW_TO_RELEASE.md) — click-by-click with screenshots.
- Want the full design and reasoning? See [docs/PLAN.md](docs/PLAN.md).

## What you need installed

| Tool | Why | Check it works |
|---|---|---|
| [Git](https://git-scm.com) | clone the repo, create branches | `git --version` |
| Bash | run the build/verify scripts (on Windows it ships with Git as "Git Bash") | `bash --version` |
| [GitHub CLI (`gh`)](https://cli.github.com) | trigger releases and manage GitHub from the terminal (see below) | `gh --version` |

### What is `gh` and how to install it

**GitHub CLI (`gh`)** is GitHub's official command-line tool. Anything you can click on
github.com — starting a workflow, downloading a release, opening a pull request — has a
`gh` command. This project uses it to trigger releases from the terminal and to run the
one-shot repository bootstrap script. You can always use the GitHub **website** instead;
`gh` is the faster path once you're comfortable.

Install it:

- **Windows:** `winget install --id GitHub.cli`
- **macOS:** `brew install gh`
- **Linux (Debian/Ubuntu):** `sudo apt install gh`
- Or download an installer from <https://cli.github.com>.

Then sign in **once** and verify:

```sh
gh auth login    # pick GitHub.com and follow the prompts (browser login is easiest)
gh auth status   # should say: Logged in to github.com
```

## How the pipeline works

| Environment | When it runs | What you get |
|---|---|---|
| development | automatically, on every PR and every merge to `main` (`ci.yml`) | build artifact in the Actions run, kept 7 days |
| staging | you trigger it manually (`release.yml`) | build artifact in the Actions run, kept 30 days |
| production | you trigger it manually + a reviewer approves (`release.yml`) | Git tag + [GitHub Release](https://github.com/andrmarin/poc_release_pipeline/releases) with the ZIP and its `.sha256` checksum |

Every ZIP contains the files from `src/` plus a generated `build.info` stating the
environment, build timestamp (UTC), version, commit, and a link to the CI run that built
it — so any ZIP can be traced back to its exact source.

Versions are **computed, never typed by hand**: `v<YYYY.MM.DD>.<run_number>` with the
run number zero-padded to 4 digits, e.g. `v2026.06.12.0045`. Staging builds get a
`-staging` suffix; development builds get `-dev+<commit>`.

## Everyday development

1. Branch from `main`, make your change, push, and open a pull request.
2. CI runs automatically (`build` + `test` must be green) and one teammate must approve.
3. **Squash-merge** the PR (the only merge method enabled). Done — CI builds the
   development artifact from `main` automatically.

Direct pushes to `main` are blocked for everyone; everything goes through a PR.

## Releasing

Short version — full click-by-click guide with screenshots in
[docs/HOW_TO_RELEASE.md](docs/HOW_TO_RELEASE.md):

```sh
gh workflow run release.yml --ref main -f environment=staging      # staging
gh workflow run release.yml --ref main -f environment=production   # production (needs approval)
```

Production releases pause until a reviewer approves, then publish fully automatically
(draft release → asset verification → publish → post-publish verify). Hotfixes branch
from the **last production tag**, not from `main` — see the guide.

## Building and testing locally

You can run the same build and verification the pipeline runs, on your own machine:

```sh
ENVIRONMENT=development scripts/build.sh   # creates dist/sample-app-...zip + .sha256
scripts/verify.sh dist/*.zip development   # checks checksum, contents, build.info, behavior
```

Needs bash, `sha256sum`, and either `zip`/`unzip` or Python.

## Simulating failures (negative-path drills)

Repository variables named `SIM_FAIL_<STAGE>` inject controlled failures into the release
pipeline so failure behavior can be tested on demand — no commits or branches needed.
Currently implemented:

| Variable | Effect when `true` |
|---|---|
| `SIM_FAIL_UPLOAD` | the "Upload artifact" step itself reads a deliberately empty sentinel path and fails; a follow-up step annotates the run with the disarm command and a link here |

```sh
gh variable set SIM_FAIL_UPLOAD --body true    # arm the drill
gh workflow run release.yml --ref main -f environment=staging
gh variable set SIM_FAIL_UPLOAD --body false   # disarm
```

Expected outcome: in the `build` job every step up to and including "Build" succeeds
(`dist/` is produced as normal) and only the "Upload artifact" step fails — the failure
originates in the targeted step itself, not in any prior step. `test`/`publish`/
`post-publish verify` are skipped; no artifact, tag, or release is produced. Safety: the
`guard` job refuses **production** dispatches while a simulation variable is enabled.
Future failure points must follow the same convention (`SIM_FAIL_BUILD`,
`SIM_FAIL_PUBLISH`, ...): fail inside the targeted step, include the production guard.

## Bootstrap (one command, no manual UI setup)

Only needed when setting this repository up from scratch on a new GitHub account/org:

```sh
scripts/setup-github.sh --approvers user1,user2
```

Creates the public repo (if missing), pushes `main`, and converges: squash-only merges,
branch ruleset (PR + approval + codeowner review + `build`/`test` checks, no force-push),
tag ruleset (released `v*` tags immutable; on org-owned repos creation is also restricted
to the release workflow), `staging`/`production` environments (deployments from `main` +
`hotfix/*`, production approvers with prevent-self-review), and read-only default Actions
permissions. Idempotent — re-run anytime.

Solo testing: `--allow-self-review` lets you approve your own production releases;
re-run without it once the team is onboarded. Admins can bypass PR requirements
(merge only, never direct push) — remove that bypass from `protect-main` when the
team grows. Update [.github/CODEOWNERS](.github/CODEOWNERS) as reviewers join.

## More documentation

- [docs/HOW_TO_RELEASE.md](docs/HOW_TO_RELEASE.md) — releasing, step by step, with screenshots
- [docs/PLAN.md](docs/PLAN.md) — requirements, design decisions, and their rationale
