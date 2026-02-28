# helium-nix

Nix package for [Helium](https://github.com/imputnet/helium)

## Build

```bash
# without GPU drivers (NixOS)
nix build .#helium-browser

# with bundled GPU drivers (non-NixOS)
nix build .#helium-browser-gpu
```

Requires ~16GB RAM and several hours to compile.

## Run

```bash
./result/bin/helium
```

## Install

```bash
nix profile add .#helium-browser
```

## Iterative development

Add `breakpointHook` to `nativeBuildInputs` in `package.nix` and `exit 1` where you want to pause (e.g. start of `installPhase`), then run `nix build`. When the build pauses, attach from another terminal with `sudo cntr attach <pid>` (`nix profile install nixpkgs#cntr`) to get an interactive shell inside the sandbox with full build tree and incremental ninja.

## Overlay

```nix
{
  nixpkgs.overlays = [ helium-nix.overlays.default ];
  # then use pkgs.helium-browser
}
```
