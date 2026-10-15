{
  description = "schildi-revenge fork with standalone Nix packaging";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    self.submodules = true;
  };
  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor = system:
        let pkgs = import nixpkgs { inherit system; };
        in let
          sourcePackage = pkgs.schildi-revenge.overrideAttrs (_old: {
            src = nixpkgs.lib.cleanSource self;
          });
        in if pkgs.stdenv.hostPlatform.isDarwin
          then pkgs.callPackage ./nix/package.nix { schildi-revenge = sourcePackage; }
          else sourcePackage;
    in {
      packages = forAllSystems (system:
        let package = packageFor system;
        in { default = package; schildi-revenge = package; });
      checks = forAllSystems (system: { schildi-revenge = packageFor system; });
    };
}
