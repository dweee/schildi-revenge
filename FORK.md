# schildi-revenge fork

Upstream: https://github.com/SchildiChat/schildi-revenge

Base revision: `276946bfbaa2b7ef2f27fe7adb17639ff2f009bd`. Upstream ancestry and license attribution are retained.

Nix desktop packaging with macOS application, notification and keyboard integration.

## Build

```sh
nix build .#packages.<system>.<package>
```

Supported packages and native systems are listed in `nix/platforms.json`.

## CI

Native build workflows are under `.github/workflows/`. The upstream-sync caller
is installed after pinning the published reusable controller.
Darwin and Linux builds are separate where supported. See
[ci/ATTIC.md](ci/ATTIC.md) for optional binary-cache publication and
[ci/UPSTREAM-SYNC.md](ci/UPSTREAM-SYNC.md) for upstream maintenance.
