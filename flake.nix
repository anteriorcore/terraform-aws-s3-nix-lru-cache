{
  inputs = {
    # keep-sorted start block=true
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Heavily inspired by
    # https://web.archive.org/web/20250717121109/https://pyproject-nix.github.io/uv2nix/usage/hello-world.html
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };

  outputs =
    { self, flake-parts, ... }@inputs:
    let
      allSystems = {
        perSystem =
          { pkgs, inputs', ... }:
          let
            py = pkgs.callPackage ./py/package.nix {
              inherit (inputs) pyproject-build-systems pyproject-nix uv2nix;
              python = pkgs.python313;
            };
          in
          {
            checks = py.s3-nix-lru-cache.tests;
            packages = {
              inherit (inputs'.tools.packages) conventional-commit nix-flake-check-changed nix-grep-to-build;
              inherit (py) s3-nix-lru-cache lambda-zip;
              next-semver = pkgs.callPackage ./next-semver.nix { };
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
