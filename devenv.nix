{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  env.MIX_OS_DEPS_COMPILE_PARTITION_COUNT = 4;
  env.NAMIGATOR_SRC = inputs.namigator.outPath;

  # https://devenv.sh/packages/
  packages = [
    pkgs.docker
    pkgs.git
    pkgs.bun
    pkgs.inotify-tools
    pkgs.just
    pkgs.rsync
  ];

  # https://devenv.sh/languages/
  languages.rust.enable = true;
  languages.elixir = {
    enable = true;
    package = pkgs.beam29Packages.elixir_1_20;
  };
  languages.nix.enable = true;

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    nixfmt.enable = true;
    mix-format.enable = true;
    credo = {
      enable = true;
      entry = "mix credo --strict";
      pass_filenames = false;
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
