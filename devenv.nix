{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  # https://devenv.sh/packages/
  packages = [
    pkgs.git
    pkgs.bun
    pkgs.inotify-tools
  ];

  # https://devenv.sh/languages/
  languages.rust.enable = true;
  languages.elixir.enable = true;
  languages.erlang.enable = true;

  # https://devenv.sh/git-hooks/
  git-hooks.hooks = {
    nixfmt.enable = true;
    mix-format.enable = true;
  };

  # See full reference at https://devenv.sh/reference/options/
}
