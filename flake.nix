{
  inputs = {
    # keep-sorted start block=true
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    systems.url = "systems";
    tools = {
      url = "github:anteriorcore/tools";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };

  outputs =
    { self, flake-parts, ... }@inputs:
    let
      allSystems = {
        perSystem =
          {
            pkgs,
            lib,
            inputs',
            ...
          }:
          {
            packages = {
              inherit (inputs'.tools.packages) conventional-commit nix-flake-check-changed nix-grep-to-build;
            };
          };
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = builtins.filter (s: s != "x86_64-darwin") (import inputs.systems);
      imports = [
        # keep-sorted start
        ./nix/treefmt.nix
        allSystems
        inputs.tools.flakeModules.checkBuildAll
        inputs.treefmt-nix.flakeModule
        # keep-sorted end
      ];
    };
}
