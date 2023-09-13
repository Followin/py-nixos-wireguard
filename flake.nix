{
  outputs = { ... }: {
    nixosModules.default = import ./py-wireguard.nix;
  };
}
