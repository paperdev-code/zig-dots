{
  description = "A semigraphical graphics library in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    zig.url = "github:silversquirl/zig-flake";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;
      systems = import inputs.systems;
    in
    {
      devShells = lib.genAttrs systems (system: {
        default = inputs.zig.devShells.${system}.default;
      });
    };
}
