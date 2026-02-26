{
  stdenv,
  fetchFromGitHub,
  fetchurl,
  python3Packages,
  makeWrapper,
  patch,
  unzip,
}:

{
  rev,
  hash,
  linuxRev,
  linuxHash,
  extras,
}:

let
  heliumLinux = fetchFromGitHub {
    owner = "imputnet";
    repo = "helium-linux";
    rev = linuxRev;
    hash = linuxHash;
  };

  extraSources = builtins.mapAttrs (
    _name: spec: fetchurl { inherit (spec) url hash; }
  ) extras;
in
stdenv.mkDerivation {
  pname = "helium-source";

  version = rev;

  src = fetchFromGitHub {
    owner = "imputnet";
    repo = "helium";
    inherit rev hash;
  };

  dontBuild = true;

  buildInputs = [
    python3Packages.python
    python3Packages.pillow
    patch
    unzip
  ];

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    mkdir $out
    cp -R * $out/
    mkdir -p $out/helium-linux
    cp -R ${heliumLinux}/* $out/helium-linux/

    # Store extra sources for later unpacking
    mkdir -p $out/extras
    ${builtins.concatStringsSep "\n" (
      builtins.attrValues (
        builtins.mapAttrs (name: src: "ln -s ${src} $out/extras/${name}") extraSources
      )
    )}

    # Don't prune paths that nixpkgs symlinks its own binaries into.
    sed -i "/third_party\/node\/linux/d;/third_party\/jdk\/current/d" $out/utils/prune_binaries.py

    # Skip wasm-rollup patch — nixpkgs handles rollup/esbuild with its own
    # reverts and we let them run. Helium's patch conflicts with that state.
    sed -i '/build-with-wasm-rollup\.patch/d' $out/patches/series

    wrapProgram $out/utils/patches.py --add-flags "apply" --prefix PATH : "${patch}/bin"
  '';
}
