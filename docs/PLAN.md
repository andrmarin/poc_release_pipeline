# PLAN: CI/CD Proof-of-Concept Release Pipeline (GitHub Actions)

## 1. Goal

Build a proof-of-concept CI/CD pipeline with GitHub Actions that can **build, test, and release** a
sample project, as a dry run for a future desktop application. The pipeline must support three
environments (**development**, **staging**, **production**), publish production releases to
**GitHub Releases**, and use a branching/release strategy that minimizes the risk of human error.

The sample project is intentionally trivial (a ZIP of text files) so that builds are fast and the
artifact content is easy to verify. The *pipeline*, not the application, is the deliverable.

## 2. Decisions (agreed with the user on 2026-06-12)

| Topic | Decision |
|---|---|
| Branching strategy | Trunk-based: single protected `main` branch, short-lived feature branches via PR |
| Promotion model | Tags mark production releases, but tags are **created by the workflow**, never typed by hand |
| Hotfix model | Branch from the **last production tag** (`hotfix/*`), one PR review, release from the hotfix branch, forward-merge into `main` — no back merges |
| Publishing | GitHub Releases **only for production**; development and staging builds are GitHub Actions artifacts |
| Versioning | Build-number versioning: `v<YYYY.MM.DD>.<run_number>`, computed automatically |
| Runner OS | `ubuntu-latest` (structure transfers to Windows later by swapping `runs-on`) |
| Repo visibility | **Public** (full rulesets available on the free plan) |
| GitHub setup | Fully automated by `scripts/setup-github.sh` (gh CLI) — zero manual UI actions |

Rationale for the promotion model: the user chose both "trunk-based + tags" and "build-number
versioning". Manual tag pushing would reintroduce typo/duplicate-version risk, so the production
release workflow computes the version, creates the tag, and publishes the release in one gated,
auditable action. Humans approve releases; they never name them.

## 3. Assumptions & prerequisites (step zero)

The local repository currently has **no commits, no remote, and is on `master`**. The repository
will be **public**, so full rulesets are available on the free plan. All GitHub-side setup —
repo creation, push, rulesets, environments, Actions settings — is performed by
`scripts/setup-github.sh` (§8) with **no manual UI actions**. The only prerequisites are:

1. An initial commit exists (the implementation commit itself satisfies this).
2. The `gh` CLI is installed and authenticated (`gh auth login`) with repo-administration scope;
   the script verifies this and fails fast otherwise.

## 4. Sample project

Keep the user's suggestion (ZIP of text files) — it is a good fit: fast to build, fast to
upload/download, trivially inspectable. One small improvement: include a tiny executable script in
the ZIP so the "test" stage can assert *behavior*, not just file presence.

### Repository layout

```
.
├── .github/
│   ├── CODEOWNERS           # routes review of .github/ and scripts/ changes
│   ├── dependabot.yml       # weekly bumps of the SHA-pinned actions
│   └── workflows/
│       ├── ci.yml           # PRs + pushes to main → development build + test
│       └── release.yml      # manual, gated → staging artifact or production release
├── docs/
│   ├── HOW_TO_RELEASE.md    # click-by-click release guide (screenshots in docs/img/)
│   └── PLAN.md              # this document
├── scripts/
│   ├── build.sh             # produces dist/<artifact>.zip (+ .sha256)
│   ├── verify.sh            # unzips and validates an artifact
│   └── setup-github.sh      # one-shot, idempotent GitHub bootstrap via gh (spec in §8)
├── src/                     # sample app payload; extra files ride along into the ZIP
│
└── README.md                # entry point: prerequisites, pipeline overview, doc map
```

### Artifact specification

- Name: `sample-app-<version>-<environment>.zip` (e.g. `sample-app-v2026.06.12.0045-production.zip`).
  The environment suffix is omitted when the version already ends with an environment marker
  (`-staging`, `-dev+<sha>`), avoiding names like `...-staging-staging.zip`.
- The Actions **artifact container** uses the ZIP's base name (set from the built file, single
  source of truth) — names are unique per run and sort chronologically, so downloads never
  collide in a Downloads folder.
- Contents: everything under `src/` **plus a generated `build.info`** at the ZIP root.
- A `<artifact>.zip.sha256` checksum file is produced next to every ZIP and published with it.

### `build.info` format (key=value, one per line)

```
environment=production            # required by the task
build_timestamp=2026-06-12T14:30:00Z   # required by the task; UTC, ISO 8601
version=v2026.06.12.45
commit=<full git SHA>
workflow_run=<URL of the Actions run that built it>
```

`environment` and `build_timestamp` are the user's hard requirements; the other three fields are
added for traceability (any downloaded ZIP can be traced back to its exact commit and CI run).

### `scripts/build.sh` requirements

- Inputs via environment variables: `ENVIRONMENT` (one of `development|staging|production`),
  `VERSION`, plus git SHA and run URL when available (sane local defaults so the script also runs
  on a developer machine).
- Validates `ENVIRONMENT` against the allowed list and fails loudly otherwise.
- Generates `build.info`, stages `src/` + `build.info`, produces the ZIP and `.sha256` into `dist/`.

### `scripts/verify.sh` requirements (the "test" stage)

Given a ZIP path and an expected environment, it must:

1. Verify the `.sha256` checksum matches the ZIP.
2. Unzip to a temp dir and assert all expected files are present.
3. Assert `build.info` exists and that `environment`, `build_timestamp`, `version`, `commit` are
   non-empty; assert `environment` equals the expected value; assert the timestamp parses as
   ISO 8601 UTC.
4. Execute `hello.sh` from the extracted ZIP and assert its output contains the environment and
   version (behavioral check).
5. Exit non-zero with a clear message on any failure.

## 5. Versioning scheme

- **Production:** `v<YYYY.MM.DD>.<run_number>` where the date is the UTC date and `run_number` is
  the `release.yml` workflow run number **zero-padded to 4 digits** (e.g. `v2026.06.12.0045`).
  Monotonic and collision-free without any stored state. Padding is required because GitHub's
  Releases page orders entries by string comparison of tag names — with fixed-width components,
  string order equals chronological order, keeping the newest release on top. (Verified
  empirically on 2026-06-12: unpadded `v2026.06.12.13` sorted below `v2026.06.12.9`.)
- **Staging:** same scheme with a `-staging` suffix; **no tag is created**.
- **Development:** `v<YYYY.MM.DD>.<ci_run_number>-dev+<short SHA>` (run number padded the same
  way); **no tag is created**.
- **Hotfix releases** use the regular production scheme — the build number absorbs them with no
  special casing. Note: version order reflects release time, not code lineage (a hotfix version
  can be "newer" than a staging build that contains more features); `build.info`'s commit field
  is the source of truth for lineage.
- A re-run of a release workflow attempt keeps the same run number; if the tag already exists the
  workflow must **fail with a clear error** rather than overwrite anything (intentional idempotency
  guard — re-releasing the same version requires a fresh run).
- **Monotonic version guard** (build job, both environments): the computed version must sort
  strictly above the newest existing `v*` tag, otherwise the run fails. This closes the same-day
  stale re-run loophole: run numbers are frozen per run, so re-running an old failed run after
  newer releases shipped would otherwise produce a *lower* version — for production it would even
  be marked Latest. Caveat: re-runs execute their original workflow snapshot, so the guard only
  protects runs created after it was introduced (2026-06-12).

## 6. Branching & release strategy

```
feature/* ──PR (review + green CI required)──> main
                                                │
   every merge to main          ──> ci.yml      → development ZIP (Actions artifact, short retention)
   manual dispatch (staging)    ──> release.yml → staging ZIP     (Actions artifact, 30-day retention)
   manual dispatch (production) ──> release.yml → tag v<date>.<run> + GitHub Release with ZIP + sha256
        └─ gated by the `production` environment: required reviewers, no self-review

hotfix lane — production needs a fix while main carries unreleased features:

v<last prod tag> ──branch──> hotfix/<issue> ──PR into main (the one review, CI runs as usual)
                                  │
                                  ├─ optional: dispatch release.yml (staging) to rehearse the fix
                                  ├─ dispatch release.yml (production) → tag + GitHub Release
                                  └─ merge the same, already-approved PR into main (forward merge)
```

- All changes reach `main` exclusively through pull requests (squash-merge only); direct pushes
  are blocked.
- Promotion is by **re-building the dispatched ref** (`main` for regular releases, `hotfix/*` for
  hotfixes) with a different `ENVIRONMENT` stamp. (Rebuild-per-environment is acceptable here
  because `build.info` must differ per environment; the plan notes "build once, re-stamp" as a
  future option for the real desktop app.)
- **Hotfixes branch from the last production tag, never from `main`** — so the released ZIP
  contains exactly production's code plus the fix, even while `main`/staging carry unreleased
  features. The PR into `main` is the single review; the release is dispatched from the hotfix
  branch; merging that same PR forward puts the fix into the next regular release. The trunk is
  the only long-lived branch, so no back merges exist in this model.
- **Unmerged-hotfix guard:** a regular production release from `main` fails if the latest
  production tag is not an ancestor of the commit being released — that means a hotfix shipped
  but was never merged forward, and releasing would silently regress it. Because this repo is
  squash-merge only (commits are rewritten on merge), the guard also accepts a tag whose commit
  belongs to a PR that was merged into `main`.
- **Hotfix pipeline snapshot:** a release dispatched from a `hotfix/*` branch runs the workflow
  *as committed on that branch* — i.e. the pipeline as of the tag it was cut from. Guards added
  to `main` afterwards do not apply to such releases.

## 7. Workflows

### 7.1 `ci.yml` — continuous integration (development environment)

- **Triggers:** `pull_request` targeting `main`, and `push` to `main`.
- **Permissions:** `contents: read` (top level).
- **Concurrency:** group per ref, `cancel-in-progress: true` (superseded runs are cancelled).
- **Jobs:**
  1. `build` — checkout, compute the dev version, run `scripts/build.sh` with
     `ENVIRONMENT=development`, upload `dist/` as an Actions artifact (retention ~7 days).
  2. `test` — `needs: build`; **downloads the built artifact** (does not rebuild) and runs
     `scripts/verify.sh` against it expecting `development`. Testing the actual artifact, not a
     rebuild, is deliberate.
- The combination of `build` + `test` is the required status check for merging PRs.

### 7.2 `release.yml` — gated promotion (staging / production)

- **Trigger:** `workflow_dispatch` with one input: `environment` (choice: `staging`,
  `production`). No free-text inputs — nothing for a human to mistype.
- **Guard job:** asserts the workflow was dispatched from `main` or a `hotfix/*` branch
  (`github.ref` equals `refs/heads/main` or matches `refs/heads/hotfix/*`); fails immediately
  otherwise.
- **Permissions:** top-level `contents: read`; only the publish step's job gets
  `contents: write` (needed to create the tag and release).
- **Concurrency:** group `release-<environment>`, no cancel-in-progress (a running production
  release is never killed mid-publish; a second dispatch queues).
- **Build/test jobs:** set `environment: ${{ inputs.environment }}` on the job so GitHub's
  environment protection rules apply automatically (this is the human-error gate: production
  requires reviewer approval, staging does not). Compute the version per §5, build, then verify
  with `scripts/verify.sh`.
- **Staging path:** upload the verified ZIP + checksum as an Actions artifact with 30-day
  retention. Done — no tag, no release.
- **Failure simulation:** repository variables following the `SIM_FAIL_<STAGE>` naming convention
  inject controlled failures for negative-path drills — toggled with `gh variable set
  SIM_FAIL_<STAGE> --body true|false`, no commits required; unset evaluates as off. The failure
  must occur **inside the targeted step**, never by tampering with earlier steps' output (first:
  `SIM_FAIL_UPLOAD` switches the upload step's `path` to a deliberately empty location so the
  upload step itself fails; `dist/` is untouched). The guard job refuses production dispatches
  while any simulation variable is enabled.
- **Production path:**
  1. **Unmerged-hotfix guard** (regular releases only, i.e. dispatched from `main`): fail if the
     most recent production tag is not an ancestor of the commit being released — a prior hotfix
     shipped but was never merged forward and would regress. Squash-aware: a tag whose commit
     belongs to a PR merged into `main` passes. Skipped for `hotfix/*` dispatches.
  2. **Draft-first publish:** create a *draft* GitHub Release for `v<YYYY.MM.DD>.<run_number>`
     (auto-generated notes) and upload the ZIP + `.sha256` to it. Drafts create no tag and are
     not public, so a failed asset upload leaves nothing half-released; a failure handler deletes
     the leftover draft automatically. The draft's **release id is captured from the create
     response** and passed between steps — never looked up by name afterwards (the list endpoint
     failed to return a just-created draft in practice: "Draft release not found", 2026-06-12).
  3. Verify both assets report state `uploaded`, then publish the draft and mark it latest — this
     final, smallest step is what creates the tag on the built commit via the workflow's
     `GITHUB_TOKEN`.
  4. **Post-publish verify job:** download the asset *from the published GitHub Release* (not from
     the workspace) and run `scripts/verify.sh` on it — proves the artifact users will download is
     valid, closing the loop end to end.
  5. The post-publish verify job also writes the **actual execution time** (sum of job run times,
     vs. wall clock and approval-wait split) to the run summary — GitHub's run-duration display
     is wall clock including approval wait and cannot be configured to exclude it.

## 8. Repository setup & protections (automated by `scripts/setup-github.sh`)

No manual GitHub UI actions. One bootstrap script applies everything in this section via the `gh`
CLI — `gh repo create`/`gh repo edit` for the basics, `gh api` for rulesets, environments, and
Actions settings.

### Script requirements

- **Inputs:** repo owner/name (defaults: authenticated user + current directory name), the
  production approver GitHub usernames (`--approvers user1,user2`), `--allow-self-review`
  (keep the gate but let the dispatcher approve their own release), and `--no-approval`
  (disable the production approval gate entirely — no required reviewers; re-running without
  the flag restores the gate).
- **Idempotent:** safe to re-run at any time — finds existing rulesets/environments by name and
  updates them, creates what is missing. A second run against a fully configured repo changes
  nothing and says so.
- **Preflight:** verify `gh` is installed and authenticated with sufficient scope; ensure the
  local branch is `main` (rename `master` automatically if needed); fail fast with a clear
  message on any unmet precondition.
- **Steps performed, in order:**
  1. Create the **public** repository if it does not exist, add it as `origin`, push `main`.
  2. Set `main` as the default branch; enable delete-branch-on-merge.
  3. Configure merge methods per item 3 below.
  4. Create/update the branch ruleset (item 2) and the tag ruleset (item 4) via the rulesets API.
  5. Create/update the `staging` and `production` environments (item 5), resolving approver
     usernames to user IDs; enable prevent-self-review on `production`. If the only approver is
     the authenticated user, warn that self-dispatched production releases will block. With
     `--no-approval`, configure `production` with no required reviewers instead and warn loudly
     that releases will publish without human approval.
  6. Apply the Actions defaults (item 7) via the Actions permissions API.
  7. Print a summary of everything created, updated, or already compliant.

### Target configuration the script must apply

1. **Default branch** `main`.
2. **Branch ruleset on `main`:** require PR before merging, ≥1 approval, required status checks
   (`build`, `test`) passing, block force pushes and deletion, require linear history. Do **not**
   require branches to be up to date before merging: with five developers on one trunk it forces
   constant rebase-and-rerun churn, and post-merge CI on `main` catches the rare semantic
   conflict. If the repo's plan supports merge queue, enable it and re-enable strict up-to-date.
3. **Merge methods:** allow **squash-merge only** (disable merge commits and rebase merges).
   Linear history makes rolling back a whole feature a single `git revert`.
4. **Tag ruleset on `v*`:** preferred configuration blocks creation, update, and deletion for
   everyone, with a bypass for the GitHub Actions app so only the release workflow can create
   tags. **Verified during implementation:** that bypass actor is only accepted on org-owned
   repos; on a personal repo the script automatically falls back to blocking update/deletion only
   (released tags are immutable, creation stays open). The publish job independently refuses to
   reuse an existing tag, so a stray manual tag fails the release loudly rather than being
   overwritten. Re-running the script after moving the repo to an organization converges to the
   full lockdown.
5. **Environments:** create `staging` and `production`. `production` gets **required reviewers**
   (name at least two eligible approvers to cover absences, and enable **"prevent self-review"**
   so the person dispatching a release can never approve it themselves) and deployment-branch
   restriction to `main` + `hotfix/*`. `staging` gets the same branch restriction only.
6. **CODEOWNERS:** route `.github/workflows/` and `scripts/` to designated reviewer(s) — pipeline
   changes are the highest-blast-radius changes in the repo.
7. **Actions settings:** default workflow permissions = read-only; "Allow GitHub Actions to create
   and approve pull requests" stays off.
8. **Action pinning:** all third-party actions pinned to a full commit SHA; `dependabot.yml` keeps
   the pins updated (`package-ecosystem: github-actions`, weekly).

## 9. Acceptance criteria

The implementation is complete when all of the following are demonstrated
(✅ = verified live on 2026-06-12):

- [ ] A PR with a failing `verify.sh` check cannot be merged; a green PR can. *(Green half
      verified many times; the failing-PR drill has not been run yet.)*
- [x] Merging to `main` produces a development artifact whose `build.info` says
      `environment=development` and contains a valid UTC timestamp, version, commit SHA, and run URL.
- [x] Dispatching `release.yml` with `staging` produces a 30-day-retention artifact stamped
      `environment=staging`, with **no** tag and **no** GitHub Release created.
- [x] Dispatching `release.yml` with `production` pauses for reviewer approval, then creates tag
      `v<date>.<run>`, and a GitHub Release with the ZIP and `.sha256` attached.
- [x] The post-publish verify job downloads the released asset and `verify.sh` passes on it.
- [ ] Hotfix drill: a `hotfix/*` branch cut from the latest production tag, with one reviewed PR
      into `main`, releases to production **without** any unreleased `main` features in the ZIP;
      the same PR then merges forward into `main`.
- [ ] While a shipped hotfix PR is still unmerged, a regular production release from `main` fails
      on the unmerged-hotfix guard; after merging (squash), it succeeds via the merged-PR check.
- [x] The dispatcher of a production release cannot approve it themselves (prevent self-review).
      *(Verified before prevent-self-review was temporarily disabled for solo testing — re-enable
      by re-running `setup-github.sh` without `--allow-self-review` once the team is onboarded.)*
- [ ] Manually updating or deleting a released `v*` tag is rejected by the tag ruleset. (On
      org-owned repos manual *creation* is also rejected; on personal repos creation stays open —
      see §8 item 4 — and the publish job's existing-tag check is the compensating control.)
- [x] Direct push to `main` is rejected.
- [x] `scripts/build.sh` + `scripts/verify.sh` also run successfully on a local machine
      (documented in README).
- [x] `scripts/setup-github.sh` takes a fresh local repo to a fully configured public GitHub repo
      (rulesets, environments, Actions settings) with zero manual UI actions; a second run
      converges everything back to the target state.
- [x] *(Added during implementation)* Negative-path drills: `SIM_FAIL_UPLOAD` fails the upload
      step itself on staging and is refused for production; the monotonic version guard blocks
      stale same-day re-runs (comparison logic unit-tested; pass path verified live).

## 10. Out of scope (future work for the real desktop application)

- Real compilation, code signing, and installers (MSI/MSIX/DMG) — the `build.sh` seam is where
  this plugs in.
- Windows/macOS runners or a build matrix (swap/extend `runs-on`).
- Build provenance attestations (`actions/attest-build-provenance`) and SBOMs.
- "Build once, re-stamp per environment" instead of rebuild-per-environment.
- Enforce "the released SHA had a successful staging run" for regular production releases (with an
  explicit bypass for `hotfix/*`, which skips staging by design).
- Auto-deployment to update channels / package managers.

## 11. Open items

- **Repo owner:** the setup script defaults to the authenticated user's personal account; pass an
  organization owner if it should live elsewhere. Visibility is decided: **public**.
- **Production reviewers:** supplied to `scripts/setup-github.sh` via `--approvers`. Until the
  other four developers have access, the owner can be the sole approver — but with
  prevent-self-review enabled, a release the owner dispatches needs someone else to approve; the
  script warns when this configuration is detected.
