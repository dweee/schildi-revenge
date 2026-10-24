{
  description = "schildi-revenge fork with standalone Nix packaging";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
    self.submodules = true;
  };
  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in let
          sourcePackage = pkgs.schildi-revenge.overrideAttrs (finalAttrs: _old: {
            # The fork SDK lock can advance independently of the nixpkgs release.
            cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
              inherit (finalAttrs) src cargoRoot;
              # Keep both the current branch and reviewed incoming SDK buildable.
              hash = let
                hashes = builtins.fromJSON (builtins.readFile ./nix/cargo-hashes.json);
                lockHash = builtins.hashFile "sha256" (self + "/matrix-rust-sdk/Cargo.lock");
              in hashes.${lockHash} or nixpkgs.lib.fakeHash;
            };
            # Keep the standalone fork cache current with upstream dependency bumps.
            mitmCache = pkgs.gradle_9.fetchDeps {
              pkg = finalAttrs.finalPackage;
              data = ./deps-linux.json;
            };
            # Workflow and sync-state changes do not alter the application.
            src = nixpkgs.lib.cleanSourceWith {
              src = self;
              filter = path: type:
                let
                  relative = nixpkgs.lib.removePrefix "${self}/" (toString path);
                  top = builtins.head (nixpkgs.lib.splitString "/" relative);
                in nixpkgs.lib.cleanSourceFilter path type
                  && !(builtins.elem top [ ".github" ".forgejo" ".fork-ci" ".fork-ci.json" "ci" ]);
            };
          });
        in if pkgs.stdenv.hostPlatform.isDarwin
          then pkgs.callPackage ./nix/package.nix { schildi-revenge = sourcePackage; }
          else if pkgs.stdenv.hostPlatform.isAarch64
          then pkgs.callPackage ./nix/aarch64-linux.nix { schildi-revenge = sourcePackage; }
          else sourcePackage;
    in {
      packages = forAllSystems (system:
        let package = packageFor system;
        in { default = package; schildi-revenge = package; });
      checks = forAllSystems (system: { schildi-revenge = packageFor system; });
    };
}
