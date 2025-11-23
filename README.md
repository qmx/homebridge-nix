# homebridge-nix

Nix flake for Homebridge with declarative home-manager configuration.

## Features

- Homebridge packages built with Nix
- Declarative configuration via home-manager
- Runs as user service (no root needed)
- Linux only (uses systemd user services)
- Included plugin: homebridge-camera-ffmpeg

## Installation

Add to your home-manager flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    homebridge.url = "github:qmx/homebridge-nix";
  };

  outputs = { nixpkgs, home-manager, homebridge, ... }: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        homebridge.homeManagerModules.default
        {
          nixpkgs.overlays = [ homebridge.overlays.default ];

          services.homebridgeNix = {
            enable = true;

            config = {
              bridge = {
                name = "My Homebridge";
                username = "AA:BB:CC:DD:EE:FF";
                port = 51826;
                pin = "123-45-678";
              };

              platforms = [
                {
                  platform = "Camera-ffmpeg";
                  cameras = [
                    {
                      name = "Front Door";
                      videoConfig.source = "-i rtsp://camera.local/stream";
                    }
                  ];
                }
              ];
            };

            plugins = with pkgs; [ homebridge-camera-ffmpeg ];
          };
        }
      ];
    };
  };
}
```

## Usage

After installation, enable and start the service:

```bash
systemctl --user enable --now homebridgeNix
systemctl --user status homebridgeNix
```

Configuration is stored in `~/.local/share/homebridge/`.


## Available Plugins

- `homebridge-camera-ffmpeg` - FFmpeg-based IP camera support

## Building

```bash
nix build .#homebridge
nix build .#homebridge-camera-ffmpeg
nix flake check
```

## Supported Systems

**home-manager module (Linux only):**
- `x86_64-linux`, `aarch64-linux`

**Packages (build on any system):**
- `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`
