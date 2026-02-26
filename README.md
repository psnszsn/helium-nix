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

## Overlay

```nix
{
  nixpkgs.overlays = [ helium-nix.overlays.default ];
  # then use pkgs.helium-browser
}
```
