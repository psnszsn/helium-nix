# helium-nix

Nix package for [Helium](https://github.com/imputnet/helium)

## Build

```bash
nix build .#helium-browser
```

Compilation is memory intensive and can take several hours. By default the build
uses every core on the builder, and V8 compilation can exhaust memory on machines
with many cores. Limit parallel jobs with `--cores`, which does not change the
output path:

```bash
nix build .#helium-browser --cores 20
```

For remote builders, set `cores` in each builder's `nix.conf` instead.

To build exclusively on the configured remote servers:

```bash
nix build .#helium-browser --builders @/etc/nix/machines --max-jobs 0
```

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
