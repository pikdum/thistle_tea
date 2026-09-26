{ pkgs, src }:
pkgs.applyPatches {
  name = "namigator-with-wmo-metadata";
  inherit src;
  patches = [
    ./patches/namigator-wmo-groups.patch
    ./patches/namigator-wmo-liquids.patch
  ];
}
