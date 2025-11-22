# homebridge-nix

Nix flake for Homebridge with declarative configuration for NixOS and nix-darwin.

## Features

- Homebridge packages built with Nix
- Declarative `config.json` via NixOS module
- Cross-platform: Linux (NixOS) and macOS (nix-darwin)
- Platform-specific mDNS (Avahi on Linux, native Bonjour on macOS)
- Included plugin: homebridge-camera-ffmpeg

## Usage

### NixOS (Linux)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    homebridge.url = "github:qmx/homebridge-nix";
  };

  outputs = { self, nixpkgs, homebridge }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        homebridge.nixosModules.default
        {
          services.homebridgeNix = {
            enable = true;

            config = {
              bridge = {
                name = "Home Bridge";
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
                      name = "Front Door";
                      videoConfig = {
                        source = "-i rtsp://camera.local/stream";
                        maxWidth = 1280;
                        maxHeight = 720;
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
        }
      ];
    };
  };
}
```

### macOS (nix-darwin)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin.url = "github:LnL7/nix-darwin";
    homebridge.url = "github:qmx/homebridge-nix";
  };

  outputs = { self, nixpkgs, darwin, homebridge }: {
    darwinConfigurations.my-mac = darwin.lib.darwinSystem {
      system = "aarch64-darwin";  # or "x86_64-darwin" for Intel
      modules = [
        homebridge.nixosModules.default  # Works with nix-darwin too!
        {
          # Import the overlay to make packages available
          nixpkgs.overlays = [ homebridge.overlays.default ];

          services.homebridgeNix = {
            enable = true;

            config = {
              bridge = {
                name = "Mac Homebridge";
                username = "BB:CC:DD:EE:FF:00";
                port = 51826;
                pin = "987-65-432";
              };

              platforms = [
                {
                  platform = "Camera-ffmpeg";
                  name = "Camera FFmpeg";
                  cameras = [
                    {
                      name = "Backyard Camera";
                      videoConfig = {
                        source = "-i rtsp://camera.local/stream";
                        maxWidth = 1920;
                        maxHeight = 1080;
                      };
                    }
                  ];
                }
              ];
            };

            plugins = with pkgs; [
              homebridge-camera-ffmpeg
            ];

            # Note: openFirewall doesn't apply on macOS
            # You may need to configure macOS firewall separately
          };
        }
      ];
    };
  };
}
```


## Available Plugins

- `homebridge-camera-ffmpeg` - FFmpeg-based IP camera support

## Building

```bash
nix build .#homebridge
nix build .#homebridge-camera-ffmpeg
nix flake check
```

## Supported Systems

- `x86_64-linux`, `aarch64-linux`
- `x86_64-darwin`, `aarch64-darwin`
