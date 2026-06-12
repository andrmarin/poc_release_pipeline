# How to release

A click-by-click guide for releasing this project. No prior GitHub Actions experience
needed. If a term is unfamiliar, the [README](../README.md) explains the moving parts.

> 📸 Screenshots are placeholders for now — drop the real images into `docs/img/`
> using the file names given in each placeholder.

## The 30-second version

| I want to... | Do this |
|---|---|
| test a release candidate | run the **Release** workflow with environment **staging** |
| ship to users | run the **Release** workflow with environment **production**, then a reviewer approves |
| fix production while `main` has unreleased work | make a `hotfix/*` branch from the last production tag, then release **from that branch** |

Releases are always triggered from the `main` branch (or a `hotfix/*` branch); the
workflow refuses anything else. Version numbers are generated automatically — you never
type one.

---

## Release to staging

Staging is safe to run anytime: it produces a downloadable build artifact, no tag, no
public release, and needs no approval.

### In the browser

1. Open the repository on github.com and click the **Actions** tab (top of the page).

   > 📸 **Screenshot placeholder** — *the repository header with the Actions tab highlighted.*
   > <!-- ![Actions tab](img/release-01-actions-tab.png) -->

2. In the **left sidebar**, under "All workflows", click **Release**.

   > 📸 **Screenshot placeholder** — *Actions page with the "Release" workflow selected in the sidebar.*
   > <!-- ![Release workflow](img/release-02-release-workflow.png) -->

3. On the right side, click the **Run workflow** dropdown button. In the panel that
   opens: leave **Branch: main** as is, set **Target environment** to **staging**, and
   click the green **Run workflow** button.

   > 📸 **Screenshot placeholder** — *the "Run workflow" panel with branch `main` and environment `staging` selected.*
   > <!-- ![Run workflow panel](img/release-03-run-workflow-staging.png) -->

4. A new run named **"Release: staging @ main"** appears in the list after a few
   seconds (refresh if needed). Click it and watch the jobs turn green:
   `guard` → `build` → `test`. (`publish` and `post-publish verify` stay skipped —
   they are production-only.)

5. Your build is at the **bottom of the run page**, in the **Artifacts** section:
   `sample-app-staging`. Click it to download a ZIP containing the build and its
   checksum. It is kept for 30 days.

   > 📸 **Screenshot placeholder** — *run page scrolled to the Artifacts section with `sample-app-staging` visible.*
   > <!-- ![Staging artifact](img/release-04-staging-artifact.png) -->

### From the terminal

```sh
gh workflow run release.yml --ref main -f environment=staging
gh run watch   # then pick the newest run, or just watch it in the browser
```

---

## Release to production

Production does everything staging does, **plus**: a reviewer must approve, and on
success a Git tag and a public [GitHub Release](https://github.com/andrmarin/poc_release_pipeline/releases)
with the ZIP + `.sha256` are created — fully automatically after the approval.

1. Trigger exactly like staging (steps 1–3 above), but set **Target environment** to
   **production**.

2. The run starts and then **pauses** — the `build` job shows "Waiting for review".
   This is the safety gate. A yellow banner appears at the top of the run page.

   > 📸 **Screenshot placeholder** — *run page with the yellow "This workflow is awaiting approval" banner.*
   > <!-- ![Waiting for review](img/release-05-waiting-review.png) -->

3. **The approver** (anyone configured as a production reviewer — by default not the
   person who started the run) clicks **Review deployments** in that banner, ticks the
   **production** checkbox, optionally leaves a comment, and clicks
   **Approve and deploy**.

   > 📸 **Screenshot placeholder** — *the "Review pending deployments" dialog with production ticked and the Approve and deploy button.*
   > <!-- ![Approve deployment](img/release-06-approve.png) -->

4. From here, **no more clicks** — watch the jobs finish:
   `build` → `test` → `publish` → `post-publish verify`. The publish job creates a
   draft release, verifies both files made it, then publishes; the last job downloads
   the *published* release and verifies it end to end.

5. Find the result on the **Releases page** (repository front page → "Releases" in the
   right sidebar, or the *latest release* badge in the README). The new version —
   e.g. `v2026.06.12.0045` — is at the top, marked **Latest**, with two assets:
   the ZIP and its `.sha256` checksum.

   > 📸 **Screenshot placeholder** — *Releases page with the new version at the top, marked Latest, two assets expanded.*
   > <!-- ![Releases page](img/release-07-releases-page.png) -->

> **Note:** the release builds the commit `main` pointed at when the run was **dispatched**.
> PRs merged while the run waits for approval are *not* included — dispatch a fresh run if you
> want them.

### From the terminal

```sh
gh workflow run release.yml --ref main -f environment=production
# approval still happens in the browser (step 2-3 above)
gh release view --web   # opens the latest release when done
```

---

## Hotfix release

Use this when production is broken but `main` already contains unreleased features you
do **not** want to ship yet.

1. Find the **last production tag** on the Releases page (the version marked Latest,
   e.g. `v2026.06.12.0045`).
2. Branch **from that tag** — not from `main`:

   ```sh
   git fetch --tags
   git switch -c hotfix/fix-crash v2026.06.12.0045
   ```

3. Make the fix, push the branch, and open a PR into `main`. This PR gets the one and
   only code review.
4. After the PR is approved — but **before merging it** (merging auto-deletes the
   branch, and a deleted branch cannot be dispatched) — run the **Release** workflow:
   in the **Run workflow** panel select **your hotfix branch** instead of `main`,
   environment **production**. Approval works the same as above. Heads-up: the run
   executes the pipeline *as it exists on your hotfix branch*, i.e. as of the tag you
   branched from.

   > 📸 **Screenshot placeholder** — *Run workflow panel with branch `hotfix/fix-crash` selected and environment `production`.*
   > <!-- ![Hotfix dispatch](img/release-08-hotfix-dispatch.png) -->

5. **Merge the hotfix PR into `main`** after the release. This is required: the next
   regular production release **fails on purpose** if a released hotfix was never
   merged back (so the fix can't silently disappear). Squash-merging is fine — the
   guard recognizes the merged PR.

Optional rehearsal: dispatch a **staging** release from the hotfix branch first.

---

## How do I know a release is good?

- All jobs in the run are green — especially **post-publish verify**, which downloads
  the actual published file and re-checks it.
- On the release, the ZIP contains a `build.info` stating
  `environment=production`, the version, the commit, and a link back to the CI run.
- Verify a downloaded ZIP yourself anytime:

  ```sh
  gh release download --pattern '*'   # in an empty folder
  bash scripts/verify.sh sample-app-*.zip production
  ```

## Troubleshooting

| What you see | Why | What to do |
|---|---|---|
| Annotation: *"Simulated failure — SIM_FAIL_UPLOAD drill"* | someone armed the failure drill | `gh variable set SIM_FAIL_UPLOAD --body false`, re-run ([README](../README.md#simulating-failures-negative-path-drills)) |
| `guard` fails: *"must be dispatched from 'main' or a 'hotfix/*' branch"* | workflow was run from some other branch | re-run, selecting `main` (or your `hotfix/*` branch) in the Run workflow panel |
| `guard` fails: *"SIM_FAIL_UPLOAD is enabled"* on production | drill left armed; production refuses to run with simulations on | disarm (see first row), re-run |
| `build` fails: *"Latest production tag ... is not an ancestor of main"* | a hotfix was released but its PR never merged into `main` | merge the hotfix PR, then re-run |
| `publish` fails: *"Tag ... already exists"* | a version collision from a re-run | dispatch a **new** run (fresh run number) instead of re-running |
| `build` fails: *"Computed version ... is not newer than the latest release"* | you re-ran an old failed run; its frozen run number now computes an outdated version | dispatch a **new** run from the Run workflow panel instead of re-running |
| Run stuck on *"Waiting for review"* | nobody approved the production gate | an eligible reviewer must click Review deployments → Approve; the person who dispatched may not be allowed to approve themselves |
