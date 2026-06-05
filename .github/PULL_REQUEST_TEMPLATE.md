<!--
  Please write this PR in English (title and description).
  See AGENTS.md at the repo root for the full contributor guardrails.
-->

## Summary

Brief description of what this PR changes and why.

## Changes

- [ ] New feature / command
- [ ] Bug fix
- [ ] Documentation update
- [ ] Refactor

## Testing

Describe how you tested this change:

```sh
# Run the full test suite
for f in tests/*_test.sh; do sh "$f" || echo "FAIL: $f"; done

# Example: command used and expected output
```

**Router tested on:** (e.g., Xiaomi AX3000T, OpenWRT 24.10.2) — or "N/A (logic-only change, covered by tests)"

## Checklist

- [ ] PR title and description are in **English**
- [ ] All tests pass locally (`for f in tests/*_test.sh; do sh "$f"; done`)
- [ ] `shellcheck` passes with zero warnings (CI flags: `shellcheck -x --source-path=SCRIPTDIR --shell=sh -e SC2018,SC2019,SC3043 <file>`)
- [ ] New/changed behavior is covered by tests under `tests/`
- [ ] Branch is rebased on the latest `origin/main` (CI runs the merge result)
- [ ] `README.md` updated (if feature changed)
- [ ] `README.pt-BR.md` kept in sync with `README.md`
- [ ] `docs/commands.md` and the changelog updated (if commands/behavior changed)
- [ ] New user-facing strings added to **every** `src/lang/*.sh` (if any)
- [ ] POSIX `sh` only — no bashisms (OpenWRT uses `ash`)
- [ ] No credentials or personal data in this PR
