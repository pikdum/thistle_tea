{
  description = "thistle_tea build derivations: wow-tools + db generators";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    mangoszero-server = {
      # github: fetcher uses GitHub's tarball API which omits submodules; use
      # git+https so submodules (notably src/tools/Extractor_projects) come along.
      url = "git+https://github.com/mangoszero/server.git?submodules=1";
      flake = false;
    };

    wow-dbc-src = {
      url = "github:pikdum/wow_dbc";
      flake = false;
    };

    mangoszero-database = {
      # Realm/ is a submodule (mangos/Realm_DB) so use git+https.
      url = "git+https://github.com/mangoszero/database.git?submodules=1";
      flake = false;
    };

    mysql2sqlite-src = {
      url = "github:vdechef/mysql2sqlite";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      mangoszero-server,
      wow-dbc-src,
      mangoszero-database,
      mysql2sqlite-src,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          mangos-map-extractor = pkgs.stdenv.mkDerivation {
            pname = "mangos-map-extractor";
            version = "mangoszero-${builtins.substring 0 7 mangoszero-server.rev}";
            src = mangoszero-server;

            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
            ];
            buildInputs = with pkgs; [
              openssl
              bzip2
              libmysqlclient
              ace
              zlib
            ];

            cmakeFlags = [
              "-DBUILD_TOOLS=1"
              "-DBUILD_MANGOSD=0"
              "-DBUILD_REALMD=0"
              "-DSOAP=0"
              "-DSCRIPT_LIB_ELUNA=0"
              "-DSCRIPT_LIB_SD3=0"
              "-DPLAYERBOTS=0"
              "-DUSE_STORMLIB=0"
            ];

            # mangos install layout: ${prefix}/bin/tools/{map-extractor,vmap-extractor,...}
            # Hoist them into $out/bin so they're on PATH.
            postInstall = ''
              if [ -d "$out/bin/tools" ]; then
                mv "$out/bin/tools/"* "$out/bin/"
                rmdir "$out/bin/tools"
              fi
            '';

            meta = with pkgs.lib; {
              description = "Vanilla WoW map/DBC/vmap extractors from mangoszero/server";
              platforms = platforms.linux;
              license = licenses.gpl2Only;
            };
          };

          wow-dbc-converter = pkgs.rustPlatform.buildRustPackage {
            pname = "wow-dbc-converter";
            version = "gtker-${builtins.substring 0 7 wow-dbc-src.rev}";
            src = wow-dbc-src;

            cargoLock = {
              lockFile = "${wow-dbc-src}/Cargo.lock";
            };

            # The workspace has multiple crates; we only need the converter binary.
            cargoBuildFlags = [
              "--bin"
              "wow_dbc_converter"
            ];

            doCheck = false;

            meta = with pkgs.lib; {
              description = "Convert WoW client DBC files to sqlite (gtker/wow_dbc)";
              platforms = platforms.unix;
              mainProgram = "wow_dbc_converter";
            };
          };

          # The Rustler NIF that lib/native/namigator.ex loads. Built separately
          # so the mix release doesn't need cargo + network in its sandbox; the
          # .so is dropped into priv/native/ before `mix release` runs and the
          # `use Rustler` macro is patched to `skip_compilation?: true`.
          #
          # The project's root Cargo.toml is a workspace ({ members = ["native/namigator_ex"] })
          # so we have to feed the build the workspace root, not just the crate
          # dir — otherwise cargo can't see the workspace Cargo.lock. We scope
          # the source tightly with fileset so unrelated edits don't bust the
          # cache.
          thistle-tea-nif = pkgs.rustPlatform.buildRustPackage {
            pname = "thistle-tea-nif";
            version = "0.1.0";
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./native/namigator_ex
              ];
            };

            cargoLock.lockFile = ./Cargo.lock;

            cargoBuildFlags = [
              "-p"
              "namigator_ex"
            ];

            doCheck = false;
            # cdylib, not a bin — buildRustPackage's default cargo install won't
            # do the right thing. We also drop the `lib` prefix to match what
            # Rustler expects when it loads via `crate: "namigator_ex"`
            # (default load path is priv/native/<crate>.so, no lib prefix).
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib"
              cp target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/libnamigator_ex.so "$out/lib/namigator_ex.so"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Rustler NIF for ThistleTea (namigator pathfinding bindings)";
              platforms = platforms.linux;
            };
          };

          # The JS deps (just `ol` directly, ~18MB transitive). Asset bundling
          # itself is done inside the mixRelease — esbuild's `import "phoenix"`
          # / `"phoenix_live_view"` resolution depends on the Elixir deps/ dir
          # being present (NODE_PATH=../deps), so we can't pre-bundle here.
          thistle-tea-node-modules = pkgs.buildNpmPackage {
            pname = "thistle-tea-node-modules";
            version = "0.1.0";
            src = ./assets;
            # Bump via `prefetch-npm-deps assets/package-lock.json`.
            npmDepsHash = "sha256-gmFzwKg+2a/KQmhvP6/u7GME5+CGAVgm/KNO0HV4jDU=";
            dontNpmBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -r node_modules "$out/node_modules"
              runHook postInstall
            '';

            meta.description = "thistle_tea JS dep closure (assets/node_modules/)";
          };

          mysql2sqlite = pkgs.stdenv.mkDerivation {
            pname = "mysql2sqlite";
            version = "0-${builtins.substring 0 7 mysql2sqlite-src.rev}";
            src = mysql2sqlite-src;
            dontBuild = true;
            installPhase = ''
              install -Dm755 mysql2sqlite "$out/bin/mysql2sqlite"
            '';
            meta.description = "AWK script that converts a mysql dump into a sqlite-importable file";
          };

          # `nix run .#dbc-db -- <WOW_DIR> [OUT_DIR]` — composes the two wow-tools
          # to produce dbc.sqlite. Kept as a runner (not a derivation) because the
          # WoW client install lives outside /nix/store and we don't want to slurp
          # 5GB+ of MPQs in just to bake a sqlite.
          dbc-db = pkgs.writeShellApplication {
            name = "dbc-db";
            runtimeInputs = [
              mangos-map-extractor
              wow-dbc-converter
              pkgs.coreutils
            ];
            text = ''
              wow_dir=''${1:-''${WOW_DIR:-}}
              out_dir=''${2:-./db}
              if [ -z "''${wow_dir}" ]; then
                echo "usage: dbc-db <WOW_DIR> [OUT_DIR]  (or set WOW_DIR env)" >&2
                exit 1
              fi
              if [ ! -d "''${wow_dir}" ]; then
                echo "dbc-db: WOW_DIR not a directory: ''${wow_dir}" >&2
                exit 1
              fi
              mkdir -p "''${out_dir}"
              out_dir=$(realpath "''${out_dir}")

              tmp=$(mktemp -d)
              trap 'rm -rf "$tmp"' EXIT
              # map-extractor reads MPQs under the cwd "input/" layout; we mirror
              # the existing scripts/generate-dbc-db.sh behaviour.
              ln -s "''${wow_dir}"/* "''${tmp}/"
              mkdir -p "''${tmp}/out"

              echo "Extracting DBCs from: ''${wow_dir}"
              (cd "''${tmp}" && map-extractor -i . -o ./out -e 2)

              echo "Converting DBCs -> sqlite..."
              rm -f "''${out_dir}/dbc.sqlite" "''${out_dir}/dbc.sqlite-shm" "''${out_dir}/dbc.sqlite-wal"
              wow_dbc_converter vanilla -i "''${tmp}/out/dbc" -o "''${out_dir}/dbc.sqlite"

              echo "Generated ''${out_dir}/dbc.sqlite"
            '';
          };

          mangos0-db = pkgs.stdenv.mkDerivation {
            pname = "mangos0-db";
            version = "mangoszero-${builtins.substring 0 7 mangoszero-database.rev}";

            src = mangoszero-database;

            nativeBuildInputs = with pkgs; [
              mariadb
              sqlite
              gawk
              mysql2sqlite
              coreutils
            ];

            # The mangoszero installer is interactive (./InstallDatabases.sh prompts
            # for host/user/port/pass/db-names). We replicate its non-interactive
            # path here: load the three Setup .sql bundles plus all Rel21/Rel22
            # updates into a unix-socket mariadb, then dump mangos0 to sqlite.
            buildPhase = ''
              runHook preBuild

              export TMPDIR=$(mktemp -d)
              export MYSQL_HOME="$TMPDIR"
              datadir="$TMPDIR/mysql"
              socket="$TMPDIR/mysql.sock"

              mkdir -p "$datadir"
              mariadb-install-db --auth-root-authentication-method=normal \
                --datadir="$datadir" --user="$(id -u)" >/dev/null

              mariadbd \
                --datadir="$datadir" \
                --socket="$socket" \
                --skip-networking \
                --pid-file="$TMPDIR/mariadb.pid" &
              MYSQL_PID=$!
              trap 'kill $MYSQL_PID 2>/dev/null || true' EXIT

              # wait for server to come up
              for i in $(seq 1 60); do
                if mariadb -u root --socket="$socket" -e "SELECT 1" >/dev/null 2>&1; then
                  break
                fi
                sleep 1
              done

              # Skip the mangosdCreateDB.sql / characterCreateDB.sql / realmdCreateDB.sql
              # files — they only CREATE DATABASE + GRANT to a 'mangos'@'%' user we
              # don't need. We do the CREATE DATABASEs ourselves and connect as root.
              mariadb -u root --socket="$socket" -e "
                CREATE DATABASE mangos0   CHARACTER SET utf8 COLLATE utf8_general_ci;
                CREATE DATABASE character0 CHARACTER SET utf8 COLLATE utf8_general_ci;
                CREATE DATABASE realmd    CHARACTER SET utf8 COLLATE utf8_general_ci;
              "

              load () {
                local db=$1 path=$2
                if [ ! -e "$path" ]; then return; fi
                echo "  $path -> $db"
                mariadb -u root --socket="$socket" "$db" <"$path"
              }

              load_dir () {
                local db=$1 dir=$2
                if [ ! -d "$dir" ]; then return; fi
                find "$dir" -maxdepth 1 -name '*.sql' | sort | while read -r f; do
                  load "$db" "$f"
                done
              }

              echo "Loading mangos0 (world)..."
              load mangos0 World/Setup/mangosdLoadDB.sql
              load_dir mangos0 World/Setup/FullDB/Rel21
              load_dir mangos0 World/Setup/FullDB
              load_dir mangos0 World/Updates/Rel21
              load_dir mangos0 World/Updates/Rel22

              echo "Loading character0..."
              load character0 Character/Setup/characterLoadDB.sql
              load_dir character0 Character/Updates/Rel21
              load_dir character0 Character/Updates/Rel22

              echo "Loading realmd..."
              load realmd Realm/Setup/realmdLoadDB.sql
              load_dir realmd Realm/Updates/Rel21
              load_dir realmd Realm/Updates/Rel22
              load realmd Tools/updateRealm.sql

              echo "Dumping mangos0 -> sqlite..."
              mariadb-dump -u root --socket="$socket" --skip-extended-insert --compact mangos0 >"$TMPDIR/dump.sql"
              mysql2sqlite "$TMPDIR/dump.sql" | sqlite3 "$TMPDIR/mangos0.sqlite"

              kill $MYSQL_PID 2>/dev/null || true
              wait $MYSQL_PID 2>/dev/null || true

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp "$TMPDIR/mangos0.sqlite" "$out/mangos0.sqlite"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "mangoszero world+characters+realmd databases, rolled into a sqlite file";
              platforms = platforms.linux;
            };
          };

          beam = pkgs.beam.packagesWith pkgs.erlang;

          # evision (used by lib/web/utils/homography.ex) downloads a precompiled
          # NIF tarball during `mix compile`. The build sandbox has no network,
          # so we fetch it as a FOD and drop it into ELIXIR_MAKE_CACHE_DIR so
          # evision's downloader finds it cached.
          # Bump version + sha256 in lockstep with the :evision hex pin.
          evision-precompiled-tarball = pkgs.fetchurl {
            url = "https://github.com/cocoa-xu/evision/releases/download/v0.2.15/evision-nif_2.16-x86_64-linux-gnu-contrib-0.2.15.tar.gz";
            hash = "sha256-j2kZYKTi2ASJDRIo9N8EcnltM3YlFyjRc5QvhCPqAfk=";
          };

          # The mix release. Composes the pre-built NIF + pre-built assets so
          # the build sandbox doesn't need cargo or npm/esbuild/tailwind.
          thistle-tea = beam.mixRelease {
            pname = "thistle_tea";
            version = "0.1.0";
            src = ./.;
            removeCookie = false;

            # Hex/git deps as a single fixed-output derivation. To refresh after
            # changing mix.lock: set this to an empty/wrong hash, run the build,
            # and copy the "got:" hash from the error.
            mixFodDeps = beam.fetchMixDeps {
              pname = "mix-deps-thistle-tea";
              version = "0.1.0";
              src = ./.;
              hash = "sha256-5biusF/eL1FYrCOwOhoh+h6IztPDqG4tEN6BVv37CLU=";
            };

            nativeBuildInputs = [
              pkgs.esbuild
              pkgs.tailwindcss_3
            ];

            # 1. Drop the prebuilt NIF where `use Rustler` expects it.
            # 2. Inject `skip_compilation?: true` so mix compile doesn't shell out
            #    to cargo (the build sandbox has no network).
            # 3. Pull in the vendored node_modules so esbuild can resolve `ol/*`.
            postPatch = ''
              mkdir -p priv/native
              cp ${thistle-tea-nif}/lib/namigator_ex.so priv/native/

              sed -i \
                's|use Rustler, otp_app: :thistle_tea, crate: "namigator_ex"|use Rustler, otp_app: :thistle_tea, crate: "namigator_ex", skip_compilation?: true|' \
                lib/native/namigator.ex

              cp -r ${thistle-tea-node-modules}/node_modules assets/node_modules
            '';

            # evision's downloader checks $ELIXIR_MAKE_CACHE_DIR first; if the
            # tarball is already there it skips network. Build sandbox $HOME is
            # /homeless-shelter (deps try to mkdir in there), so redirect both.
            ELIXIR_MAKE_CACHE_DIR = "/build/elixir-make-cache";

            # mixRelease's configurePhase runs `mix deps.compile` (which triggers
            # evision's downloader), so the cache has to be seeded BEFORE that —
            # preBuild runs too late.
            preConfigure = ''
              export HOME=$TMPDIR
              mkdir -p "$ELIXIR_MAKE_CACHE_DIR"
              cp ${evision-precompiled-tarball} "$ELIXIR_MAKE_CACHE_DIR/evision-nif_2.16-x86_64-linux-gnu-contrib-0.2.15.tar.gz"
            '';

            # Run esbuild + tailwind directly (skipping the mix esbuild/tailwind
            # tasks, which would try to download their own binaries). Args mirror
            # config/config.exs plus --minify from the assets.deploy alias.
            #
            # Note: we deliberately skip `mix phx.digest`. It triggers Mix's git
            # lock check, which fails because fetchMixDeps strips git objects
            # from /nix/store deps. The release still serves assets correctly,
            # it just lacks the cache_manifest.json fingerprinting. If/when we
            # need cache busting we can either re-fetch git deps with their
            # objects intact or run phx.digest as a post-install step.
            preBuild = ''
              mkdir -p priv/static/assets
              (cd assets && NODE_PATH="../deps" esbuild \
                js/app.js \
                --bundle \
                --target=es2017 \
                --outdir=../priv/static/assets \
                --external:/fonts/* \
                --external:/images/* \
                --minify)
              (cd assets && tailwindcss \
                --config=tailwind.config.js \
                --input=css/app.css \
                --output=../priv/static/assets/app.css \
                --minify)
            '';

            meta = with pkgs.lib; {
              description = "thistle_tea WoW 1.12 server (mix release)";
              platforms = platforms.linux;
              mainProgram = "thistle_tea";
            };
          };
        in
        {
          inherit
            mangos-map-extractor
            wow-dbc-converter
            mysql2sqlite
            mangos0-db
            dbc-db
            thistle-tea-nif
            thistle-tea-node-modules
            thistle-tea
            ;
          default = thistle-tea;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          inherit (self.packages.${system}) mangos0-db;
          mangos0-db-runner = pkgs.writeShellApplication {
            name = "mangos0-db";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              out_dir=''${1:-./db}
              mkdir -p "''${out_dir}"
              out_dir=$(realpath "''${out_dir}")
              rm -f "''${out_dir}/mangos0.sqlite" \
                    "''${out_dir}/mangos0.sqlite-shm" \
                    "''${out_dir}/mangos0.sqlite-wal"
              install -m 644 ${mangos0-db}/mangos0.sqlite "''${out_dir}/mangos0.sqlite"
              echo "Generated ''${out_dir}/mangos0.sqlite"
            '';
          };
        in
        {
          dbc-db = {
            type = "app";
            program = "${self.packages.${system}.dbc-db}/bin/dbc-db";
          };
          mangos0-db = {
            type = "app";
            program = "${mangos0-db-runner}/bin/mangos0-db";
          };
          thistle-tea = {
            type = "app";
            program = "${self.packages.${system}.thistle-tea}/bin/thistle_tea";
          };
          default = {
            type = "app";
            program = "${self.packages.${system}.thistle-tea}/bin/thistle_tea";
          };
        }
      );

      # Convenience: a dev shell with all the tools on PATH for ad-hoc use.
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          wow-tools = pkgs.mkShell {
            packages = [
              self.packages.${system}.mangos-map-extractor
              self.packages.${system}.wow-dbc-converter
              self.packages.${system}.mysql2sqlite
              pkgs.sqlite
              pkgs.mariadb
            ];
          };
        }
      );
    };
}
