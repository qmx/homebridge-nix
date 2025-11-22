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

      # NixOS module
      nixosModules.default = import ./module.nix;

      # Example NixOS configurations for Linux systems
      nixosConfigurations = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.default
            ({ pkgs, ... }: {
              nixpkgs.overlays = [ self.overlays.default ];

              services.homebridgeNix = {
                enable = true;

                config = {
                  bridge = {
                    name = "Example Homebridge";
                    username = "AA:BB:CC:DD:EE:FF";
                    port = 51826;
                    pin = "123-45-678";
                  };

                  platforms = [
                    {
                      platform = "Camera-ffmpeg";
                      name = "Camera FFmpeg";
                      cameras = [
                        {
                          name = "Example Camera";
                          videoConfig = {
                            source = "-i rtsp://camera.example.com/stream";
                            maxWidth = 1280;
                            maxHeight = 720;
                            maxFPS = 30;
                          };
                        }
                      ];
                    }
                  ];
                };

                plugins = with pkgs; [
                  homebridge-camera-ffmpeg
                ];

                openFirewall = true;
              };
            })
          ];
        }
      );
    };
}
