{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  env.MIX_OS_DEPS_COMPILE_PARTITION_COUNT = 4;

  # https://devenv.sh/packages/
  packages = [
    pkgs.docker
    pkgs.git
    pkgs.bun
    pkgs.inotify-tools
  ];

  # https://devenv.sh/languages/
  languages.rust.enable = true;
  languages.elixir = {
    enable = true;
    package = pkgs.elixir_1_19;
  };
  languages.nix.enable = true;

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    nixfmt.enable = true;
    mix-format.enable = true;
  };

  # See full reference at https://devenv.sh/reference/options/
}
