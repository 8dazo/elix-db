# Step 1: Project Scaffold

**Status:** Done

## Goal

Create the Mix project and application skeleton: `elix_db` app, `ElixDb.Application` with supervision tree. No vector logic yet—only a running BEAM application.

## Tasks

- [ ] Run `mix new elix_db --sup` (or create project with supervision).
- [ ] Ensure `lib/elix_db/application.ex` exists and starts a supervision tree (e.g. empty children or a placeholder).
- [ ] Ensure `mix test` runs (default test passes).
- [ ] Optional: add `.formatter.exs` and `mix format`; add ExUnit config in `test/test_helper.exs` if needed.

## Debug

- Start app: `iex -S mix`
- In IEx: `Application.started_applications()` should include `:elix_db`.
- Run: `mix test`

## Verify

- [ ] `mix compile` succeeds with no warnings.
- [ ] `mix test` passes.
- [ ] IEx starts and the application is listed as started.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Project layout | Service binary / multi-process | Mix app, OTP | Standard Elixir; no API yet. |
| Startup | Config-driven | Supervision tree | Add config in later steps. |

**Efficiency notes:** N/A for scaffold. Document when steps 2–8 add behavior.
