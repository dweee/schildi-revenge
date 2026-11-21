{
  description = "schildi-revenge fork with standalone Nix packaging";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
    self.submodules = true;
  };
  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in let
          # Match upstream gradle-wrapper.properties (9.9.1) across Linux locks.
          linuxGradle = (pkgs.gradle-packages.mkGradle {
            version = "9.9.1";
            hash = "sha256-2KGKeoQd1d+CXTWmhfrW8tfxKsDCgOV7Z8J7SlILoig=";
            defaultJava = pkgs.jdk25;
          }).wrapped;
          basePackage = if pkgs.stdenv.hostPlatform.isLinux
            then pkgs.schildi-revenge.override { gradle_9 = linuxGradle; }
            else pkgs.schildi-revenge;
          rtcCargoDeps = pkgs.rustPlatform.importCargoLock {
            lockFile = self + "/matrix-rust-rtc/Cargo.lock";
            allowBuiltinFetchGit = true;
          };
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
            postPatch = (old.postPatch or "") + ''
              # Isolate matrix-rust-sdk and matrix-rust-rtc Cargo vendor configs so
              # both Rust workspaces build offline from their own lockfiles.
              if [ -f ../.cargo/config.toml ]; then
                mkdir -p matrix-rust-sdk/.cargo
                sdkVendor="''${cargoDepsCopy:-$(realpath ../cargo-vendor-dir)}"
                sed "s|directory = \"cargo-vendor-dir\"|directory = \"$sdkVendor\"|" \
                  ../.cargo/config.toml > matrix-rust-sdk/.cargo/config.toml
                rm -f ../.cargo/config.toml
              fi
              rtcVendor="$TMPDIR/matrix-rust-rtc-vendor"
              cp -Lr --reflink=auto -- ${rtcCargoDeps} "$rtcVendor"
              chmod -R u+w -- "$rtcVendor"
              mkdir -p matrix-rust-rtc/.cargo
              sed "s|directory = \"cargo-vendor-dir\"|directory = \"$rtcVendor\"|" \
                "$rtcVendor/.cargo/config.toml" > matrix-rust-rtc/.cargo/config.toml
            '';
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
