{
  description = "Homebridge - HomeKit support for the impatient";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in
    {
      # Overlay for adding homebridge packages to nixpkgs
      overlays.default = final: prev: {
        homebridge = final.callPackage ./package.nix { };
        homebridge-camera-ffmpeg = final.callPackage ./camera-ffmpeg.nix { };
      };

      # Packages for each supported system
      packages = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          homebridge = pkgs.homebridge;
          homebridge-camera-ffmpeg = pkgs.homebridge-camera-ffmpeg;
          default = pkgs.homebridge;
        }
      );

      # home-manager module
      homeManagerModules.default = import ./module.nix;
    };
}
