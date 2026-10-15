{
  gradle-packages,
  gradle_9,
  imagemagick,
  lib,
  python3,
  schildi-revenge,
}:
# nixpkgs builds this Compose Desktop client for Linux only, and its Gradle
# dependency cache lacks the macOS Compose/Skiko artifacts. deps-darwin.json
# is re-locked for aarch64-darwin.
# Re-lock from this repository: nix build .#schildi-revenge.mitmCache.updateScript
# then run ./result and review the generated dependency metadata.
let
  # deps.json contains Kotlin DSL 6.7.3 from Gradle 9.7.1.
  gradle = (gradle-packages.mkGradle {
    version = "9.7.1";
    hash = "sha256-rNU/HtrwLxqP+Zh5+KNLMCZhoFfZsGOunjW1UvgE0go=";
    defaultJava = gradle_9.jdk;
  }).wrapped;
in
(schildi-revenge.override {gradle_9 = gradle;}).overrideAttrs (finalAttrs: old: {
  # macOS polish lives in the fork source. Bundle packaging expects
  # graphics/ic_launcher.icns, which postPatch generates from the launcher PNG.
  nativeBuildInputs = old.nativeBuildInputs ++ [imagemagick python3];
  postPatch =
    (old.postPatch or "")
    + ''
      python3 ${./mkicns.py} res/src/commonMain/composeResources/drawable-xxxhdpi/ic_launcher.png graphics/ic_launcher.icns
    '';

  mitmCache = gradle.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ../deps-darwin.json;
  };

  # nixpkgs' default update script only resolves composeApp:dependencies, which
  # misses KSP and packaging tools on macOS; a full distributable build (which
  # also compiles the Rust crate) records everything the real build needs.
  gradleUpdateScript = ''
    runHook preBuild

    gradle createReleaseDistributable --write-verification-metadata sha256
  '';

  # The Android Gradle plugin insists on creating ~/.android; the Darwin
  # sandbox forbids the default HOME.
  preConfigure = ''
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export ANDROID_USER_HOME=$HOME/.android
  '';

  # Compose Desktop on macOS emits a self-contained, already ad-hoc-signed
  # SchildiChatRevenge.app instead of the Linux bin/ + lib/ tree, so skip the
  # patchelf postFixup and don't let fixup touch (and unsign) the Mach-O files.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications $out/bin
    cp -r composeApp/build/compose/binaries/main-release/app/SchildiChatRevenge.app $out/Applications/
    ln -s "$out/Applications/SchildiChatRevenge.app/Contents/MacOS/SchildiChatRevenge" $out/bin/schildichat-revenge

    runHook postInstall
  '';
  postFixup = "";
  dontFixup = true;

  meta = old.meta // {platforms = old.meta.platforms ++ lib.platforms.darwin;};
})
