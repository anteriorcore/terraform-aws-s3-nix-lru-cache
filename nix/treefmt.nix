{ ... }: {
  perSystem.treefmt = {
    projectRootFile = "flake.nix";
    programs = {
      # keep-sorted start block=true
      keep-sorted.enable = true;
      nixfmt = {
        enable = true;
        strict = true;
      };
      ruff-check.enable = true;
      ruff-format.enable = true;
      terraform.enable = true;
      # keep-sorted end
    };
  };
}
