# AI Agent Rules

This file instructs AI agents (Claude, Copilot, Gemini, etc.) working on this repository.

## Documentation

- Always update `README.md` and relevant `docs/` files when adding or changing features.
- Keep `README.pt-BR.md` in sync with `README.md` after every change.
- Every new command must be documented in `docs/commands.md`.
- Keep the changelog section in `README.md` up to date.

## Code Quality

- All shell scripts must pass `shellcheck` with zero warnings before any PR is merged.
- Use POSIX-compatible `sh` syntax — OpenWRT uses `ash`, not `bash`. Avoid bashisms:
  - No `[[ ]]`, use `[ ]`
  - No `$(( ))` for string ops, use `expr` or `awk`
  - No arrays, use newline-delimited strings
  - No `local` in functions at the top level (use it only inside functions)
  - No `source`, use `.`
- Each function must have a single, clear responsibility.
- Prefix internal/private functions with `_` (e.g., `_bw_resolve_mac`).

## Security

- Never log or expose Telegram bot tokens or chat IDs in any output, log, or commit.
- Config files containing credentials must have `chmod 600`.
- Validate all user input before passing it to shell commands (prevent injection).
- Never store sensitive data in `/tmp` without restricting permissions.

## Open Source Standards

- English is the primary language for code, comments, commit messages, and docs.
- Portuguese translations are welcome in `docs/` and `README.pt-BR.md`.
- Commit messages must be in English, imperative mood: `Add block command`, not `Added block command`.
- Every PR must include a usage example or test scenario for the changed feature.
- Do not add features beyond what the current issue or PR requests (YAGNI).

## Compatibility

- Scripts must run on OpenWRT 23.05 and later.
- Test primary functionality with and without optional packages (`nft-qos`, `iw`, `hostapd_cli`).
- Minimize external package dependencies — `curl` and `jsonfilter` are the only hard requirements.
- Do not assume a specific Wi-Fi chip or driver; use standard tools (`iw dev`, `hostapd_cli`).

## Project Structure

- Core logic lives in `src/core/` — no feature-specific code there.
- Feature modules live in `src/modules/` — one file per feature domain.
- Installers (`install.sh`, `uninstall.sh`) live at the repo root.
- Documentation lives in `docs/`.
