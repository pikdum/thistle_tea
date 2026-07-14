{
  lib,
  beamPackages,
  cmake,
  extend,
  lexbor,
  fetchFromGitHub,
  oniguruma,
  overrides ? (x: y: { }),
  overrideFenixOverlay ? null,
  rustlerPrecompiledOverrides ? { },
  pkg-config,
  vips,
  writeText,
}:

let
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;

  workarounds = {
    portCompiler = _unusedArgs: old: {
      buildPlugins = [ beamPackages.pc ];
    };

    rustlerPrecompiled =
      {
        toolchain ? null,
        buildInputs ? [ ],
        nativeBuildInputs ? [ ],
        env ? { },
        ...
      }:
      old:
      let
        extendedPkgs = extend fenixOverlay;
        fenixOverlay =
          if overrideFenixOverlay == null then
            import "${
              fetchTarball {
                url = "https://github.com/nix-community/fenix/archive/6399553b7a300c77e7f07342904eb696a5b6bf9d.tar.gz";
                sha256 = "sha256-C6tT7K1Lx6VsYw1BY5S3OavtapUvEnDQtmQB5DSgbCc=";
              }
            }/overlay.nix"
          else
            overrideFenixOverlay;
        nativeDir = "${old.src}/native/${with builtins; head (attrNames (readDir "${old.src}/native"))}";
        fenix =
          if toolchain == null then
            extendedPkgs.fenix.stable
          else
            extendedPkgs.fenix.fromToolchainName toolchain;
        native =
          (
            (extendedPkgs.makeRustPlatform {
              inherit (fenix) cargo rustc;
            }).buildRustPackage
            {
              inherit env buildInputs;
              pname = "${old.beamModuleName}-native";
              version = old.version;
              src = nativeDir;
              cargoLock = {
                lockFile = "${nativeDir}/Cargo.lock";
              };
              nativeBuildInputs = [ extendedPkgs.cmake ] ++ nativeBuildInputs;
              doCheck = false;
            }
          ).overrideAttrs
            rustlerPrecompiledOverrides.${old.beamModuleName} or { };

      in
      {
        nativeBuildInputs = [ extendedPkgs.cargo ];

        env.RUSTLER_PRECOMPILED_FORCE_BUILD_ALL = "true";
        env.RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH = "unused-but-required";

        preConfigure = ''
          mkdir -p priv/native
          for lib in ${native}/lib/*
          do
            dest="$(basename "$lib")"
            if [[ "''${dest##*.}" = "dylib" ]]
            then
              dest="''${dest%.dylib}.so"
            fi
            ln -s "$lib" "priv/native/$dest"
          done
        '';

        preBuild = ''
          suggestion() {
            echo "***********************************************"
            echo "                 deps_nix                      "
            echo
            echo " Rust dependency build failed.                 "
            echo
            echo " If you saw network errors, you might need     "
            echo " to disable compilation on the appropriate     "
            echo " RustlerPrecompiled module in your             "
            echo " application config.                           "
            echo
            echo " We think you need this:                       "
            echo
            echo -n " "
            grep -Rl 'use RustlerPrecompiled' lib \
              | xargs grep 'defmodule' \
              | sed 's/defmodule \(.*\) do/config :${old.beamModuleName}, \1, skip_compilation?: true/'
            echo "***********************************************"
            exit 1
          }
          trap suggestion ERR
        '';
      };

    elixirMake = _unusedArgs: old: {
      preConfigure = ''
        export ELIXIR_MAKE_CACHE_DIR="$TEMPDIR/elixir_make_cache"
      '';
    };

    lazyHtml = _unusedArgs: old: {
      preConfigure = ''
        export ELIXIR_MAKE_CACHE_DIR="$TEMPDIR/elixir_make_cache"
      '';

      postPatch = ''
        substituteInPlace mix.exs \
          --replace-fail "Fine.include_dir()" '"${packages.fine}/src/c_include"' \
          --replace-fail '@lexbor_git_sha "244b84956a6dc7eec293781d051354f351274c46"' '@lexbor_git_sha ""'
      '';

      preBuild = ''
        install -Dm644           -t _build/c/third_party/lexbor/$LEXBOR_GIT_SHA/build           ${lexbor}/lib/liblexbor_static.a
      '';
    };
  };

  defaultOverrides = (
    final: prev:

    let
      apps = {
        crc32cer = [
          {
            name = "portCompiler";
          }
        ];
        explorer = [
          {
            name = "rustlerPrecompiled";
            toolchain = {
              name = "nightly-2025-06-23";
              sha256 = "sha256-UAoZcxg3iWtS+2n8TFNfANFt/GmkuOMDf7QAE0fRxeA=";
            };
          }
        ];
        snappyer = [
          {
            name = "portCompiler";
          }
        ];
      };

      applyOverrides =
        appName: drv:
        let
          allOverridesForApp = builtins.foldl' (
            acc: workaround: acc // (workarounds.${workaround.name} workaround) drv
          ) { } apps.${appName};

        in
        if builtins.hasAttr appName apps then drv.override allOverridesForApp else drv;

    in
    builtins.mapAttrs applyOverrides prev
  );

  self = packages // (defaultOverrides self packages) // (overrides self packages);

  packages =
    with beamPackages;
    with self;
    {

      bandit =
        let
          version = "1.12.0";
          drv = buildMix {
            inherit version;
            name = "bandit";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "bandit";
              sha256 = "45dac82dc86f45cf4a196dee9cc5a8b791d9c9469d996055f055e6ee36c66e20";
            };

            beamDeps = [
              hpax
              plug
              telemetry
              thousand_island
              websock
            ];
          };
        in
        drv;

      binary =
        let
          version = "0.0.5";
          drv = buildMix {
            inherit version;
            name = "binary";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "binary";
              sha256 = "ee1e9ebcab703a4e24db554957fbb540642fe9327eb9e295cb3f07dd7c11ddb2";
            };
          };
        in
        drv;

      bitmap =
        let
          version = "1.0.1";
          drv = buildMix {
            inherit version;
            name = "bitmap";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "bitmap";
              sha256 = "341a29908d005b2414ecd214623733caccf9d65c94a50911046d89a365c9805f";
            };
          };
        in
        drv;

      cc_precompiler =
        let
          version = "0.1.11";
          drv = buildMix {
            inherit version;
            name = "cc_precompiler";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "cc_precompiler";
              sha256 = "3427232caf0835f94680e5bcf082408a70b48ad68a5f5c0b02a3bea9f3a075b9";
            };

            beamDeps = [
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      db_connection =
        let
          version = "2.10.2";
          drv = buildMix {
            inherit version;
            name = "db_connection";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "db_connection";
              sha256 = "510b14482330f1af6490a2fa0efd8d4f1435d1529b165647df22ac0f2df0fa93";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      decimal =
        let
          version = "3.1.1";
          drv = buildMix {
            inherit version;
            name = "decimal";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "decimal";
              sha256 = "c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6";
            };
          };
        in
        drv;

      ecto =
        let
          version = "3.14.1";
          drv = buildMix {
            inherit version;
            name = "ecto";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "ecto";
              sha256 = "24b991956796700f467d0a3ef3d303138a3ef9ddddf8b98f43758ee067b20a30";
            };

            beamDeps = [
              decimal
              jason
              telemetry
            ];
          };
        in
        drv;

      ecto_sql =
        let
          version = "3.14.0";
          drv = buildMix {
            inherit version;
            name = "ecto_sql";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "ecto_sql";
              sha256 = "f4d8d36faf294c9417b5a37ec7ac8217ee2abdef5fcf197ba690f361548d3949";
            };

            beamDeps = [
              db_connection
              decimal
              ecto
              telemetry
            ];
          };
        in
        drv;

      ecto_sqlite3 =
        let
          version = "0.24.1";
          drv = buildMix {
            inherit version;
            name = "ecto_sqlite3";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "ecto_sqlite3";
              sha256 = "681ca576c74a94944b962eeb7e0cf19aaea517decafd3213afb403ac8f4cd2e3";
            };

            beamDeps = [
              decimal
              ecto
              ecto_sql
              exqlite
            ];
          };
        in
        drv;

      elixir_make =
        let
          version = "0.10.0";
          drv = buildMix {
            inherit version;
            name = "elixir_make";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "elixir_make";
              sha256 = "dc1f09fb7fa68866b886abd5f0f3c83553b1a19a52359a899e92af1bb3b31982";
            };
          };
        in
        drv;

      esbuild =
        let
          version = "0.10.0";
          drv = buildMix {
            inherit version;
            name = "esbuild";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "esbuild";
              sha256 = "468489cda427b974a7cc9f03ace55368a83e1a7be12fba7e30969af78e5f8c70";
            };

            beamDeps = [
              jason
            ];
          };
        in
        drv;

      exqlite =
        let
          version = "0.38.0";
          drv = buildMix {
            inherit version;
            name = "exqlite";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "exqlite";
              sha256 = "f3da7b6e7b08bd548c33a118890d0eb8c5395fe093b31c8b329663234d0e988e";
            };

            beamDeps = [
              cc_precompiler
              db_connection
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      fine =
        let
          version = "0.1.6";
          drv = buildMix {
            inherit version;
            name = "fine";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "fine";
              sha256 = "5638eb4495488e885ebec167fa57973e5c35e1a50c344eb7666c90ec1c4e3b12";
            };
          };
        in
        drv;

      group =
        let
          version = "0.2.0";
          drv = buildMix {
            inherit version;
            name = "group";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "group";
              sha256 = "a58c2fb99165cd5b10756a7a51f0162d18e5e6d75b64b3253c004d2937e73d78";
            };
          };
        in
        drv;

      hpax =
        let
          version = "1.0.4";
          drv = buildMix {
            inherit version;
            name = "hpax";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "hpax";
              sha256 = "afc7cb142ebcc2d01ce7816190b98ce5dd49e799111b24249f3443d730f377ca";
            };
          };
        in
        drv;

      jason =
        let
          version = "1.4.5";
          drv = buildMix {
            inherit version;
            name = "jason";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "jason";
              sha256 = "b0c823996102bcd0239b3c2444eb00409b72f6a140c1950bc8b457d836b30684";
            };

            beamDeps = [
              decimal
            ];
          };
        in
        drv;

      mime =
        let
          version = "2.0.7";
          drv = buildMix {
            inherit version;
            name = "mime";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "mime";
              sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
            };
          };
        in
        drv;

      phoenix =
        let
          version = "1.8.9";
          drv = buildMix {
            inherit version;
            name = "phoenix";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix";
              sha256 = "3477e2dd5a4f61820341169031bdfe21275f659923bea9c5c0ea2aa1c3fcc046";
            };

            beamDeps = [
              bandit
              jason
              phoenix_pubsub
              phoenix_template
              plug
              plug_crypto
              telemetry
              websock_adapter
            ];
          };
        in
        drv;

      phoenix_html =
        let
          version = "4.3.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_html";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix_html";
              sha256 = "3eaa290a78bab0f075f791a46a981bbe769d94bc776869f4f3063a14f30497ad";
            };
          };
        in
        drv;

      phoenix_live_dashboard =
        let
          version = "0.8.7";
          drv = buildMix {
            inherit version;
            name = "phoenix_live_dashboard";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix_live_dashboard";
              sha256 = "3a8625cab39ec261d48a13b7468dc619c0ede099601b084e343968309bd4d7d7";
            };

            beamDeps = [
              ecto
              mime
              phoenix_live_view
              telemetry_metrics
            ];
          };
        in
        drv;

      phoenix_live_view =
        let
          version = "1.2.7";
          drv = buildMix {
            inherit version;
            name = "phoenix_live_view";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix_live_view";
              sha256 = "61e97938a4fcca6d6f2c836925623abf2f52a572cc8c6085e4074f3f6337e0eb";
            };

            beamDeps = [
              jason
              phoenix
              phoenix_html
              phoenix_template
              plug
              telemetry
            ];
          };
        in
        drv;

      phoenix_pubsub =
        let
          version = "2.2.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_pubsub";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix_pubsub";
              sha256 = "adc313a5bf7136039f63cfd9668fde73bba0765e0614cba80c06ac9460ff3e96";
            };
          };
        in
        drv;

      phoenix_template =
        let
          version = "1.0.4";
          drv = buildMix {
            inherit version;
            name = "phoenix_template";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "phoenix_template";
              sha256 = "2c0c81f0e5c6753faf5cca2f229c9709919aba34fab866d3bc05060c9c444206";
            };

            beamDeps = [
              phoenix_html
            ];
          };
        in
        drv;

      plug =
        let
          version = "1.20.3";
          drv = buildMix {
            inherit version;
            name = "plug";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "plug";
              sha256 = "be266aee1b8536ef6409d58cf39a3121319f0ec47cfa1b24024485aa0e76ad76";
            };

            beamDeps = [
              mime
              plug_crypto
              telemetry
            ];
          };
        in
        drv;

      plug_crypto =
        let
          version = "2.1.1";
          drv = buildMix {
            inherit version;
            name = "plug_crypto";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "plug_crypto";
              sha256 = "6470bce6ffe41c8bd497612ffde1a7e4af67f36a15eea5f921af71cf3e11247c";
            };
          };
        in
        drv;

      tailwind =
        let
          version = "0.5.1";
          drv = buildMix {
            inherit version;
            name = "tailwind";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "tailwind";
              sha256 = "c4e26302a59fec72abc5610ecb6ad2116d9aa31f31aab2d4b8eb6e95d25a689c";
            };
          };
        in
        drv;

      telemetry =
        let
          version = "1.4.2";
          drv = buildRebar3 {
            inherit version;
            name = "telemetry";

            src = fetchHex {
              inherit version;
              pkg = "telemetry";
              sha256 = "928f6495066506077862c0d1646609eed891a4326bee3126ba54b60af61febb1";
            };
          };
        in
        drv;

      telemetry_metrics =
        let
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "telemetry_metrics";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "telemetry_metrics";
              sha256 = "e7b79e8ddfde70adb6db8a6623d1778ec66401f366e9a8f5dd0955c56bc8ce67";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      telemetry_poller =
        let
          version = "1.3.0";
          drv = buildRebar3 {
            inherit version;
            name = "telemetry_poller";

            src = fetchHex {
              inherit version;
              pkg = "telemetry_poller";
              sha256 = "51f18bed7128544a50f75897db9974436ea9bfba560420b646af27a9a9b35211";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      thousand_island =
        let
          version = "1.5.0";
          drv = buildMix {
            inherit version;
            name = "thousand_island";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "thousand_island";
              sha256 = "708923d40523e43cf99041ab37a0d4b0ec426ac6438fa3716ab23d919eaeb412";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      websock =
        let
          version = "0.5.3";
          drv = buildMix {
            inherit version;
            name = "websock";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "websock";
              sha256 = "6105453d7fac22c712ad66fab1d45abdf049868f253cf719b625151460b8b453";
            };
          };
        in
        drv;

      websock_adapter =
        let
          version = "0.6.0";
          drv = buildMix {
            inherit version;
            name = "websock_adapter";
            appConfigPath = ./config;

            src = fetchHex {
              inherit version;
              pkg = "websock_adapter";
              sha256 = "50021a85bce8f203b086705d9e0c5415e2c7eb05d319111b0428fe71f9934617";
            };

            beamDeps = [
              bandit
              plug
              websock
            ];
          };
        in
        drv;

    };
in
self
