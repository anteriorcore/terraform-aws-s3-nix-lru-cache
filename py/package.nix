# mostly taken from
# https://github.com/anteriorcore/brrr/blob/9e111e70ecb454acc5b6cad810add204f6babfec/python/package.nix
{
  # keep-sorted start
  callPackage,
  coreutils,
  findutils,
  lib,
  pyproject-build-systems,
  pyproject-nix,
  python,
  runCommand,
  stdenvNoCC,
  uv,
  uv2nix,
  writableTmpDirAsHomeHook,
  zip,
  # keep-sorted end
}:
# taking some shortcuts here (mostly around devshells and overlays) since the
# point of this is to bundle the python lambda code into a deployable zip
let
  uvWorkspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  uvOverlay = uvWorkspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  pythonSet = (callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.default
      uvOverlay
      # https://pyproject-nix.github.io/uv2nix/patterns/testing.html
      (final: prev: {
        s3-nix-lru-cache = prev.s3-nix-lru-cache.overrideAttrs (old: {
          passthru = old.passthru or { } // {
            tests = {
              mypy = stdenvNoCC.mkDerivation {
                inherit (old) src;
                nativeBuildInputs = [ dev ];
                dontConfigure = true;
                name = "mypy";
                buildPhase = ''
                  runHook preBuild
                  mypy .
                  runHook postBuild
                '';
                installPhase = ''
                  runHook preInstall
                  touch $out
                  runHook postInstall
                '';
              };
              uvlock = stdenvNoCC.mkDerivation {
                name = "uv-lock-synced";
                # https://github.com/astral-sh/uv/issues/8635#issuecomment-2759670742
                env = {
                  UV_NO_MANAGED_PYTHON = "true";
                  UV_SYSTEM_PYTHON = "true";
                };
                src =
                  with lib.fileset;
                  toSource {
                    root = ./.;
                    fileset = unions [
                      ./pyproject.toml
                      ./uv.lock
                    ];
                  };
                nativeBuildInputs = [
                  uv
                  python
                  writableTmpDirAsHomeHook
                ];
                buildPhase = ''
                  uv lock --locked
                '';
                installPhase = ''
                  touch $out
                '';
              };
            }
            // (old.passthru.tests or { });
          };
        });
      })
    ]
  );
  release = pythonSet.mkVirtualEnv "brrr-env" uvWorkspace.deps.default;
  dev = pythonSet.mkVirtualEnv "dev-env" uvWorkspace.deps.all;
in
{
  s3-nix-lru-cache = pythonSet.s3-nix-lru-cache;
  inherit release dev;
  lambda-zip =
    # Note that this will create the package.zip for the platform you run it
    # on.  It may or not work on a target platform in AWS Lambda.  If you are
    # running this yourself, we recommend doing so on the same architecture as
    # the lambda you plan to deploy.
    runCommand "s3-nix-lru-cache-lambda"
      {
        nativeBuildInputs = [
          zip
          coreutils
          findutils
        ];
      }
      # Somehow this is the way to make it deployable as a lambda.
      # https://docs.astral.sh/uv/guides/integration/aws-lambda/#deploying-a-zip-archive
      # And make it somewhat reproducible.
      # https://clickhouse.com/blog/zip-archive-aws-lambda
      ''
        cp -RL ${release}/lib/python3.1*/site-packages ./
        cp ${./main.py} ./main.py

        # https://docs.aws.amazon.com/lambda/latest/dg/python-package.html#python-package-create-update
        chmod -R u+w ./site-packages
        chmod -R u+w ./main.py

        # zip does not support timestamps before 1980.
        # February to disambiguate zip's -X from this.
        find ./site-packages -exec touch -t 198002010000 {} +
        touch -t 198002010000 main.py

        (
        cd ./site-packages/ && \
        export LC_ALL="C" && \
        find . ! -type d | sort -z |
        zip -x "*__pycache__*" -x "*dist-info/*" -XD -9 ../package.zip --names-stdin
        )
        zip -X -9 ./package.zip main.py

        mkdir $out
        cp ./package.zip $out/package.zip
      '';

}
