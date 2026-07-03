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

    namigator-src = {
      url = "git+https://github.com/pikdum/namigator.git?submodules=1";
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
      namigator-src,
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

          vmangos-db-snapshot = pkgs.fetchurl {
            url = "https://github.com/vmangos/core/releases/download/db_latest/db-sqlite-b40576b.zip";
            hash = "sha256-W7dFk4TRX6piSYemNNrzxTBev31EQoQQHvvaWR/1B4k=";
          };

          # namigator's MapBuilder CLI, built from the pinned fork via CMake.
          # The `maps` runner below drives it to generate navigation meshes.
          # namigator's CMake forces -DDT_POLYREF64 globally (CMakeLists.txt),
          # matching the runtime NIF, so the produced maps load. MapViewer is
          # WIN32-only, so on Linux only the MapBuilder executable is built.
          namigator-mapbuilder = pkgs.stdenv.mkDerivation {
            pname = "namigator-mapbuilder";
            version = "pikdum-${builtins.substring 0 7 namigator-src.rev}";
            src = namigator-src;

            nativeBuildInputs = [ pkgs.cmake ];
            buildInputs = [
              pkgs.zlib
              pkgs.bzip2
            ];

            cmakeFlags = [
              "-DNAMIGATOR_BUILD_PYTHON=OFF"
              "-DNAMIGATOR_INSTALL_TESTS=OFF"
              "-DNAMIGATOR_BUILD_C_API=OFF"
              # the bundled recastnavigation/stormlib submodules still declare
              # cmake_minimum_required < 3.5, which modern CMake rejects.
              "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
            ];

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              cp "$(find . -name MapBuilder -type f -perm -u+x | head -1)" "$out/bin/MapBuilder"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "namigator MapBuilder CLI (navmesh generation from WoW client data)";
              platforms = platforms.linux;
              mainProgram = "MapBuilder";
            };
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

          # `nix run .#maps -- <WOW_DIR> [OUT_DIR]` — generate navigation meshes
          # from the WoW client. A runner (like dbc-db) because the client MPQs
          # live outside /nix/store. Map names must match @maps_to_process in
          # lib/native/namigator.ex.
          maps = pkgs.writeShellApplication {
            name = "maps";
            runtimeInputs = [
              namigator-mapbuilder
              pkgs.coreutils
            ];
            text = ''
              wow_dir=''${1:-''${WOW_DIR:-}}
              out_dir=''${2:-./maps}
              if [ -z "''${wow_dir}" ]; then
                echo "usage: maps <WOW_DIR> [OUT_DIR]  (or set WOW_DIR env)" >&2
                exit 1
              fi
              data_dir="''${wow_dir}/Data"
              if [ ! -d "''${data_dir}" ]; then
                echo "maps: no Data/ under WOW_DIR: ''${wow_dir}" >&2
                exit 1
              fi
              mkdir -p "''${out_dir}"
              out_dir=$(realpath "''${out_dir}")

              threads=''${THREADS:-$(nproc)}

              echo "Building BVH from: ''${data_dir}"
              MapBuilder --data "''${data_dir}" --output "''${out_dir}" --bvh --threads "''${threads}" --logLevel 1

              for map in Azeroth Kalimdor development OrgrimmarInstance Stratholme; do
                echo "Building ''${map}..."
                MapBuilder --data "''${data_dir}" --output "''${out_dir}" --map "''${map}" --threads "''${threads}" --logLevel 1
              done

              echo "Maps written to ''${out_dir}"
            '';
          };

          vmangos-db = pkgs.stdenv.mkDerivation {
            pname = "vmangos-db";
            version = "b40576b";

            src = vmangos-db-snapshot;
            dontUnpack = true;

            nativeBuildInputs = with pkgs; [
              coreutils
              sqlite
              unzip
            ];

            buildPhase = ''
              runHook preBuild

              work=$(mktemp -d)
              unzip -q "$src" -d "$work"
              cp "$work/sqlite-dump/mangos.sqlite" vmangos.sqlite
              chmod u+w vmangos.sqlite

              sqlite_exec () {
                sqlite3 vmangos.sqlite "$1"
              }

              column_exists () {
                local table=$1 column=$2
                sqlite_exec "SELECT COUNT(*) FROM pragma_table_info('$table') WHERE name = '$column';"
              }

              patch_tables=$(sqlite_exec "
                SELECT DISTINCT m.name
                FROM sqlite_master m
                JOIN pragma_table_info(m.name) p
                WHERE m.type = 'table' AND p.name = 'patch'
                ORDER BY m.name;
              ")

              for table in $patch_tables; do
                key_columns=$(sqlite_exec "
                  SELECT group_concat(name, ' ')
                  FROM pragma_table_info('$table')
                  WHERE pk > 0 AND name != 'patch'
                  ORDER BY pk;
                ")

                if [ -z "$key_columns" ]; then
                  sqlite_exec "DELETE FROM \"$table\" WHERE patch > 10;"
                  continue
                fi

                comparisons=
                for column in $key_columns; do
                  if [ -z "$comparisons" ]; then
                    comparisons="newer.\"$column\" = t.\"$column\""
                  else
                    comparisons="$comparisons AND newer.\"$column\" = t.\"$column\""
                  fi
                done

                sqlite_exec "
                  DELETE FROM \"$table\" AS t
                  WHERE t.patch > 10
                     OR EXISTS (
                       SELECT 1
                       FROM \"$table\" AS newer
                       WHERE $comparisons
                         AND newer.patch <= 10
                         AND newer.patch > t.patch
                     );
                "
              done

              range_tables=$(sqlite_exec "
                SELECT DISTINCT m.name
                FROM sqlite_master m
                JOIN pragma_table_info(m.name) p
                WHERE m.type = 'table' AND p.name IN ('patch_min', 'patch_max')
                ORDER BY m.name;
              ")

              for table in $range_tables; do
                has_min=$(column_exists "$table" patch_min)
                has_max=$(column_exists "$table" patch_max)
                clauses=

                if [ "$has_min" = 1 ]; then
                  clauses="patch_min > 10"
                fi

                if [ "$has_max" = 1 ]; then
                  if [ -z "$clauses" ]; then
                    clauses="patch_max < 10"
                  else
                    clauses="$clauses OR patch_max < 10"
                  fi
                fi

                if [ -n "$clauses" ]; then
                  sqlite_exec "DELETE FROM \"$table\" WHERE $clauses;"
                fi
              done

              sqlite3 vmangos.sqlite "VACUUM;"

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp vmangos.sqlite "$out/vmangos.sqlite"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Current vmangos world database snapshot flattened to WoW 1.12 patch data";
              platforms = platforms.unix;
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

          # The mix release. Builds the Fine C++ NIF with elixir_make against
          # namigator-src and composes pre-built assets so the build sandbox
          # doesn't need npm/esbuild/tailwind downloads.
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
              hash = "sha256-in4N+W8xvq4PQkR6xXKyF1/2iUXmUYL7rUGZZo+TV+o=";
            };

            nativeBuildInputs = [
              pkgs.esbuild
              pkgs.gnumake
              pkgs.tailwindcss_3
            ];

            postPatch = ''
              cp -r ${thistle-tea-node-modules}/node_modules assets/node_modules
            '';

            NAMIGATOR_SRC = namigator-src;

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
            vmangos-db
            dbc-db
            namigator-mapbuilder
            maps
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
          inherit (self.packages.${system}) vmangos-db;
          vmangos-db-runner = pkgs.writeShellApplication {
            name = "vmangos-db";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              out_dir=''${1:-./db}
              mkdir -p "''${out_dir}"
              out_dir=$(realpath "''${out_dir}")
              rm -f "''${out_dir}/vmangos.sqlite" \
                    "''${out_dir}/vmangos.sqlite-shm" \
                    "''${out_dir}/vmangos.sqlite-wal"
              install -m 644 ${vmangos-db}/vmangos.sqlite "''${out_dir}/vmangos.sqlite"
              echo "Generated ''${out_dir}/vmangos.sqlite"
            '';
          };
        in
        {
          dbc-db = {
            type = "app";
            program = "${self.packages.${system}.dbc-db}/bin/dbc-db";
          };
          maps = {
            type = "app";
            program = "${self.packages.${system}.maps}/bin/maps";
          };
          vmangos-db = {
            type = "app";
            program = "${vmangos-db-runner}/bin/vmangos-db";
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
