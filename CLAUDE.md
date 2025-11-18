# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Nix flake that packages Homebridge and plugins for NixOS and nix-darwin systems. The flake provides deterministic builds of Node.js packages and a cross-platform service module with platform-specific mDNS configuration.

## Key Architecture Decisions

### No Web UI
This implementation runs Homebridge directly without homebridge-config-ui-x. All configuration is purely declarative via the NixOS module, generating `config.json` at service activation.

### Platform-Specific mDNS Strategy
- **Linux (NixOS)**: Uses Avahi daemon for mDNS via D-Bus (no capabilities needed)
- **macOS (nix-darwin)**: Uses Ciao, a pure Node.js mDNS implementation (no system dependencies)

The module automatically detects the platform and sets the appropriate default advertiser in `module.nix:12-13`.

### Plugin Architecture
Plugins are built as separate Nix packages and combined with Homebridge using `buildEnv` in `module.nix:19-26`. This creates a unified package with all plugins available via NODE_PATH.

## Build Commands

```bash
# Build homebridge package
nix build .#homebridge

# Build camera-ffmpeg plugin
nix build .#homebridge-camera-ffmpeg

# Build example NixOS configuration
nix build .#nixosConfigurations.example.config.system.build.toplevel

# Check flake
nix flake check

# Update dependencies
nix flake update
```

## Package Structure

### package.nix (Homebridge Core)
- Uses `buildNpmPackage` with `fetchFromGitHub`
- **Critical**: `dontNpmBuild = true` because default build script tries to npm install in sandbox
- Manually runs TypeScript compilation with `npx tsc`
- Requires `nodejs_22`, `python3` (for node-gyp), and `openssl`

### camera-ffmpeg.nix (Plugin Example)
- Uses `buildNpmPackage` with `fetchFromGitHub`
- **Critical**: `npmFlags = [ "--ignore-scripts" ]` prevents ffmpeg-for-homebridge from downloading binaries
- Uses `makeWrapper` to ensure system `ffmpeg` is in PATH
- Template for adding additional Homebridge plugins

### module.nix (Service Module)
Platform detection happens at evaluation time (`pkgs.stdenv.isLinux`/`isDarwin`). The module:
1. Creates `homebridge` system user and group
2. Generates `config.json` from `services.homebridge.config` using `builtins.toJSON`
3. Sets up `NODE_PATH` to include plugin node_modules
4. On Linux: Enables Avahi service and configures for mDNS publishing
5. On macOS: No system services needed (Ciao is embedded)

## Common Development Patterns

### Adding a New Plugin

1. Create `{plugin-name}.nix` using `camera-ffmpeg.nix` as template
2. Add to overlay in `flake.nix:19-22`
3. Add to packages output in `flake.nix:25-31`
4. If plugin has native dependencies or download scripts, use appropriate `npmFlags` and build phase customization

### Updating Package Versions

When updating `version` in package.nix or camera-ffmpeg.nix:
1. Update the `version` field
2. Update the `hash` (use `lib.fakeHash` initially, then replace with error output)
3. Update `npmDepsHash` (use `lib.fakeHash` initially, then replace with error output)
4. Test build to ensure TypeScript compilation and dependencies work

### Module Configuration

The `services.homebridge.config` option is passed directly to `builtins.toJSON`, so it must be valid Nix attrs that serialize to valid Homebridge config.json structure. See README.md lines 232-283 for full examples.

## Important Constraints

### Security Model
No Linux capabilities are used. Ports must be >1024 (default 51826). mDNS is handled by system daemons (Avahi) or userspace libraries (Ciao), not raw sockets.

### Node.js Version
Currently pinned to `nodejs_22`. Homebridge supports Node 18.15.0+ through 24.x, but plugins may have narrower ranges.

### Cross-Platform Compatibility
All code in module.nix must work on both Linux and Darwin. Use `mkIf isLinux` or `mkIf isDarwin` for platform-specific configuration (see lines 134-152).

## Supported Systems

- `x86_64-linux` - NixOS on Intel/AMD
- `aarch64-linux` - NixOS on ARM (Raspberry Pi, etc.)
- `x86_64-darwin` - macOS on Intel
- `aarch64-darwin` - macOS on Apple Silicon

Define in `flake.nix:10` and used throughout via `forAllSystems`.
