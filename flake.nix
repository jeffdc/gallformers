{
  description = "Gallformers development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      # aarch64-darwin: development Macs. x86_64-linux: GitHub Actions runners.
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Tailwind is pinned to the version in config/config.exs (nixpkgs has a newer one).
      # Same release the Dockerfiles download; keep all three in sync.
      tailwindVersion = "4.1.12";
      tailwindAssets = {
        aarch64-darwin = {
          name = "tailwindcss-macos-arm64";
          hash = "sha256-fWm+F3a76KSeFXFNmHPQiVnDIK/w8HFNjY5tnQDZtUM=";
        };
        x86_64-linux = {
          name = "tailwindcss-linux-x64";
          hash = "sha256-Xu7mbqI36umhYPozFP0M92q5k1Uamfr7Fvodtsa5Aok=";
        };
      };
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          inherit (pkgs) lib stdenv;

          # Elixir/OTP must match the Dockerfile builder image (scripts/check-toolchain).
          beam = pkgs.beam.packages.erlang_28;

          tailwindAsset = tailwindAssets.${stdenv.hostPlatform.system};
          tailwind = pkgs.runCommand "tailwindcss-${tailwindVersion}" { } ''
            install -Dm755 ${
              pkgs.fetchurl {
                url = "https://github.com/tailwindlabs/tailwindcss/releases/download/v${tailwindVersion}/${tailwindAsset.name}";
                inherit (tailwindAsset) hash;
              }
            } $out/bin/tailwindcss
          '';
        in
        {
          default = pkgs.mkShell {
            packages = [
              # On macOS the shell sets DEVELOPER_DIR to Nix's Apple SDK, which breaks
              # /usr/bin/git (an xcrun stub: "tool 'git' not found"). A real git fixes it.
              pkgs.git
              beam.erlang
              beam.elixir_1_19
              pkgs.nodejs_22
              pkgs.typst
              pkgs.pkg-config
              pkgs.postgresql_17
              # Python tooling for services/import-producer and priv/import.
              pkgs.python313
              pkgs.uv
              # ocrmypdf (import-producer) shells out to these.
              pkgs.tesseract
              pkgs.ghostscript
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [ pkgs.inotify-tools ];

            # vix compiles against this libvips through pkg-config.
            buildInputs = [ pkgs.vips ];

            env = {
              # OTP >= 28.5.0.6 httpc rejects GitHub release redirects (headers > 10240
              # bytes), which breaks vix's and tailwind's own binary downloads. Build vix
              # against libvips and hand tailwind a pinned binary instead (matter 9380).
              VIX_COMPILATION_MODE = "PLATFORM_PROVIDED_LIBVIPS";
              MIX_TAILWIND_PATH = "${tailwind}/bin/tailwindcss";

              # uv uses the Python above instead of downloading its own.
              UV_PYTHON = "${pkgs.python313}/bin/python3.13";
              UV_PYTHON_DOWNLOADS = "never";
            };

            # Dev Postgres (scripts/dev-db). Project-specific variables so a PGPORT set
            # elsewhere can't point the app at another server; override them in .envrc.local.
            shellHook = ''
              export GALLFORMERS_PG_PORT="''${GALLFORMERS_PG_PORT:-54317}"
              export GALLFORMERS_PG_HOST="''${GALLFORMERS_PG_HOST:-127.0.0.1}"
              export GALLFORMERS_PG_DATA="''${GALLFORMERS_PG_DATA:-''${XDG_DATA_HOME:-$HOME/.local/share}/gallformers/postgres-17}"
              export PGHOST="$GALLFORMERS_PG_HOST"
              export PGPORT="$GALLFORMERS_PG_PORT"
              export PGDATA="$GALLFORMERS_PG_DATA"
            '';
          };
        }
      );
    };
}
