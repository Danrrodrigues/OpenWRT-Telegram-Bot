# AI Agent Rules & Guardrails

This file instructs AI agents (Claude, Codex, Copilot, Gemini, Cursor, etc.)
working on this repository. It is the **canonical** guardrail document and is
auto-loaded by most agentic tools from the repo root.

> These are guardrails, not suggestions. If a request conflicts with a hard rule
> below, stop and surface the conflict to the human instead of silently breaking
> the rule.

---

## 🚧 Hard Rules (non-negotiable)

1. **English only for everything in the repo and on GitHub** — code, comments,
   identifiers, commit messages, branch names, **PR titles, and PR descriptions**.
   Portuguese is allowed *only* inside `README.pt-BR.md` and explicitly
   translated `docs/`. (User-facing bot strings live in `src/lang/` and may be
   translated — see Internationalization below.)
2. **All tests must pass before you push or open/update a PR.** Run the full
   suite locally (see Testing). Never push red.
3. **shellcheck must be clean** (zero warnings, matching CI flags) on every
   `*.sh` file before pushing.
4. **If you encounter a pre-existing failing test, fix it** (or clearly explain
   why it cannot be fixed in this change). Do not ignore unrelated red tests you
   have the ability to fix.
5. **Keep `README.md` and `README.pt-BR.md` in sync** — never update one without
   the other.
6. **Never log, print, or commit secrets** — Telegram bot tokens and chat IDs
   must never appear in output, logs, or git history.
7. **POSIX `sh` only** — OpenWRT uses `ash` (busybox), not `bash`. No bashisms
   (see Code Quality).

---

## Testing

- Run the full suite before every push:
  ```sh
  for f in tests/*_test.sh; do sh "$f" || echo "FAIL: $f"; done
  ```
- Run shellcheck exactly as CI does (pinned to v0.11.0):
  ```sh
  for f in $(find . -name "*.sh" -not -path "./.git/*"); do
    shellcheck -x --source-path=SCRIPTDIR --shell=sh -e SC2018,SC2019,SC3043 "$f"
  done
  ```
- Every new feature or bugfix must add or update tests under `tests/`.
- Tests must be hermetic: stub network (`curl`/`wget`), `telegram_send`, and the
  clock (`date`) rather than hitting the real Telegram API. Keep all state inside
  a per-run temp dir.
- Tests must pass under both `bash` and `dash`/`ash` (CI's `/bin/sh` is strict).
- If your branch is based on an out-of-date `main`, rebase onto `origin/main`
  before pushing — CI runs the merge result, so a stale base can fail tests that
  pass locally.

## Documentation

- Always update `README.md` and relevant `docs/` files when adding or changing
  features.
- Keep `README.pt-BR.md` in sync with `README.md` after every change.
- Every new command must be documented in `docs/commands.md`.
- Keep the changelog section in `README.md` (and `README.pt-BR.md`) up to date.

## Code Quality

- All shell scripts must pass `shellcheck` with zero warnings before any PR is
  merged.
- Use POSIX-compatible `sh` syntax — OpenWRT uses `ash`, not `bash`. Avoid
  bashisms:
  - No `[[ ]]`, use `[ ]`
  - No arrays, use newline-delimited strings
  - No `${var^^}` / `${var,,}` case ops; no `10#$n` base conversion
  - No `local` at the top level (use it only inside functions)
  - No `source`, use `.`
- Each function must have a single, clear responsibility.
- Prefix internal/private functions with `_` (e.g., `_bw_resolve_mac`).

## Security

- Never log or expose Telegram bot tokens or chat IDs in any output, log, or
  commit.
- Config files containing credentials must have `chmod 600`.
- Validate all user input before passing it to shell commands (prevent
  injection).
- Never store sensitive data in `/tmp` without restricting permissions.

## Open Source Standards

- English is the primary language for code, comments, commit messages, PR titles,
  and PR descriptions.
- Portuguese translations are welcome in `docs/` and `README.pt-BR.md`.
- Commit messages must be in English, imperative mood: `Add block command`, not
  `Added block command`.
- Every PR must include a usage example or test scenario for the changed feature.
- Do not add features beyond what the current issue or PR requests (YAGNI).

## Internationalization (bot messages)

- User-facing bot strings live in `src/lang/<code>.sh` as `T_*` `printf`
  templates plus the `I18N_COMMANDS` menu list. `src/core/i18n.sh` loads the file
  selected by the `lang` config option, falling back to `en`.
- When adding a user-facing message, add the key to **every** `src/lang/*.sh`
  file, keeping the same keys and command count across languages.
- To add a new language, copy `src/lang/en.sh`, translate the values, and the
  `lang` option will pick it up.

## Compatibility

- Scripts must run on OpenWRT 23.05 and later.
- Test primary functionality with and without optional packages (`nft-qos`,
  `iw`, `hostapd_cli`).
- Minimize external package dependencies — `curl` and `jsonfilter` are the only
  hard requirements.
- Do not assume a specific Wi-Fi chip or driver; use standard tools (`iw dev`,
  `hostapd_cli`).

## Project Structure

- Core logic lives in `src/core/` — no feature-specific code there.
- Feature modules live in `src/modules/` — one file per feature domain.
- Language files live in `src/lang/`.
- Installers (`install.sh`, `uninstall.sh`) live at the repo root.
- Documentation lives in `docs/`.
