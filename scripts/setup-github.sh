#!/usr/bin/env bash
# One-shot, idempotent GitHub bootstrap for this repository, via the gh CLI.
# Creates the public repo (if missing), pushes main, and converges all
# protections to the target configuration in PLAN.md §8. Safe to re-run.
#
# Usage:
#   scripts/setup-github.sh [--owner OWNER] [--repo NAME]
#                           [--approvers user1,user2] [--allow-self-review]
#
# Defaults: owner = authenticated gh user, repo = directory name,
#           approvers = authenticated gh user.
set -euo pipefail

OWNER=""
REPO=""
APPROVERS=""
PREVENT_SELF_REVIEW=true

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)             OWNER="$2"; shift 2 ;;
    --repo)              REPO="$2"; shift 2 ;;
    --approvers)         APPROVERS="$2"; shift 2 ;;
    --allow-self-review) PREVENT_SELF_REVIEW=false; shift ;;
    -h|--help)           sed -n '2,12p' "$0"; exit 0 ;;
    *)                   die "unknown argument: $1 (see --help)" ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# ---------------------------------------------------------------- preflight
command -v gh >/dev/null 2>&1 || die "gh CLI is not installed — https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login'"
auth_user="$(gh api user --jq .login)"

OWNER="${OWNER:-$auth_user}"
REPO="${REPO:-$(basename "$repo_root")}"
APPROVERS="${APPROVERS:-$auth_user}"
full="$OWNER/$REPO"

git rev-parse HEAD >/dev/null 2>&1 || die "no commits yet — create the initial commit first"
current_branch="$(git symbolic-ref --short HEAD)"
if [[ "$current_branch" == "master" ]]; then
  info "Renaming local branch master -> main"
  git branch -m master main
elif [[ "$current_branch" != "main" ]]; then
  die "run from 'main' (or 'master', which gets renamed); current branch is '$current_branch'"
fi

# ------------------------------------------------------- repo create + push
if gh repo view "$full" >/dev/null 2>&1; then
  info "Repository $full already exists"
  if ! git remote get-url origin >/dev/null 2>&1; then
    proto="$(gh config get git_protocol 2>/dev/null || echo https)"
    if [[ "$proto" == "ssh" ]]; then
      origin_url="$(gh repo view "$full" --json sshUrl --jq .sshUrl)"
    else
      origin_url="$(gh repo view "$full" --json url --jq .url).git"
    fi
    info "Adding origin remote: $origin_url"
    git remote add origin "$origin_url"
  fi
  info "Pushing main"
  git push -u origin main
else
  info "Creating public repository $full and pushing main"
  gh repo create "$full" --public \
    --description "Proof-of-concept CI/CD release pipeline (GitHub Actions)" \
    --source "$repo_root" --remote origin --push
fi

info "Configuring default branch and merge methods (squash only)"
gh repo edit "$full" \
  --default-branch main \
  --enable-squash-merge=true \
  --enable-merge-commit=false \
  --enable-rebase-merge=false \
  --delete-branch-on-merge=true >/dev/null

# ----------------------------------------------------------------- rulesets
ruleset_id() {
  gh api "repos/$full/rulesets" --jq ".[] | select(.name==\"$1\") | .id" | head -n 1
}

apply_ruleset() {
  local name="$1" json="$2" id
  id="$(ruleset_id "$name")"
  if [[ -n "$id" ]]; then
    info "Ruleset '$name' exists (id $id) — converging"
    gh api -X PUT "repos/$full/rulesets/$id" --input - <<<"$json" >/dev/null
  else
    info "Creating ruleset '$name'"
    gh api -X POST "repos/$full/rulesets" --input - <<<"$json" >/dev/null
  fi
}

# Admin bypass is restricted to bypass_mode=pull_request: admins may merge a
# PR without the requirements (solo-bootstrap escape hatch) but can NOT push
# to main directly. Remove the bypass once the team is onboarded.
apply_ruleset "protect-main" '{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }
  ],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "build" },
          { "context": "test" } ] } }
  ]
}'

# Preferred: only the GitHub Actions app (Integration id 15368) may create
# v* tags — i.e. the release workflow; humans, including admins, are blocked.
# That bypass actor is only valid on ORG-owned repos. On personal repos, fall
# back to immutability only (no update/delete of released tags; creation stays
# open) — the release workflow still refuses to reuse an existing tag, so a
# stray manual tag fails the release loudly instead of being overwritten.
tag_ruleset_full='{
  "name": "protect-release-tags",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "creation" },
    { "type": "update" },
    { "type": "deletion" }
  ]
}'
tag_ruleset_fallback='{
  "name": "protect-release-tags",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "update" },
    { "type": "deletion" }
  ]
}'
if apply_ruleset "protect-release-tags" "$tag_ruleset_full" 2>/dev/null; then
  tag_protection="full (creation/update/deletion blocked; workflow-only bypass)"
else
  warn "GitHub Actions app cannot be a bypass actor on a user-owned repo;"
  warn "applying fallback tag ruleset: released v* tags are immutable, but tag"
  warn "creation stays open. Re-run after moving the repo to an organization"
  warn "to get full tag lockdown."
  apply_ruleset "protect-release-tags" "$tag_ruleset_fallback"
  tag_protection="fallback (update/deletion blocked; creation open — personal repo)"
fi

# ------------------------------------------------------------- environments
ensure_branch_policy() {
  local env="$1" pattern="$2"
  if ! gh api "repos/$full/environments/$env/deployment-branch-policies" \
       --jq '.branch_policies[].name' | grep -qxF "$pattern"; then
    info "Environment '$env': allowing deployments from '$pattern'"
    gh api -X POST "repos/$full/environments/$env/deployment-branch-policies" \
      -f name="$pattern" -f type=branch >/dev/null
  fi
}

info "Configuring environment 'staging'"
gh api -X PUT "repos/$full/environments/staging" --input - <<'JSON' >/dev/null
{ "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
ensure_branch_policy staging "main"
ensure_branch_policy staging "hotfix/*"

info "Configuring environment 'production' (approvers: $APPROVERS)"
reviewers=""
for u in ${APPROVERS//,/ }; do
  id="$(gh api "users/$u" --jq .id)" || die "cannot resolve GitHub user '$u'"
  reviewers+="{\"type\":\"User\",\"id\":$id},"
done
reviewers_json="[${reviewers%,}]"

gh api -X PUT "repos/$full/environments/production" --input - <<JSON >/dev/null
{
  "prevent_self_review": $PREVENT_SELF_REVIEW,
  "reviewers": $reviewers_json,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
ensure_branch_policy production "main"
ensure_branch_policy production "hotfix/*"

if [[ "$PREVENT_SELF_REVIEW" == "true" && "$APPROVERS" == "$auth_user" ]]; then
  warn "Sole production approver is you ($auth_user) and prevent-self-review is ON:"
  warn "a production release you dispatch will wait for an approval you cannot give."
  warn "Add teammates via --approvers, or re-run with --allow-self-review for solo testing."
fi
if [[ "$PREVENT_SELF_REVIEW" == "false" ]]; then
  warn "prevent-self-review is OFF — re-run without --allow-self-review once the team is onboarded."
fi

# --------------------------------------------------------- Actions defaults
info "Locking down Actions defaults (read-only token, no PR approval)"
gh api -X PUT "repos/$full/actions/permissions/workflow" --input - <<'JSON' >/dev/null
{ "default_workflow_permissions": "read", "can_approve_pull_request_reviews": false }
JSON

# ------------------------------------------------------------------ summary
cat <<EOF

Bootstrap complete for https://github.com/$full
  - default branch 'main' pushed; squash-merge only; delete-branch-on-merge
  - ruleset 'protect-main': PR + 1 approval + codeowner review + checks
    (build, test); no force-push/deletion; linear history;
    admin bypass via PR only (remove once team is onboarded)
  - ruleset 'protect-release-tags': $tag_protection
  - environment 'staging': deployments from main + hotfix/*
  - environment 'production': required reviewers ($APPROVERS),
    prevent_self_review=$PREVENT_SELF_REVIEW, deployments from main + hotfix/*
  - Actions: read-only default token, cannot approve PRs

Re-running this script converges everything back to this state.
EOF
