# AI Agent Rules

The canonical agent guardrails for this repository live in **[`/AGENTS.md`](../AGENTS.md)**
at the repo root (auto-loaded by most agentic tools).

Please read and follow that file. Highlights:

- English only for code, comments, commits, **and PR titles/descriptions**.
- All tests and `shellcheck` must pass before pushing or opening a PR.
- Fix pre-existing failing tests you encounter.
- Keep `README.md` and `README.pt-BR.md` in sync.
- POSIX `sh` only (OpenWRT `ash`); never log secrets.
