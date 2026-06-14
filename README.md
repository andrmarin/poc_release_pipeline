# PoC Release Pipeline

[![CI](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/ci.yml?query=branch%3Amain)

**desktop** &nbsp;
[![desktop staging](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/desktop-staging.svg)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml)
[![desktop production](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/desktop-production.svg)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml)
[![desktop latest](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/desktop-latest-release.svg)](https://github.com/andrmarin/poc_release_pipeline/releases)

**browser** &nbsp;
[![browser staging](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/browser-staging.svg)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml)
[![browser production](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/browser-production.svg)](https://github.com/andrmarin/poc_release_pipeline/actions/workflows/release.yml)
[![browser latest](https://raw.githubusercontent.com/andrmarin/poc_release_pipeline/badges/browser-latest-release.svg)](https://github.com/andrmarin/poc_release_pipeline/releases)

<sub>↑ &nbsp;**CI** – development build health on `main` &nbsp;·&nbsp; per-app **staging** / **production** – outcome of each app+environment's most recent completed release &nbsp;·&nbsp; **latest** – that app's newest published version. Self-hosted badges rendered by the release workflow (`badges` tag); allow a few minutes of caching after a release.</sub>

## What is this?

A proof-of-concept CI/CD pipeline built with GitHub Actions, structured as a **monorepo
with two apps** — `apps/desktop` and `apps/browser` — that **release independently**.
Each app is deliberately tiny (a ZIP of text files) because **the pipeline is the
deliverable**, not the apps. For each app the pipeline builds a ZIP, tests it, and
releases it through three environments: **development → staging → production**.

```
apps/
  desktop/   # sample payload for the desktop app
  browser/   # sample payload for the browser app
scripts/     # build.sh, verify.sh, badge.sh, setup-github.sh (all app-aware)
.github/workflows/   # ci.yml, release.yml, tag-police.yml
```

The two apps version and release on their own tracks: a desktop release never touches
browser, and vice versa.

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

CI builds only the app(s) a PR actually changed (changing shared `scripts/` or workflows
builds both). Release runs take an **app** input, so you release `desktop` or `browser`
on demand, independently.

Every ZIP contains that app's files plus a generated `build.info` stating the app,
environment, build timestamp (UTC), version, commit, and a link to the CI run that built
it — so any ZIP can be traced back to its exact source.

Versions are **computed, never typed by hand**: tags are `<app>-v<YYYY.MM.DD>.<run_number>`
with the run number zero-padded to 4 digits, e.g. `desktop-v2026.06.14.0045`. Artifacts are
named the same (`desktop-v2026.06.14.0045-production.zip`). Staging builds get a `-staging`
suffix; development builds get `-dev+<commit>`.

## Everyday development

1. Branch from `main`, make your change, push, and open a pull request.
2. CI runs automatically (the `ci` check must be green — it builds/tests whichever app you
   changed) and one teammate must approve.
3. **Squash-merge** the PR (the only merge method enabled). Done — CI builds the
   development artifact from `main` automatically.

Direct pushes to `main` are blocked for everyone; everything goes through a PR.

## Branch rules: what is enforced, and why

`main` is protected by the `protect-main` ruleset (applied automatically by
[scripts/setup-github.sh](scripts/setup-github.sh); full rationale in
[docs/PLAN.md](docs/PLAN.md) §8). The rules exist to make human error hard, not to
slow you down:

| Rule | What it does | Why |
|---|---|---|
| Pull request required | direct pushes to `main` are rejected, for everyone | every change gets CI and a second pair of eyes before it can ship |
| 1 approving review | a PR needs a teammate's approval (you cannot approve your own) | review is evidence, not ceremony — someone else looked |
| Code-owner review | changes under `.github/` and `scripts/` need approval from [CODEOWNERS](.github/CODEOWNERS) | pipeline changes have the highest blast radius in the repo |
| Required check: `ci` | a PR cannot merge while CI is red — one gate job that always reports, even when only one app (or no app) changed | `main` stays releasable at every commit without path-filtered checks deadlocking |
| Squash-merge only + linear history | each PR lands as exactly one commit, no merge commits | rolling back a whole feature is a single `git revert`; history reads like a changelog |
| No force-pushes | history on `main` is append-only | released tags and `build.info` commit references can never point at rewritten history |
| No branch deletion | `main` cannot be deleted | even by accident, even by admins |
| Admin bypass (PR-only) | an admin may merge a PR without the requirements above, but still **cannot** push directly | solo-phase escape hatch — remove it from the ruleset once the team grows |

Two related protections outside the branch ruleset:

- **`protect-release-tags` ruleset + tag police:** well-formed release tags
  (`<app>-vYYYY.MM.DD.NNNN`) are immutable (no update, no deletion) — a published version
  number must point at the same commit forever. Malformed look-alikes (e.g. `v2026.05.1111`
  or `desktop-v1`) are **auto-deleted within seconds** by the `tag-police` workflow
  (ruleset-level name regexes need GitHub Enterprise). On org-owned repos tag *creation* is
  also restricted to the release workflow.
- **Auto-delete merged branches:** the remote feature branch is removed on merge, so
  stale branches don't accumulate (note: this is why a hotfix must be *released before*
  its PR is merged).

## Terminal cheat sheet: branch → PR → merge → release

The whole journey from a fresh branch to a production release, console-only:

```sh
# 0. Start from an up-to-date main
git switch main
git pull origin main

# 1. Create a feature branch
git switch -c feat/my-change

# 2. ...edit files..., then commit
git add .
git commit -m "Describe the change"

# 3. Push the branch to GitHub
git push -u origin feat/my-change

# 4. Open a pull request and wait for CI
gh pr create --fill        # title/body from your commit message
gh pr checks --watch       # waits until the 'ci' gate (changed-app build/test) finishes

# 5. Merge after a teammate approves (squash is the only allowed method;
#    the remote branch is deleted automatically)
gh pr merge --squash --delete-branch
#    solo phase only: admins may append --admin to bypass the review requirement

# 6. Back to an up-to-date main
git switch main
git pull origin main

# 7. (Optional) Release the changed app to staging (no approval) and watch it.
#    Pick the app: desktop or browser.
gh workflow run release.yml --ref main -f app=desktop -f environment=staging
sleep 10 && gh run watch "$(gh run list --workflow=release.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')"

# 8. Release that app to production — the run PAUSES for reviewer approval:
#    an approver opens the run page → "Review deployments" → Approve and deploy
#    (click path with screenshots: docs/HOW_TO_RELEASE.md)
gh workflow run release.yml --ref main -f app=desktop -f environment=production
sleep 10 && gh run watch "$(gh run list --workflow=release.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')"

# 9. See the published release (tag desktop-v..., ZIP + .sha256)
gh release view "desktop-$(date -u +%Y.%m.%d)"* --web 2>/dev/null || gh release list
```

## Releasing

Short version — full click-by-click guide with screenshots in
[docs/HOW_TO_RELEASE.md](docs/HOW_TO_RELEASE.md):

```sh
gh workflow run release.yml --ref main -f app=desktop -f environment=staging     # staging
gh workflow run release.yml --ref main -f app=browser -f environment=production  # production (needs approval)
```

Each release targets one app (`desktop` or `browser`) and one environment. Production
releases pause until a reviewer approves, then publish fully automatically (draft release →
asset verification → publish → post-publish verify). Hotfixes branch from that app's **last
production tag** (e.g. `desktop-v…`), not from `main` — see the guide.

## Building and testing locally

You can run the same build and verification the pipeline runs, on your own machine:

```sh
APP=desktop ENVIRONMENT=development scripts/build.sh   # creates dist/desktop-...zip + .sha256
scripts/verify.sh dist/*.zip development desktop       # checksum, contents, build.info, behavior
```

`APP` defaults to `desktop`; set `APP=browser` to build the other app. Needs bash,
`sha256sum`, and either `zip`/`unzip` or Python.

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
branch ruleset (PR + approval + codeowner review + the `ci` check, no force-push), tag
ruleset (released `<app>-v*` tags immutable; on org-owned repos creation is also restricted
to the release workflow), **four per-app environments** (`desktop-staging`,
`desktop-production`, `browser-staging`, `browser-production` — deployments from `main` +
`hotfix/*`, production envs gated by approvers with prevent-self-review), and read-only
default Actions permissions. Idempotent — re-run anytime.

Solo testing: `--allow-self-review` lets you approve your own production releases, and
`--no-approval` removes the production approval gate entirely (releases publish without
any pause — PoC/sandbox use only); re-run without these flags once the team is onboarded. Admins can bypass PR requirements
(merge only, never direct push) — remove that bypass from `protect-main` when the
team grows. Update [.github/CODEOWNERS](.github/CODEOWNERS) as reviewers join.

## More documentation

- [docs/HOW_TO_RELEASE.md](docs/HOW_TO_RELEASE.md) — releasing, step by step, with screenshots
- [docs/PLAN.md](docs/PLAN.md) — requirements, design decisions, and their rationale
- [docs/ISSUES.md](docs/ISSUES.md) — log of issues faced and how each was solved
