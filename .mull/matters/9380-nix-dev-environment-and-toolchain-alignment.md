---
status: planned
tags: [design, nix]
created: 2026-10-23
updated: 2026-10-23
epic: platform
relates: [47ae]
---

# Nix dev environment and toolchain alignment

# Nix dev environment and toolchain alignment

## Goal

Get every environment on the same toolchain and Postgres major version, and make the dev environment reproducible with a Nix flake. First step of a longer, incremental path toward Nix-built releases and eventually NixOS hosting off Fly (see Future steps). Learning Nix along the way is an explicit goal.

## Drift found (2026-10-23)

| | Elixir / OTP | Postgres |
|---|---|---|
| Local (Jeff) | 1.19.5 / 28 | 18.3 (Postgres.app) |
| CI (`ci.yml`, smoke test in `deploy.yml`) | 1.19 / 28 (setup-beam) | `postgres:17` service |
| Prod image (`Dockerfile`, `Dockerfile.preview`) | **1.17.3 / 27.1.2** (hexpm alpine) | Fly `postgres-flex:17.2` |
| README | 1.19.0 / 28.0 | **16+** |

Prod compiles with an older Elixir/OTP than CI tests with. Typst is downloaded in the Dockerfile with no checksum.

## Decisions

- **Postgres stays on 17 everywhere for now.** Dev moves from Postgres.app 18 to Nix-managed 17. No prod DB work in this matter.
- **Elixir 1.19 / OTP 28 everywhere**, exact patch versions chosen once and shared by flake and Dockerfiles.
- **Plain flake + small scripts** for dev Postgres (initdb / pg_ctl wrapped in make targets or scripts). No devenv / services-flake / process-compose for now — less to learn up front; revisit if the scripts hurt.
- **Never assume port 5432 locally.** A dev env shipping a hard-coded common port collides with existing Postgres installs.

## Design

### 1. Dockerfile fixes (no Nix)
- `Dockerfile` and `Dockerfile.preview`: bump builder image to the chosen 1.19.x / OTP 28.x hexpm tag.
- Verify the Typst download against a pinned sha256 in both.

### 2. `flake.nix` dev shell
- Pins: Elixir + OTP (matching Dockerfile), Node 22, Python + `uv` (for the new producer `services/import-producer/` and `priv/import/validate.py`; version from import-producer's `requires-python`, currently `>=3.12`), the producer's system deps for `ocrmypdf` (Tesseract, Ghostscript — confirm the full list then), Typst 0.14.x, libvips, Postgres 17 (server + client).
- **Updated 2026-10-23 by `47ae`:** the old pipeline's Python extractor is removed, so the prod image no longer contains Python. Python is a dev-only tool; it does not need to match Alpine. Task 3's `pymupdf4llm` risk and Step 2's `pymupdf4llm` packaging are gone (once `47ae` merges).
- direnv: `.envrc` with `use flake`, plus `source_env_if_exists .envrc.local` (gitignored) for per-user overrides.
- `flake.lock` committed; updates are deliberate.

### 3. Dev Postgres 17 (Nix-managed)
- Listens on TCP `127.0.0.1` only, on a project-specific non-default port (e.g. 54317 — pick at implementation). `PGPORT` set in `.envrc`, overridable in `.envrc.local`.
- Start script prints the port and fails clearly if it's taken.
- One shared cluster for all worktrees (same behavior as Postgres.app today): data dir outside the repo, e.g. `~/.local/share/gallformers/postgres`, overridable.
- Coexists with Postgres.app; no need to quit it.
- No Elixir config changes needed: Postgrex `default_opts/1` (`deps/postgrex/lib/postgrex/utils.ex`) fills `:port` from `PGPORT`, and `dev.exs` / `test.exs` don't set `:port`.
- Dev data reload: new 17 cluster starts empty → `make download-db` (prod pg_dump from S3, which is 17) plus the WCVP restore. Existing Postgres.app 18 data can't be restored into 17; don't try.
- Rejected: Unix-socket-only. Would need `dev.exs`/`test.exs` changes (config passes `PGHOST` as `:hostname`, bypassing Postgrex's socket-dir handling) and risks the ~104-char macOS socket path limit under `.worktrees/`.

### 4. CI uses the flake
- `ci.yml` jobs and the `deploy.yml` smoke test run via the flake dev shell instead of setup-beam / setup-node.
- Keep the `postgres:17` service container (already matches prod).
- Needs Nix store caching in Actions; choose the action during planning (verify current options/terms then).

### 5. Drift guard
- CI check that the Elixir/OTP versions in the Dockerfile builder tag match the flake's. Fails the build on mismatch. Remains until the image itself is Nix-built (Future step 2).

### 6. README
- Setup becomes: install Nix + direnv, `direnv allow`, start DB, load data. Remove brew/asdf/Postgres.app instructions.

## To verify during implementation
- ~~`Makefile:119` port-less `DATABASE_URL`~~ — resolved during planning: Ecto `parse_url/1` drops a nil port, so Postgrex falls back to `PGPORT`. No change needed.
- Exact nixpkgs Elixir/OTP patch versions vs. available hexpm/elixir tags — pick a combo that exists in both.
- Whether nixpkgs' Typst version matches the Dockerfile's 0.14.2.

## Implementation Plan

**Goal:** One pinned toolchain (Elixir/OTP, Node, Python, Typst, libvips, Postgres 17) shared by dev, CI and the prod image, with a Nix flake dev shell and a Nix-run dev Postgres on a non-default port.

**Architecture:** A `flake.nix` defines one dev shell for `aarch64-darwin` and `x86_64-linux`. direnv loads it locally; CI runs commands through `nix develop -c`. Dev Postgres is a plain cluster managed by a small script (initdb/pg_ctl) behind make targets. The Dockerfiles stay, pinned to the same versions, with a CI script that fails on drift.

**Tech Stack:** Nix flakes, nixpkgs (`beam.packages.erlang_28`, `postgresql_17`, `nodejs_22`, `typst`, `vips`, `uv`), direnv, GitHub Actions, hexpm/elixir Alpine images.

**Testing note:** This is infra/config, not app code — "Testing" below means concrete verification steps, not ExUnit tests. `mix precommit` must still pass at the end.

### Task 1: Choose the version set

**Files:** none (decision recorded in this matter).

**Behavior:**
- Pick a nixpkgs revision (start from current `nixos-unstable` or the latest stable release branch) and read its exact versions: `nix eval --raw nixpkgs#beam.packages.erlang_28.elixir_1_19.version` (confirm attribute names — not verified yet), the matching Erlang version, `typst`, `nodejs_22`, Python (per import-producer's `requires-python`), `postgresql_17`.
- Find a `hexpm/elixir` tag with the same Elixir and OTP versions. As of 2026-10-22 the published 1.19.6 Alpine tags are `1.19.6-erlang-{28.0.4,28.1.1,28.2,28.3.3,28.4.3,28.5.0.8}-alpine-3.24.3`.
- If nixpkgs' OTP patch has no hexpm tag, move the nixpkgs rev (or the hexpm tag) until they agree. Do NOT override the Erlang version in Nix — that compiles OTP locally with no binary cache.
- Record the chosen set (nixpkgs rev, Elixir, OTP, Alpine, Python, Typst) in this matter.

**Notes:** Needs Nix installed (Task 2's prerequisite). Python no longer ships in the prod image (`47ae`), so it doesn't need to match Alpine.

### Task 2: Install Nix + direnv on Jeff's Mac (manual, Jeff runs)

**Files:** none.

**Behavior:** Install Nix (pick the installer then — upstream or Determinate; verify current state of both before recommending), enable flakes if the installer doesn't, install direnv + nix-direnv, hook direnv into zsh. Postgres.app stays installed and running.

### Task 3: Dockerfile alignment

**Files:**
- Modify: `Dockerfile` (builder `FROM` tag; runtime `FROM alpine:` must match the builder's Alpine version — ERTS is linked against that Alpine's musl/OpenSSL/ncurses; Typst checksum)
- Modify: `Dockerfile.preview` (same three changes)

**Behavior:**
- Builder: `hexpm/elixir:<chosen tag>`. Runtime: `alpine:<same version>`.
- Typst: keep the `ADD` of v0.14.2 (or the version nixpkgs has, if it differs and is compatible) and verify it, e.g. `ADD --checksum=sha256:<hash> <url> /tmp/typst.tar.xz`. Get the hash from the GitHub release asset digest or by downloading once.
- Re-check `apk add` package names still exist on the new Alpine.

**Testing:**
- `docker build --platform linux/amd64 -t gallformers:align .` succeeds locally (emulated; slow is fine).
- In the built image: `/app/bin/gallformers eval 'IO.puts(System.version())'` prints the chosen Elixir version; `typst --version` works.
- Depends on `47ae` having merged (Dockerfiles without Python). If it hasn't, the `pymupdf4llm` install on Python 3.14 + musl is the main risk.
- Same build for `Dockerfile.preview`.

**Notes:** Independent of the flake; can merge on its own first. Prod deploy happens on merge to main (deploy.yml), so the local image build is the only gate before prod — be thorough.

### Task 4: `flake.nix` dev shell + direnv

**Files:**
- Create: `flake.nix`, `flake.lock`
- Create: `.envrc`
- Modify: `.gitignore` (add `.direnv/`, `.envrc.local`)

**Behavior:**
- `devShells.default` for `aarch64-darwin` and `x86_64-linux` (small `forAllSystems` helper; no flake-utils dependency needed).
- Packages: Elixir + Erlang from the chosen `beam.packages.erlang_28`, `nodejs_22`, Python, `typst`, `vips` (+ `pkg-config` if vix needs it to find libvips), `postgresql_17`, `uv`. Linux-only extras if needed (`inotify-tools` for live reload).
- `shellHook` exports the Postgres env from project-specific vars so CI and per-user overrides work, and a global `PGPORT` in someone's shell can't silently point at another server:

```sh
export GALLFORMERS_PG_PORT="${GALLFORMERS_PG_PORT:-54317}"   # final number chosen here
export GALLFORMERS_PG_HOST="${GALLFORMERS_PG_HOST:-127.0.0.1}"
export GALLFORMERS_PG_DATA="${GALLFORMERS_PG_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/gallformers/postgres-17}"
export PGHOST="$GALLFORMERS_PG_HOST" PGPORT="$GALLFORMERS_PG_PORT" PGDATA="$GALLFORMERS_PG_DATA"
```

- `.envrc`: `source_env_if_exists .envrc.local` FIRST (so overrides of `GALLFORMERS_PG_*` are visible to the shellHook), then `use flake`.
- Also keep mix/hex state project-local if needed (`MIX_HOME`/`HEX_HOME` under `.nix-mix/`) — only if global Homebrew-era state causes conflicts; don't add preemptively.

**Testing:**
- `direnv allow` in a fresh terminal: `elixir --version`, `erl` OTP version, `node -v`, `python3 --version`, `typst --version`, `psql --version` all report the Task 1 set.
- `mix deps.get && mix compile --warnings-as-errors` works (vix finds Nix libvips — check the vix compilation mode the project uses today and that it still works).
- `echo $PGPORT` shows the project port; putting `export GALLFORMERS_PG_PORT=55555` in `.envrc.local` changes it after `direnv reload`.
- Worktree: `cd .worktrees/<any>` gets the same shell (worktrees have their own `.envrc` checkout once merged; until then verify on main).

**Notes:** Data dir path includes the major version (`postgres-17`) so a future PG 18 cluster lives alongside instead of failing on an incompatible data dir. Because the data dir is outside the repo, all worktrees share one cluster — same as Postgres.app today.

### Task 5: Dev Postgres script + make targets

**Files:**
- Create: `scripts/dev-db` (POSIX sh; subcommands `start`, `stop`, `status`)
- Modify: `Makefile` (targets `db-start`, `db-stop`, `db-status`; add to `.PHONY` and `help`; mention `make db-start` in `check-db` / `wcvp-check` error messages)

**Behavior:**
- Refuses to run if `PGDATA`/`PGPORT` aren't set (i.e. not in the dev shell) with a message saying to `direnv allow` / `nix develop`.
- `start`:
  - If `$PGDATA` doesn't exist: `initdb -D "$PGDATA" --auth=trust --encoding=UTF8` (superuser = `$USER`, matching `dev.exs`/`test.exs` defaults). Locale: see notes.
  - If already running (`pg_ctl status`): print "already running on 127.0.0.1:<port>" and exit 0.
  - If the port is taken by something else (`pg_isready -h 127.0.0.1 -p $PGPORT` succeeds, or `lsof -iTCP:$PGPORT -sTCP:LISTEN`): fail with a message naming the port and how to override (`GALLFORMERS_PG_PORT` in `.envrc.local`).
  - Else `pg_ctl -D "$PGDATA" -l "$PGDATA/server.log" -o "-p $PGPORT -c listen_addresses=$PGHOST -k $PGDATA" -w start`. `-k $PGDATA` keeps the Unix socket out of `/tmp` so it never collides with Postgres.app's socket.
  - Print the connection info.
- `stop`: `pg_ctl -D "$PGDATA" -m fast stop`; no-op message if not running.
- `status`: running/not running, port, data dir, server version.

**Testing (manual):**
- Fresh: `make db-start` initializes and starts; `psql -d postgres -c 'select version()'` reports 17.x.
- With Postgres.app running on 5432: both run; `psql` in the dev shell hits 17, outside the shell hits Postgres.app 18.
- Port conflict: start something on the project port (or set `GALLFORMERS_PG_PORT=5432` while Postgres.app runs) → clear error, non-zero exit.
- `make db-start` twice → second is a no-op. `make db-stop` then `db-status` → not running.
- Outside the dev shell → refuses with the guidance message.
- Then the real thing: `make download-db`, `make wcvp-restore`, `make test` (rebuilds `gallformers_test`/`wcvp_test` on the Nix server), `make dev` serves pages. All existing make targets use `psql`/`pg_restore`/`createdb` and `mix` without host/port flags, so they follow `PGHOST`/`PGPORT` with no edits (checked: `Makefile`, `lib/mix/tasks/gallformers/wcvp/restore.ex`).

**Notes:**
- Locale/collation: sort order depends on collation and differs between macOS libc and prod/CI glibc anyway. Have Jeff check prod's `SELECT datname, datcollate, datlocprovider FROM pg_database` (he runs it — no prod access from the agent); initdb with the same locale name if it exists on macOS. Don't chase exact sort parity beyond that — out of scope.
- `run-local-release` (`Makefile:119`) needs no change (Ecto drops the nil port; Postgrex uses `PGPORT`).

### Task 6: CI runs in the flake

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/deploy.yml` (smoke-test job only)

**Behavior:**
- Replace `erlef/setup-beam` and `actions/setup-node` with a Nix install step (e.g. `cachix/install-nix-action` or `DeterminateSystems/nix-installer-action` — verify current versions and terms when implementing) and run commands as `nix develop -c <cmd>`.
- Job env sets `GALLFORMERS_PG_HOST=localhost`, `GALLFORMERS_PG_PORT=5432` so the shellHook points at the `postgres:17` service container. `USER: postgres` stays.
- The `psql`/`createdb` calls in "Setup test database" also go through `nix develop -c` (drops the dependency on the runner's preinstalled client).
- Nix store caching: start without a dedicated cache — everything in the shell should be substituted from cache.nixos.org. Measure the dev-shell setup time; add a GitHub-Actions-backed Nix cache only if it's slow.
- Keep `actions/cache` for `deps`/`_build`, but add `hashFiles('flake.lock')` to the key — compiled artifacts depend on the Elixir/OTP versions.
- Add `flake.nix`, `flake.lock`, `Dockerfile`, `Dockerfile.preview`, `scripts/**` to the `paths:` filters (push and pull_request) — today a flake- or Dockerfile-only change wouldn't run CI at all.
- Smoke test job in `deploy.yml`: same Nix install + `nix develop -c`.

**Testing:** Open the PR; Phoenix, Assets and API-version jobs pass. Compare job durations with a recent run on main and note them in the PR.

**Notes:** The `ubuntu-latest` runner is `x86_64-linux`, which the flake must support (Task 4).

### Task 7: Drift guard

**Files:**
- Create: `scripts/check-toolchain`
- Modify: `.github/workflows/ci.yml` (new step in the Phoenix job, or a small separate job)

**Behavior:**
- Runs inside the dev shell. Reads the builder tag from `Dockerfile` and `Dockerfile.preview` (`FROM hexpm/elixir:<elixir>-erlang-<otp>-alpine-<alpine>`), compares to:
  - `elixir --short-version`
  - full OTP version from `$(erl -noshell -eval 'io:format("~s",[code:root_dir()]),halt().')/releases/<major>/OTP_VERSION`
- Also checks both Dockerfiles use the same tag, and that the Typst version in the Dockerfile URL equals `typst --version`.
- On mismatch: print expected vs found per item and exit 1.

**Testing:** Passes on the aligned branch. Temporarily edit the tag in `Dockerfile` to another version → fails naming Elixir/OTP; restore. Same for a mismatched `Dockerfile.preview`.

### Task 8: README + docs

**Files:**
- Modify: `README.md` (prerequisites/install sections; Postgres "16+" line)
- Modify: `CLAUDE.md` only if agent-facing setup guidance needs it (check; keep minimal)

**Behavior:** Setup becomes: install Nix + direnv → `direnv allow` → `make db-start` → `make download-db` + `make wcvp-restore` → `make dev`. Document the port override (`GALLFORMERS_PG_PORT` in `.envrc.local`), the shared data dir and how to move it, and that Postgres.app (or any other Postgres) can keep running. Remove the brew/asdf/apt instructions for Elixir, Postgres and libvips. Playwright section stays as is.

### Order and PRs

1. Task 1 + 2 (decide versions, install Nix).
2. PR A: Task 3 (Dockerfiles). Fixes the prod drift on its own; merge first.
3. PR B: Tasks 4–8 (flake, dev DB, CI, guard, README). Jeff switches his own dev DB over (Task 5's manual run-through) before merging.

## Out of scope
Postgres 18, Nix-built release images, NixOS hosting, Nix-managed Postgres in CI.

## Future steps (roadmap, not committed)

1. **This matter** — alignment + dev shell.
2. **Nix-built release, deployed to Fly.** Package with nixpkgs `mixRelease`, ship the OCI image via `fly deploy --image`, delete the Dockerfiles. Ends Dockerfile drift for good, and the package is reused by step 3. Known work: `fetchMixDeps` hash bumps on every `mix.lock` change (incl. Dependabot PRs); esbuild 0.25.4 / tailwind 4.1.12 mix packages download binaries — point them at nixpkgs builds with matching versions; npm deps hash; vix against system libvips. x86_64-linux can't be built on Apple Silicon without a Linux builder, so builds move to CI with a binary cache.
3. **NixOS hosting off Fly**, starting with `gallformers-preview`, then prod. Fits the self-hosting direction in `41cf` (proxy) and `cd9d` (observability). Rollback becomes NixOS generations; the Fly "sleep infinity" / volume-attachment hazards go away. Cost: own Postgres ops, backups/PITR, patching, single-box SPOF.

### Parked idea: move only the DB to NixOS first, at PG 18
Discussed and deferred as too much for now. Notes if revisited:
- Pros: one DB migration (straight to final home + PG 18); addresses the 03-27 CPU-steal incident; Postgres is the easiest first NixOS service.
- Hinge: latency between Fly app and external DB — must be same metro (`fly.toml` says `ewr`; fly-operations runbook says `iad` — reconcile). Measure before committing.
- Private link: Fly supports external WireGuard peers on the org 6PN (Fly "bridge deployments" blueprint); confirm bidirectional reachability in a test.
- Backups: lose Fly's barman; set up WAL archiving to S3 on the box; `db-snapshot.yml` must stop using `fly proxy`.
- Ordering trap for any prod PG major upgrade: `pg_dump` won't dump a newer server, so bump the snapshot workflow's client before/with the prod upgrade. CI should track prod's major version, not lead it.
- Fly Postgres major upgrades are new-cluster + dump/restore (no in-place); `flyio/postgres-flex:18` exists as of 2026-08-31.
