---
status: done
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
- ~~No Elixir config changes needed~~ **Wrong (found 2026-10-23):** `ecto_sql`'s `Ecto.Adapters.Postgres.Connection` (`deps/ecto_sql/lib/ecto/adapters/postgres/connection.ex:14`) does `Keyword.put_new(:port, 5432)` before Postgrex's `PGPORT` default, so pooled connections (migrations, the app) went to 5432 while `ecto.create`/`drop` honored `PGPORT`. Fixed by setting `port: String.to_integer(System.get_env("PGPORT", "5432"))` on both repos in `dev.exs` and `test.exs`.
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
- ~~`Makefile:119` port-less `DATABASE_URL`~~ — the planning-time conclusion was wrong (same ecto_sql 5432 default as above); `run-local-release` now builds the URL from `PGHOST`/`PGPORT`.
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

**Result (2026-10-23):**
- nixpkgs-unstable rev `5adc50831c259f87faeb09ddf930d43597197473` (`nixpkgs-26.11pre1097770`). Attribute names confirmed: `beam.packages.erlang_28.elixir_1_19`, `beam.packages.erlang_28.erlang`.
- **Elixir 1.19.6 / OTP 28.5.0.8** — exact match with `hexpm/elixir:1.19.6-erlang-28.5.0.8-alpine-3.24.3` (amd64 + arm64). Runtime stage → `alpine:3.24.3`.
- Node 22.23.3, Postgres 17.11 (prod is postgres-flex 17.2 — same major), vips 8.18.7, Python 3.13.16 (`python313`; default `python3` is 3.14.8).
- All of the above are prebuilt in cache.nixos.org for aarch64-darwin (`nix build --dry-run`: 115 paths fetched, nothing built).
- **Typst: nixpkgs has 0.15.1, Dockerfile has 0.14.2.** 0.15.0 breaking changes (removed `path`/`pattern`/`pdf.embed`/scoped `decode`, backslash file paths, baseline/math layout changes) — `priv/typst/key.typ` uses none of the removed features. `pdf_generator_test.exs --include typst` passes under 0.15.1. Possible silent layout shifts are not covered by tests — eyeball a generated key PDF. **Decided (Jeff, 2026-10-23): bump the Dockerfiles to Typst 0.15.1**; flake uses nixpkgs `typst`.
- **Decided (Jeff, 2026-10-23): Python 3.13 (`python313`)** — import-producer has only been run on 3.13 (`cpython-313` bytecode); Docling on 3.14 unverified.

### Task 2: Install Nix + direnv on Jeff's Mac (manual, Jeff runs)

**Files:** none.

**Behavior:** Install Nix (pick the installer then — upstream or Determinate; verify current state of both before recommending), enable flakes if the installer doesn't, install direnv + nix-direnv, hook direnv into zsh. Postgres.app stays installed and running.

**Result (2026-10-23):** Done. NixOS community installer (`artifacts.nixos.org/nix-installer`, upstream Nix 2.35.4, `--enable-flakes`; chosen over Determinate, which since 2026-01 only installs Determinate Nix). direnv 2.38.2 from Homebrew (no Homebrew formula exists for Nix or nix-direnv); nix-direnv via `nix profile`. Gotcha: the installer only hooks `/etc/zshrc`, which Claude Code's shell doesn't load — Jeff added the `nix-daemon.sh` sourcing to `~/.zshrc` (also protects against macOS updates resetting `/etc/zshrc`).
- Agent commands don't trigger direnv's prompt hook. **Solved (2026-10-23)** with Claude Code's documented pattern (code.claude.com/docs/en/hooks-guide, direnv section): global hooks in `~/.claude/settings.json` — `SessionStart` and `CwdChanged` run `direnv export bash > "$CLAUDE_ENV_FILE"`, `FileChanged` (matcher `.envrc|flake.nix|flake.lock`) re-exports. Claude Code runs that file before every Bash command, so no `nix develop -c` prefixes. Timeout 300s for a cold nix-direnv build. Still to verify once the flake exists: that subagents' Bash commands get it (undocumented).

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

**Result (2026-10-23), branch `align-toolchain-versions`:**
- Done: builder `hexpm/elixir:1.19.6-erlang-28.5.0.8-alpine-3.24.3`, runtime `alpine:3.24.3`, Typst 0.15.1 verified with `sha256sum -c` in `RUN` (not `ADD --checksum`, which needs a newer Dockerfile frontend that Fly's builder may not have).
- **Root cause found while testing — OTP 28.5.0.6 httpc header limit.** OTP 28.5.0.6 (OTP-20343, inets 9.6.2.3) made `httpc` reject responses with more than 10240 bytes of headers unless the caller passes the new `max_header_size` option. GitHub release-download redirects carry ~10.8 KB of headers (long signed `Location`), so every Elixir tool that fetches GitHub releases with plain `httpc` fails on OTP ≥ 28.5.0.6: vix's precompiled NIF (via `elixir_make` 0.9.0 — which hides it as `:enoent`; 0.10.0 doesn't fix it), vix's precompiled libvips (`header_too_long`; still so in vix 0.42.0), and the `tailwind` package's binary download. esbuild is unaffected (npm). Reproduced with the same request: OTP 27.1.2 → 200; OTP 28.5.0.8 → `{:header_too_long, {:max, 10240}}`. The libvips header errors in the log are noise from vix's Makefile running dependency generation before the (failing) libvips download.
- **Fix in both Dockerfiles:** `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` + `pkgconf` (vix 0.36.0 compiles cleanly against Alpine's libvips 8.18.2 and links `/usr/lib/libvips.so.42`); Tailwind 4.1.12 x64-musl binary placed at `/app/_build/tailwind-linux-x64-musl` via `ADD` + `sha256sum -c`, so the tailwind package skips its download. Same direction a Nix-built image needs (no network in builds).
- **Verified:** emulated linux/amd64 build of `Dockerfile` passes; in the release, Elixir 1.19.6, ERTS 16.4.0.7, Typst 0.15.1, and vix creates an image through system libvips (`Vix.Vips.Operation.black/2`).
- **Local-only gotcha:** under QEMU (amd64 on Apple Silicon) the OTP 28 JIT crashes at boot (`prim_tty:isatty` `nif_error undef`). Workaround for local emulated builds only: `ENV ERL_FLAGS="+JMsingle true"` in a scratch copy of the Dockerfile. Not needed on Fly (native amd64) or native arm64.
- **Latent elsewhere:** CI already runs OTP 28.5.0.8 (setup-beam `28`) and passes only because the `deps`/`_build` cache (compiled vix, downloaded tailwind) is restored. A cold cache would fail the same way. Tasks 4 and 6 must set `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS` (with libvips + pkg-config in the shell) and provide Tailwind (nixpkgs `tailwindcss_4`, matching version, via `config :tailwind, path:` or the `_build/tailwind-<target>` location).
- Upstream: worth reporting to `elixir_make`, vix and `phoenixframework/tailwind` (pass `max_header_size` for GitHub downloads).

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

**Result Tasks 4 + 5 (2026-10-23), branch `nix-dev-shell` (stacked on `align-toolchain-versions`):**
- `flake.nix` (aarch64-darwin + x86_64-linux), `flake.lock` pinned to nixpkgs `5adc5083`, `.envrc` (`source_env_if_exists .envrc.local` then `use flake`), `.gitignore` (`.direnv/`, `.envrc.local`).
- Shell provides: Elixir 1.19.6 / OTP 28.5.0.8, Node 22.23.3, Python 3.13.16 + uv 0.13.1 (`UV_PYTHON` points at it, `UV_PYTHON_DOWNLOADS=never`), Typst 0.15.1, Postgres 17.11, libvips 8.18.7 via pkg-config, tesseract + ghostscript (import-producer's ocrmypdf), Tailwind 4.1.12 fetched by URL + hash and exposed as `MIX_TAILWIND_PATH` (`config :tailwind, path: System.get_env("MIX_TAILWIND_PATH")` in config.exs; nil → package default, as in Docker). `VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`.
- `scripts/dev-db start|stop|status` + `make db-start/db-stop/db-status`. TCP only (`unix_socket_directories=''`) — the in-`$PGDATA` socket idea broke on macOS's 103-byte socket path limit with a longer data path. Refuses outside the dev shell, on a taken port (before initdb), and on a different-major data dir. initdb: trust auth, UTF8, en_US.UTF-8.
- Verified (scratch data dir): failure cases; start/idempotent start/status/stop; vix compiles from source against Nix libvips on macOS; `mix compile --warnings-as-errors`; `make test-db`; **`mix precommit` passes in the shell against Nix PG 17 (1932 tests, 0 failures)**; `mix assets.deploy` uses the pinned Tailwind; Typst PDF tests pass.
- **Switchover done (2026-10-23):** `direnv allow` + Claude Code restart → plain Bash commands get the dev shell (Nix `elixir` 1.19.6/OTP 28.5.0.8, all env vars) in the main session **and in subagents** (verified with a test subagent — answers the undocumented question). `make db-start` initialized `~/.local/share/gallformers/postgres-17`; `make download-db` (6845 species) and `make wcvp-restore` (1,441,152 names) landed on the Nix PG 17.11 at 54317 (checked with `inet_server_port()`). `make test-db` + `mix precommit` pass with plain commands (1932 tests, 0 failures). Postgres.app left untouched.

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

**Status (2026-10-23):**
- PR A = branch `align-toolchain-versions`, commit `3ca4500b` (Task 3). Not pushed.
- PR B = branch `nix-dev-shell` (stacked on PR A), commit `e0dc7d5e` (Tasks 4–8). Not pushed. Rebase onto main after PR A merges, or open it against `align-toolchain-versions`.
- Task 6: ci.yml Phoenix + Assets jobs and deploy.yml smoke test run via `shell: 'nix develop -c bash -e {0}'` after `cachix/install-nix-action@v31` and a separate "Build dev shell" step (pattern from the action's README). Phoenix job sets `GALLFORMERS_PG_HOST=localhost`, `GALLFORMERS_PG_PORT=5432` for the service container. Cache key now includes `hashFiles('flake.lock')` (first run is cold — that run exercises the vix/Tailwind no-download path). Paths filters include flake.nix/lock, Dockerfiles, scripts/**. No Nix store cache; measure the first runs before adding one.
- Task 7: `scripts/check-toolchain` (CI step in Phoenix job): Dockerfile + Dockerfile.preview Elixir/OTP vs shell, runtime Alpine = builder Alpine, Typst vs shell, Tailwind URL vs config.exs, flake.nix tailwindVersion vs config.exs. Tested against drifted copies (`CHECK_TOOLCHAIN_ROOT`) — caught all planted mismatches, and caught a bug in its own config.exs parsing (read esbuild's version) which was fixed.
- Task 8: README Quick Start/Prerequisites/Database rewritten for Nix + direnv (+ Claude Code hook note).
- Found after the switchover: on macOS the shell's `DEVELOPER_DIR` (Nix Apple SDK) breaks `/usr/bin/git` (xcrun stub → "tool 'git' not found"). Fixed by adding `pkgs.git` to the shell (Nix git ships git-credential-osxkeychain, matching Jeff's `credential.helper`). The `FileChanged` hook reloaded the session env on the flake edit without a restart. But anything launched from a direnv-loaded terminal before the fix (e.g. Claude Code itself, whose statusline runs `git` with Claude Code's own process env) keeps the broken `/usr/bin/git` until restarted from a reloaded shell — the ccstatusline branch display went blank until Jeff restarted Claude Code.
- Verified: `nix flake check`, x86_64-linux shell evaluates, actionlint + shellcheck clean, `mix precommit` (1932 tests, 0 failures) with plain commands.
- Still to watch: first CI run on the PR (cold cache, Linux shell build, timings).

**Shipped (2026-10-23):** PR #595 merged as merge commit `4cf631ed` (contains `3ca4500b` Dockerfiles, `e0dc7d5e` Nix dev shell/CI, `80add8d0` .dockerignore build context 583 MB → ~5 MB). CI on the PR: cold-cache run green (vix compiled from source, Tailwind from the flake, check-toolchain ok, 1932 tests), warm run green. Both Dockerfiles built on Fly's Depot builder via `--build-only` against `gallformers-preview` (note: `--dockerfile` is ignored when the fly.toml has `[build] dockerfile`; use `fly deploy --build-only -a gallformers-preview` for the prod Dockerfile). Prod deploy + smoke test green; `/health` 200; Jeff confirmed admin image upload (vix/libvips) and key PDF (Typst 0.15.1) work. Prod, CI and dev now all run Elixir 1.19.6 / OTP 28.5.0.8.

**Follow-ups (not in this matter):** preview has no `DATABASE_URL` (machine crash-loops at migrations; see `f465`); upstream issues for vix / elixir_make / phoenixframework/tailwind to pass `max_header_size` on GitHub downloads; recurring `Postgrex … client exited` log line in passing test runs; Future steps 2–3 above (Nix-built image, NixOS hosting) and the parked DB-first idea.

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
