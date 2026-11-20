{
  description = "schildi-revenge fork with standalone Nix packaging";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/0bb8272318b4ca41bf0edc6224df3e3e3046b70d";
    self.submodules = true;
  };
  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in let
          # The Linux offline locks were generated with Gradle 9.8.2.
          # Keep the compiler/plugin pair aligned while nixpkgs advances.
          linuxGradle = (pkgs.gradle-packages.mkGradle {
            version = "9.8.2";
            hash = "sha256-Ib1dot5JtkKQQHfzjA79x3eOkrPtCIk5LcphuX44lgc=";
            defaultJava = pkgs.jdk25;
          }).wrapped;
          basePackage = if pkgs.stdenv.hostPlatform.isLinux
            then pkgs.schildi-revenge.override { gradle_9 = linuxGradle; }
            else pkgs.schildi-revenge;
          sourcePackage = basePackage.overrideAttrs (finalAttrs: old: {
            # cargoSetupHook requires system libraries for these active SDK features.
            nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkg-config ];
            buildInputs = (old.buildInputs or []) ++ [ pkgs.aws-lc pkgs.zstd pkgs.sqlite ];
            # The fork SDK lock can advance independently of the nixpkgs release.
            cargoDeps = pkgs.rustPlatform.importCargoLock {
              # Crate checksums come from the lock itself, so an SDK lock bump
              # needs no hand-maintained vendor hash. Git sources are pinned
              # by the revision recorded in the lock.
              lockFile = self + "/matrix-rust-sdk/Cargo.lock";
              allowBuiltinFetchGit = true;
            };
            # Keep the standalone fork cache current with upstream dependency bumps.
            mitmCache = linuxGradle.fetchDeps {
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
          then pkgs.callPackage ./nix/aarch64-linux.nix { schildi-revenge = sourcePackage; gradle_9 = linuxGradle; }
          else sourcePackage;
    in {
      packages = forAllSystems (system:
        let package = packageFor system;
        in { default = package; schildi-revenge = package; });
      checks = forAllSystems (system: { schildi-revenge = packageFor system; });
    };
}
