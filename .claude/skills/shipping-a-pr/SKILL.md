---
name: shipping-a-pr
description: Use when pushing a finished change in this repo through PR, CI, review comments, merge, and a version tag/release — covers gh CLI commands, branch-protection gotchas, and where Codex review comments actually live.
---

# Shipping a PR in this repo (push → CI → review → merge → tag)

## Overview

This repo's `main` is protected: required status check `shellcheck` (strict —
branch must be up to date), and `required_conversation_resolution: true`.
A squash-merge workflow means feature branches go stale fast. This skill is
the checklist for getting a change from local commit to a tagged release
without getting stuck on the non-obvious blockers below.

## Quick Reference

| Step | Command |
|---|---|
| Run full test suite locally | `for f in tests/*_test.sh; do sh "$f" || echo "FAIL: $f"; done` |
| Push branch | `git push origin <branch>` |
| Open PR | `gh pr create --title "..." --body "..."` |
| Check CI | `gh pr checks <PR#>` |
| Find ALL review feedback (see below) | GraphQL `reviewThreads` query |
| Resolve a thread (required before merge) | GraphQL `resolveReviewThread` mutation |
| Check why merge is blocked | `gh pr view <PR#> --json mergeStateStatus,mergeable` |
| Merge | `gh pr merge <PR#> --squash --delete-branch=false` |
| Tag + release | `gh release create vX.Y.Z --target main --title "vX.Y.Z" --notes "..."` |

## Gotcha 1: `gh pr checks` shows nothing / no run triggers

If `gh pr checks <PR#>` reports "no checks reported" and `gh run list` shows
no run for your new commit, check `mergeable_state`:

```bash
gh api repos/<owner>/<repo>/pulls/<PR#> --jq '{mergeable, mergeable_state}'
```

`"mergeable_state": "dirty"` means the branch has diverged from `main` (very
common here because PRs are squash-merged — your local branch still has the
old pre-squash commit with a different SHA than what landed on `main`). CI
won't run cleanly against a PR it can't auto-merge for testing. Fix:

```bash
git fetch origin
git rebase origin/main
git push --force-with-lease origin <branch>
```

## Gotcha 2: CI is green but `mergeStateStatus` is still `BLOCKED`

`gh pr merge` fails with "the base branch policy prohibits the merge" even
though both required checks show `success`. This repo requires conversation
resolution. Check for unresolved review threads — **these often don't show
up in `gh api .../pulls/<PR#>/comments` or `.../issues/<PR#>/comments`**.
The Codex review bot (`chatgpt-codex-connector`) posts as a review thread,
which only shows via GraphQL:

```bash
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 20) {
        nodes { id isResolved comments(first:3){nodes{body author{login}}} }
      }
    }
  }
}'
```

Read every unresolved thread's body — Codex has flagged real P1 bugs here
before (e.g. a new module not added to `install.sh`'s copy list, which would
silently break fresh installs/`/update`). Fix the underlying issue first,
push the fix, reply on the PR, then resolve the thread:

```bash
gh api graphql -f query='
mutation { resolveReviewThread(input: {threadId: "THREAD_ID"}) { thread { isResolved } } }'
```

Re-check `mergeStateStatus` — should flip to `CLEAN`.

## Gotcha 3: new module added but bot won't start after install/update

If a new file under `src/modules/*.sh` is added and sourced from
`src/bot.sh`, it must ALSO be added to `_copy_files()` in `install.sh`
(explicit `cp` list, not a glob). Otherwise fresh installs and remote
`/update` ship a `bot.sh` that sources a file that was never copied, and the
service crashes on startup. Add a regression assertion in
`tests/install_update_test.sh` (`assert_file_exists` for the new module path
in the installed dir) when you do this.

## End-to-end sequence

1. Implement + write/update `tests/<module>_test.sh`, run the full suite locally.
2. Bump `VERSION` in `src/bot.sh`; add a changelog line to **both**
   `README.md` and `README.pt-BR.md` (never one without the other).
3. Commit, push, `gh pr create`.
4. `gh pr checks <PR#>` — if no run appears, see Gotcha 1.
5. Run the GraphQL `reviewThreads` query — read and act on any Codex
   feedback, even if `gh pr checks` is all green.
6. Once threads are resolved and checks pass, confirm
   `mergeStateStatus: CLEAN`, then `gh pr merge --squash`.
7. Wait for CI to finish on the merge commit on `main`
   (`gh run list --branch main --limit 2`).
8. `gh release create vX.Y.Z --target main ...` — this creates the tag too;
   verify with `git fetch --tags && git tag --sort=-v:refname | head -3`.
