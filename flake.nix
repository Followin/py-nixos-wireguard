{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { ... }: {
    nixosModules.default = import ./py-wireguard.nix;
  };
}
