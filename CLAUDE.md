# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Nix flake that packages Homebridge and plugins for home-manager. The flake provides deterministic builds of Node.js packages and a home-manager module for declarative configuration.

## Key Architecture Decisions

### home-manager Module
Uses systemd user services (not system services), runs as the user without requiring root privileges. Data stored in `~/.local/share/homebridge/`.

### No Web UI
This implementation runs Homebridge directly without homebridge-config-ui-x. All configuration is purely declarative via the home-manager module, generating `config.json` at service activation.

### Plugin Architecture
Plugins are built as separate Nix packages and combined with Homebridge using `buildEnv` in `module.nix:12-19`. This creates a unified package with all plugins available via NODE_PATH.

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

### module.nix (home-manager Module)
The module:
1. Generates `config.json` from `services.homebridgeNix.config` using `builtins.toJSON`
2. Sets up `NODE_PATH` to include plugin node_modules
3. Creates systemd user service (`systemd.user.services.homebridgeNix`)
4. Uses `~/.local/share/homebridge` as data directory
5. Runs as the user (no root/system services)

Note: Uses `services.homebridgeNix` (not `services.homebridge`) to avoid conflict with upstream nixpkgs module.

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

The `services.homebridgeNix.config` option is passed directly to `builtins.toJSON`, so it must be valid Nix attrs that serialize to valid Homebridge config.json structure. See README.md for full examples.

## Important Constraints

### User Service
Runs as systemd user service (no root). Data in user's home directory. Ports must be >1024 (default 51826 is fine).

### Node.js Version
Currently pinned to `nodejs_22`. Homebridge supports Node 18.15.0+ through 24.x, but plugins may have narrower ranges.

## Supported Systems

**home-manager module (Linux only):**
- `x86_64-linux`, `aarch64-linux`
- Uses systemd user services (not available on macOS)

**Packages (all systems):**
- `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`
- Defined in `flake.nix:10` and used throughout via `forAllSystems`
