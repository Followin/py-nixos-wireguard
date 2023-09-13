{ config, pkgs, lib, ... }:

let
  serverOpts =
    {
      options = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Name of the WireGuard server.";
        };
        ip = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "IP address of the WireGuard server.";
        };
        publicKey = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Public key of the WireGuard server.";
        };
      };
    };
in
{
  options.py.wireguard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable WireGuard.
      '';
    };
    privateKeyFilePath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/systemd/network/wireguard/key";
      description = ''
        Path to the WireGuard private key file.
      '';
    };
    mainDeviceName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "wlp0";
      description = ''
        Name of the main wan device.
      '';
    };
    servers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule serverOpts);
      default = [ ];
      description = ''
        List of WireGuard servers.
      '';
    };
  };

  config = lib.mkIf config.py.wireguard.enable {
    system.activationScripts.ensureWireguardKeysExist.text =
      let
        privateKey = config.py.wireguard.privateKeyFilePath;
        publicKey = config.py.wireguard.privateKeyFilePath + ".pub";
      in
      ''
        #!/usr/bin/env bash

        # if file not exists, generate a new private key
        echo "something" > /tmp/ensureWireguardKeysExist.log

        if [ ! -f ${privateKey} ]; 
        then
          mkdir -p $(dirname ${privateKey})
          ${pkgs.wireguard-tools}/bin/wg genkey > ${privateKey}
          chown root:systemd-network ${privateKey}
          chmod 640 ${privateKey}

          # generate public key
          ${pkgs.wireguard-tools}/bin/wg pubkey < ${privateKey} > ${publicKey}
        fi
      '';

    systemd.network = {
      netdevs =
        let
          buildNetDevs = builtins.foldl'
            (netdevs: wgConf:
              netdevs // {
                "10-${wgConf.name}" = {
                  netdevConfig = {
                    Kind = "wireguard";
                    Name = "wg-${wgConf.name}";
                    MTUBytes = "1420";
                  };

                  wireguardConfig = {
                    PrivateKeyFile = config.py.wireguard.privateKeyFilePath;
                    ListenPort = 9918;
                  };

                  wireguardPeers = [{
                    wireguardPeerConfig = {
                      PublicKey = wgConf.publicKey;
                      AllowedIPs = [ "10.100.0.1" "0.0.0.0/0" ];
                      Endpoint = "${wgConf.ip}:51820";
                    };
                  }];
                };
              })
            { };
        in
        buildNetDevs config.py.wireguard.servers;

      networks = builtins.foldl'
        (networks: wgConf:
          networks // {
            "10-${wgConf.name}" = {
              matchConfig.Name = "wg-${wgConf.name}";
              # IP addresses the client interface will have
              address = [
                "10.100.0.2/24"
              ];
              DHCP = "no";
              routes = [
                {
                  routeConfig = {
                    Gateway = "10.100.0.1";
                    Metric = 1;
                  };
                }
              ];
              linkConfig = {
                ActivationPolicy = "down";
              };
              dns = [ "10.100.0.1" ];
              networkConfig = {
                IPv6AcceptRA = false;
                DNSDefaultRoute = true;
                DNSSEC = false;
                Domains = [ "~." ];
              };
            };
          })
        {
          ${config.py.wireguard.mainDeviceName} = {
            routes = map
              (wgConf: {
                routeConfig = {
                  Gateway = "_dhcp4";
                  Destination = wgConf.ip;
                };
              })
              config.py.wireguard.servers;
          };
        }
        config.py.wireguard.servers;
    };
  };
}
