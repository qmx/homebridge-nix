# Homebridge Nix Flake

A Nix flake providing Homebridge and related plugins for NixOS systems.

## Overview

Homebridge is a Node.js server that emulates the iOS HomeKit API, allowing integration of non-HomeKit smart home devices with Apple's Home app and ecosystem.

This flake provides:
- A deterministic Nix package for Homebridge
- Homebridge plugins (starting with homebridge-camera-ffmpeg)
- A NixOS/nix-darwin service module for declarative configuration
- Cross-platform support: Linux (NixOS) and macOS (nix-darwin)

## Architecture Decisions

### No Web UI
Unlike the official Debian and Docker packages, this implementation runs Homebridge directly without homebridge-config-ui-x. This provides:
- Simpler, more minimal package
- Purely declarative configuration via Nix
- No additional web server overhead
- Better security (no web interface to secure)

### Declarative Configuration
All configuration is managed through NixOS module options, generating `config.json` at service activation. This aligns with the Nix philosophy of reproducible, declarative system configuration.

### Platform-Specific mDNS

**Linux (NixOS):**
Uses Avahi daemon for mDNS/Bonjour advertisement, matching the Debian and Docker approach. Homebridge communicates with Avahi via D-Bus - no special capabilities required. The service module automatically enables and configures Avahi.

**macOS:**
Uses Ciao, a pure Node.js/TypeScript mDNS implementation recommended by Homebridge for non-Linux platforms. No system dependencies required - works out of the box. Alternatively, the native Bonjour-HAP advertiser can be used.

### Declarative Plugin Management
Plugins are built as separate Nix packages and declared in the NixOS configuration, ensuring reproducible plugin installations.

## Research Findings

### Analysis of Existing Packages

#### Debian Package (homebridge-apt-pkg)
**Key insights:**
- Installs Node.js runtime to `/opt/homebridge/`
- User data directory: `/var/lib/homebridge/`
- Runs as `homebridge` system user
- Uses systemd with capabilities: `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_ADMIN`
- Actually runs homebridge-config-ui-x as service wrapper
- Environment variables control npm behavior (no package-lock, global style, etc.)
- On Raspberry Pi, user added to hardware groups: audio, bluetooth, gpio, etc.

#### Docker Package (docker-homebridge)
**Key insights:**
- Based on Ubuntu 24.04
- Uses s6-overlay for service management
- Runs as root in container (for hardware access)
- Host networking required for mDNS to work properly
- Includes Avahi daemon and D-Bus in container
- Bundles FFmpeg for camera support
- Volume mount at `/homebridge` for persistence

### Homebridge Core Requirements

**Node.js Version:**
- Minimum: 18.15.0
- Recommended: 22.x (current stable)
- Maximum tested: 24.x

**System Dependencies:**
- `openssl` - TLS/crypto operations
- `avahi` - mDNS/DNS-SD (when using Avahi advertiser)
- `dbus` - D-Bus daemon (for Avahi communication)
- `gcc`, `g++`, `make`, `python3` - Build native modules

**Network Ports:**
- Default bridge port: 51826 (configurable)
- Child bridge range: 52100-52150 (configurable)
- Web UI port: 8581 (not applicable to this implementation)

**Storage Layout:**
```
/var/lib/homebridge/
├── config.json                 # Main configuration
├── accessories/                # Cached accessories
│   └── cachedAccessories       # Binary cache file
└── persist/                    # HAP-NodeJS persistence data
    ├── AccessoryInfo.*.json    # Accessory pairing info
    └── IdentifierCache.*.json  # UUID cache
```

**Configuration Structure:**
```json
{
  "bridge": {
    "name": "Homebridge",
    "username": "CC:22:3D:E3:CE:30",  // Unique MAC address format
    "manufacturer": "homebridge.io",
    "model": "homebridge",
    "port": 51826,
    "pin": "031-45-154"                // HomeKit pairing code (XXX-XX-XXX)
  },
  "accessories": [],                   // Accessory plugins
  "platforms": []                      // Platform plugins
}
```

**mDNS Advertiser Options:**
- `bonjour` - Bonjour HAP (legacy, works everywhere but less efficient)
- `ciao` - Pure Node.js/TypeScript implementation (recommended for macOS, platform-independent)
- `avahi` - Uses D-Bus to communicate with avahi-daemon (recommended for Linux)
- `resolved` - systemd-resolved (Linux only, experimental)

**Platform Defaults (This Flake):**
- **Linux/NixOS**: `avahi` (with automatic Avahi service configuration)
- **macOS/Darwin**: `ciao` (no system dependencies required)

### Plugin Architecture

**Discovery:**
- Plugins must match pattern: `homebridge-*` or `@scope/homebridge-*`
- Loaded via Node.js require() from node_modules
- Can be scoped to specific path with `--plugin-path` flag

**Types:**
- Accessory Plugins: Single devices
- Platform Plugins: Multiple devices from one source
- Dynamic Platforms: Modern API
- Static Platforms: Legacy API

## Implementation Approach

### Package Building with buildNpmPackage

All Node.js packages (Homebridge and plugins) are built using Nix's `buildNpmPackage`:

```nix
buildNpmPackage {
  pname = "homebridge";
  version = "...";

  src = fetchFromGitHub { ... };

  npmDepsHash = "sha256-...";  # Deterministic hash of all npm dependencies

  nativeBuildInputs = [ python3 ];  # For node-gyp
  buildInputs = [ ... ];             # Runtime dependencies
}
```

This approach:
- Fetches all npm dependencies deterministically
- Builds native modules during Nix build
- Creates a reproducible closure
- No runtime npm or internet access needed

### NixOS Module Design

**Core Options:**
```nix
services.homebridge = {
  enable = true;

  config = {
    bridge = {
      name = "My Homebridge";
      username = "CC:22:3D:E3:CE:30";
      port = 51826;
      pin = "031-45-154";
    };
    platforms = [ ... ];
    accessories = [ ... ];
  };

  plugins = with pkgs; [
    homebridge-camera-ffmpeg
  ];
};
```

**Service Implementation:**
- Simple systemd service (Type=simple)
- No capabilities required (use non-privileged ports)
- Auto-enables Avahi service
- Generates config.json from Nix options
- Sets NODE_PATH for plugin resolution

**Avahi Integration:**
Automatically enables and configures Avahi:
```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;  # Enable mDNS resolution
  publish = {
    enable = true;
    addresses = true;
    domain = true;
  };
};
```

### Why No Capabilities Needed (Linux)

The Debian package uses Linux capabilities to allow the homebridge user to:
1. Bind to privileged ports (<1024) - `CAP_NET_BIND_SERVICE`
2. Use raw sockets - `CAP_NET_RAW`
3. Perform network admin tasks - `CAP_NET_ADMIN`

In our Nix implementation on Linux:
- **Ports**: Configure Homebridge to use ports >1024 (no privilege needed)
- **mDNS**: Avahi daemon handles mDNS with its own permissions
- **Communication**: Homebridge talks to Avahi via D-Bus (user-level IPC)

This is more secure and simpler than granting capabilities.

On macOS, capabilities don't apply - the Ciao advertiser runs entirely in user-space without any special permissions.

## Platform Support

This flake supports the following systems:
- `x86_64-linux` - Intel/AMD 64-bit Linux (NixOS)
- `aarch64-linux` - ARM 64-bit Linux (NixOS on Raspberry Pi, etc.)
- `x86_64-darwin` - Intel Mac
- `aarch64-darwin` - Apple Silicon Mac (M1/M2/M3)

The service module automatically detects the platform and configures the appropriate mDNS advertiser and system services.

## Usage Examples

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
          services.homebridge = {
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

          services.homebridge = {
            enable = true;

            config = {
              bridge = {
                name = "Mac Homebridge";
                username = "BB:CC:DD:EE:FF:00";
                port = 51826;
                pin = "987-65-432";
                # advertiser is automatically set to "ciao" on macOS
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

**Notes for macOS:**
- Uses `ciao` advertiser by default (no system dependencies)
- No Avahi service required
- Works with both Intel and Apple Silicon Macs
- Firewall configuration must be done through macOS System Settings
- The service runs via launchd instead of systemd

## Included Plugins

### homebridge-camera-ffmpeg

Allows integration of IP cameras via FFmpeg. Supports:
- RTSP/HTTP/HTTPS camera streams
- Snapshot serving
- Two-way audio
- Motion detection
- Doorbell automation

**Runtime Dependencies:**
- FFmpeg (automatically included)

## File Structure

```
homebridge-nix/
├── README.md              # This file
├── flake.nix             # Main flake definition
├── package.nix           # Homebridge package
├── camera-ffmpeg.nix     # homebridge-camera-ffmpeg plugin
└── module.nix            # NixOS service module
```

## Development

### Building Packages

```bash
# Build homebridge
nix build .#homebridge

# Build camera-ffmpeg plugin
nix build .#homebridge-camera-ffmpeg
```

### Testing the Module

```bash
# Build a test NixOS configuration
nix build .#nixosConfigurations.test.config.system.build.toplevel
```

## License

This Nix packaging follows the licenses of the upstream projects:
- Homebridge: Apache-2.0
- homebridge-camera-ffmpeg: Apache-2.0

## References

- [Homebridge Official Repo](https://github.com/homebridge/homebridge)
- [Homebridge Debian Package](https://github.com/homebridge/homebridge-apt-pkg)
- [Homebridge Docker](https://github.com/homebridge/docker-homebridge)
- [homebridge-camera-ffmpeg](https://github.com/homebridge-plugins/homebridge-camera-ffmpeg)
