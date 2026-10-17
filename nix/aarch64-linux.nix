{
  gradle_9,
  lib,
  schildi-revenge,
}:
schildi-revenge.overrideAttrs (finalAttrs: old: {
  # The upstream dependency cache and fixup currently select x86 Linux natives.
  mitmCache = gradle_9.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ../deps-linux-arm64.json;
  };
  postFixup = lib.replaceStrings
    [ "libskiko-linux-x64.so" ]
    [ "libskiko-linux-arm64.so" ]
    old.postFixup;
})
