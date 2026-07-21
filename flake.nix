{
  description = "A semigraphical graphics library in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zig.url = "github:silversquirl/zig-flake";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib legacyPackages;
      eachSystem =
        f: lib.mapAttrs (system: pkgs: f pkgs inputs.zig.packages.${system}.nightly) legacyPackages;
    in
    {
      devShells = eachSystem (
        pkgs: zig: {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.bash
              zig
              zig.zls
            ];
          };
        }
      );
    };
}
