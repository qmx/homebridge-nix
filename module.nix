{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.homebridge;

  # Detect if we're on Linux or macOS
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;

  # Platform-specific default advertiser
  defaultAdvertiser = if isLinux then "avahi" else "ciao";

  # Generate the config.json file from Nix options
  configFile = pkgs.writeText "config.json" (builtins.toJSON cfg.config);

  # Create a package that includes homebridge and all plugins
  homebridgeWithPlugins = if cfg.plugins == [] then
    cfg.package
  else
    pkgs.buildEnv {
      name = "homebridge-with-plugins";
      paths = [ cfg.package ] ++ cfg.plugins;
      pathsToLink = [ "/lib/node_modules" ];
    };

in
{
  options.services.homebridge = {
    enable = mkEnableOption "Homebridge HomeKit support server";

    package = mkOption {
      type = types.package;
      default = pkgs.homebridge;
      defaultText = literalExpression "pkgs.homebridge";
      description = "The homebridge package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "homebridge";
      description = "User account under which homebridge runs.";
    };

    group = mkOption {
      type = types.str;
      default = "homebridge";
      description = "Group under which homebridge runs.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/homebridge";
      description = "The directory where homebridge stores its data.";
    };

    config = mkOption {
      type = types.attrs;
      default = {
        bridge = {
          name = "Homebridge";
          username = "CC:22:3D:E3:CE:30";
          port = 51826;
          pin = "031-45-154";
          advertiser = "avahi";
        };
        accessories = [];
        platforms = [];
      };
      example = literalExpression ''
        {
          bridge = {
            name = "My Homebridge";
            username = "AA:BB:CC:DD:EE:FF";
            port = 51826;
            pin = "123-45-678";
            advertiser = "avahi";
          };
          platforms = [
            {
              platform = "Camera-ffmpeg";
              name = "Camera FFmpeg";
              cameras = [ ];
            }
          ];
        }
      '';
      description = ''
        Configuration for homebridge. This will be converted to JSON and
        written to config.json in the data directory.

        See https://github.com/homebridge/homebridge/wiki/Configuration
        for available options.
      '';
    };

    plugins = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExpression "[ pkgs.homebridge-camera-ffmpeg ]";
      description = ''
        List of homebridge plugin packages to install.
        These will be made available to homebridge via NODE_PATH.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to automatically open the firewall for homebridge.
        This will open the bridge port and the child bridge port range.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Set platform-appropriate default advertiser
    services.homebridge.config.bridge.advertiser = mkDefault defaultAdvertiser;

    # Create the homebridge user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "Homebridge daemon user";
    };

    users.groups.${cfg.group} = {};

    # Enable and configure Avahi for mDNS (Linux only)
    services.avahi = mkIf isLinux {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        workstation = true;
      };
    };

    # Open firewall ports if requested (Linux only, macOS uses different firewall)
    networking.firewall = mkIf (cfg.openFirewall && isLinux) {
      allowedTCPPorts = [
        cfg.config.bridge.port
      ] ++ (optionals (cfg.config ? ports) [
        # Open child bridge port range if configured
      ]);
    };

    # Create the systemd service
    systemd.services.homebridge = {
      description = "Homebridge - HomeKit support for the impatient";
      after = [ "network-online.target" ] ++ optional isLinux "avahi-daemon.service";
      wants = [ "network-online.target" ];
      requires = optional isLinux "avahi-daemon.service";
      wantedBy = [ "multi-user.target" ];

      # Set up the data directory and config file before starting
      preStart = ''
        # Ensure data directory exists and has correct permissions
        mkdir -p ${cfg.dataDir}
        chown ${cfg.user}:${cfg.group} ${cfg.dataDir}
        chmod 750 ${cfg.dataDir}

        # Copy config.json to data directory
        cp ${configFile} ${cfg.dataDir}/config.json
        chown ${cfg.user}:${cfg.group} ${cfg.dataDir}/config.json
        chmod 640 ${cfg.dataDir}/config.json

        # Create subdirectories for homebridge data
        mkdir -p ${cfg.dataDir}/persist
        mkdir -p ${cfg.dataDir}/accessories
        chown -R ${cfg.user}:${cfg.group} ${cfg.dataDir}/persist ${cfg.dataDir}/accessories
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;

        # Set up environment for homebridge
        Environment = [
          "HOME=${cfg.dataDir}"
          "NODE_PATH=${homebridgeWithPlugins}/lib/node_modules"
        ];

        # Command to run homebridge
        ExecStart = "${homebridgeWithPlugins}/bin/homebridge -U ${cfg.dataDir}";

        # Restart policy
        Restart = "always";
        RestartSec = 3;
        KillMode = "process";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        NoNewPrivileges = true;

        # Resource limits
        LimitNOFILE = 4096;
      };
    };

    # Add a helper command to manage homebridge
    environment.systemPackages = [ cfg.package ];
  };
}
