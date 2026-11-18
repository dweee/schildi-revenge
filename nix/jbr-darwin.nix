{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# nixpkgs' source-built JetBrains Runtime currently supports Linux only.
# Keep upstream's JBR 21 toolchain on macOS too, rather than dropping the AWT
# fixes SchildiChat Revenge relies on by substituting an ordinary OpenJDK distribution.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "schildi-revenge-jetbrains-runtime";
  version = "21.0.10-b1163.110";

  src = fetchurl {
    url = "https://cache-redirector.jetbrains.com/intellij-jbr/jbrsdk-21.0.10-osx-${
      if stdenvNoCC.hostPlatform.isAarch64
      then "aarch64"
      else "x64"
    }-b1163.110.tar.gz";
    hash =
      {
        aarch64-darwin = "sha256-wc7uOs+IkWS50PMSgE3UdGwJIS7lnEn9N/A+QzVfX2k=";
        x86_64-darwin = "sha256-rdpVcT/+5jEUEasrCFd/LEg/dJPmQVsFKjvKQomN1Gg=";
      }
      .${
        stdenvNoCC.hostPlatform.system
      };
  };

  dontBuild = true;
  # Preserve the upstream signatures and the SDK bundle's relative paths.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R Contents "$out/"
    ln -s "$out/Contents/Home/bin" "$out/bin"
    runHook postInstall
  '';

  passthru.home = "${finalAttrs.finalPackage}/Contents/Home";

  meta = {
    description = "JetBrains Runtime 21 SDK for SchildiChat Revenge on macOS";
    homepage = "https://github.com/JetBrains/JetBrainsRuntime";
    license = lib.licenses.gpl2Classpath;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = lib.platforms.darwin;
  };
})
