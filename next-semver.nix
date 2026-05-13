{ writeShellApplication, semver }:
writeShellApplication {
  name = "next-semver";
  runtimeInputs = [ semver ];
  text = ''
    # use system git
    git fetch --tags
    semver -i patch
  '';
}
