{ pkgs, src }:
pkgs.applyPatches {
  name = "namigator-with-wmo-groups";
  inherit src;
  patches = [ ./patches/namigator-wmo-groups.patch ];
}
