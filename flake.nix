{
  description = "Helium - privacy-focused Chromium-based browser";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          helium-browser = pkgs.callPackage ./package.nix { withGpu = false; };
          helium-browser-gpu = pkgs.callPackage ./package.nix { };
          default = pkgs.callPackage ./package.nix { withGpu = false; };
        }
      );

      overlays.default = final: prev: {
        helium-browser = final.callPackage ./package.nix { };
      };
    };
}
