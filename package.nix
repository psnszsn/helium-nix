# Top-level package that wraps the helium browser binary, similar to
# how nixpkgs chromium/default.nix wraps chromium.browser.
{
  lib,
  stdenv,
  makeWrapper,
  ed,
  gnugrep,
  coreutils,
  xdg-utils,
  glib,
  gtk3,
  gtk4,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
  libva,
  pipewire,
  wayland,
  libkrb5,
  mesa,
  libglvnd,
  widevine-cdm,
  runCommand,
  chromium,
  config,
  callPackage,
  pkgsBuildBuild,
  buildPackages,
  python3Packages,
  breakpointHook,
  # package customization
  enableWideVine ? false,
  commandLineArgs ? "",
  enableBreakpoint ? false, # add breakpointHook for iterative development
}:

let
  upstream-info = chromium.upstream-info;
  mkChromiumDerivation = chromium.mkDerivation;

  chromiumVersionAtLeast =
    min-version: lib.versionAtLeast upstream-info.version min-version;

  heliumInfo = lib.importJSON ./info.json;

  helium-source =
    pkgsBuildBuild.callPackage ./helium-source.nix { } {
      inherit (heliumInfo.deps.helium) rev hash;
      linuxRev = heliumInfo.deps.helium-linux.rev;
      linuxHash = heliumInfo.deps.helium-linux.hash;
      extras = heliumInfo.deps.extras;
    };

  heliumBrowser = mkChromiumDerivation (
    base:
    let
      # https://chromium-review.googlesource.com/c/chromium/src/+/7253206
      ifElseM145 = new: old: if chromiumVersionAtLeast "145" then new else old;
    in
    rec {
      name = "helium-browser";
      packageName = "helium";
      buildTargets = [
        "chrome_sandbox"
        "chrome"
      ];

      outputs = [
        "out"
        "sandbox"
      ];

      sandboxExecutableName = "__chromium-suid-sandbox";

      # Filter out nixpkgs patches guarded by `!ungoogled` — Helium includes
      # its own version of these via its ungoogled-chromium patch set.
      patches = builtins.filter (p:
        let name = builtins.toString p; in
        !lib.hasSuffix "build-with-wasm-rollup.patch" name
        && !lib.hasSuffix "revert-Add-finch-seeds-to-desktop-perf-builds.patch" name
      ) base.patches;

      nativeBuildInputs = base.nativeBuildInputs ++ [
        python3Packages.pillow
        buildPackages.unzip
      ] ++ lib.optionals enableBreakpoint [
        breakpointHook
      ];

      postPatch =
        base.postPatch
        + ''
          # Helium: prune binaries
          ${helium-source}/utils/prune_binaries.py . ${helium-source}/pruning.list || echo "some errors"

          # Helium: unpack extras before patches (patches modify ublock files)
          mkdir -p third_party/ublock
          ${buildPackages.unzip}/bin/unzip -o ${helium-source}/extras/ublock -d third_party/ublock
          if [ -d third_party/ublock/uBlock0.chromium ]; then
            mv third_party/ublock/uBlock0.chromium/* third_party/ublock/
            rmdir third_party/ublock/uBlock0.chromium
          fi

          mkdir -p components/helium_onboarding
          tar xzf ${helium-source}/extras/onboarding -C components/helium_onboarding

          mkdir -p third_party/search_engines_data/resources_internal
          tar xzf ${helium-source}/extras/searchEngines -C third_party/search_engines_data/resources_internal

          # Re-create dirs that pruning may have removed
          mkdir -p third_party/jdk/current/bin

          # Helium: apply patches (main + linux-specific)
          ${helium-source}/utils/patches.py . ${helium-source}/patches
          ${helium-source}/utils/patches.py . ${helium-source}/helium-linux/patches

          # Helium: domain substitution
          ${helium-source}/utils/domain_substitution.py apply \
            -r ${helium-source}/domain_regex.list \
            -f ${helium-source}/domain_substitution.list \
            .

          # Helium: name substitution (Chromium -> Helium branding)
          python3 ${helium-source}/utils/name_substitution.py --sub \
            -t . --backup-path helium-namesubs.tar.gz

          # Helium: version stamping
          python3 ${helium-source}/utils/helium_version.py \
            --tree ${helium-source} \
            --platform-tree ${helium-source}/helium-linux \
            --chromium-tree .

          # Helium: generate and replace branded resources
          cp -r ${helium-source}/resources helium-resources
          chmod -R u+w helium-resources
          python3 ${helium-source}/utils/generate_resources.py \
            helium-resources/generate_resources.txt helium-resources
          python3 ${helium-source}/utils/replace_resources.py \
            helium-resources/helium_resources.txt helium-resources .

          rm -f helium-namesubs.tar.gz
        '';

      # Helium-specific GN flags
      gnFlags = lib.importTOML ./helium-flags.toml;

      installPhase = ''
        mkdir -p "$libExecPath"
        cp -v "$buildPath/"*.so "$buildPath/"*.pak "$buildPath/"*.bin "$libExecPath/"
        cp -v "$buildPath/libvulkan.so.1" "$libExecPath/"
        cp -v "$buildPath/vk_swiftshader_icd.json" "$libExecPath/"
        cp -v "$buildPath/icudtl.dat" "$libExecPath/"
        cp -vLR "$buildPath/locales" "$buildPath/resources" "$libExecPath/"
        cp -v "$buildPath/helium_crashpad_handler" "$libExecPath/"
        cp -v "$buildPath/helium" "$libExecPath/$packageName"

        # Swiftshader
        if [ -n "$(find "$buildPath/swiftshader/" -maxdepth 1 -name '*.so' -print -quit)" ]; then
          echo "Swiftshader files found; installing"
          mkdir -p "$libExecPath/swiftshader"
          cp -v "$buildPath/swiftshader/"*.so "$libExecPath/swiftshader/"
        else
          echo "Swiftshader files not found"
        fi

        mkdir -p "$sandbox/bin"
        cp -v "$buildPath/chrome_sandbox" "$sandbox/bin/${sandboxExecutableName}"

        mkdir -vp "$out/share/man/man1"
        cp -v "$buildPath/$packageName.1" "$out/share/man/man1/$packageName.1" \
          || cp -v "$buildPath/chrome.1" "$out/share/man/man1/$packageName.1" \
          || echo "warning: man page not found, skipping"

        # Install regular size icons
        for size in 24 48 64 128 256; do
          icon_file="chrome/app/theme/chromium/product_logo_''${size}.png"
          if [ -f "$icon_file" ]; then
            install -Dvm644 "$icon_file" \
              "$out/share/icons/hicolor/''${size}x''${size}/apps/$packageName.png"
          fi
        done

        # Install small icons from 100% density source
        for size in 16 32; do
          icon_file="chrome/app/theme/default_100_percent/chromium/product_logo_''${size}.png"
          if [ -f "$icon_file" ]; then
            install -Dvm644 "$icon_file" \
              "$out/share/icons/hicolor/''${size}x''${size}/apps/$packageName.png"
          fi
        done

        # Install scalable SVG icon
        if [ -f "chrome/app/theme/chromium/product_logo.svg" ]; then
          install -Dvm644 chrome/app/theme/chromium/product_logo.svg \
            "$out/share/icons/hicolor/scalable/apps/$packageName.svg"
        fi

        # Install Desktop Entry
        install -D chrome/installer/linux/common/desktop.template \
          $out/share/applications/helium-browser.desktop

        substituteInPlace $out/share/applications/helium-browser.desktop \
          --replace-fail "${ifElseM145 "@@MENUNAME" "@@MENUNAME@@"}" "Helium" \
          --replace-fail "${ifElseM145 "@@PACKAGE" "@@PACKAGE@@"}" "helium" \
          --replace-fail "${ifElseM145 "/usr/bin/@@usr_bin_symlink_name" "/usr/bin/@@USR_BIN_SYMLINK_NAME@@"}" "helium" \
          --replace-fail "${ifElseM145 "@@uri_scheme" "@@URI_SCHEME@@"}" "x-scheme-handler/helium;" \
          --replace-fail "${ifElseM145 "@@extra_desktop_entries" "@@EXTRA_DESKTOP_ENTRIES@@"}" ""

        substituteInPlace $out/share/applications/helium-browser.desktop \
          --replace-fail "[Desktop Entry]" "[Desktop Entry]''\nStartupWMClass=helium-browser"

        if grep -F '@@' $out/share/applications/helium-browser.desktop ; then
          echo "error: helium-browser.desktop contains unsubstituted placeholders" >&2
          exit 1
        fi
      '';

      passthru = { inherit sandboxExecutableName; };

      requiredSystemFeatures = [ "big-parallel" ];

      meta = {
        description = "Privacy-focused Chromium-based browser";
        longDescription = ''
          Helium is a privacy-focused browser based on Chromium. It bundles patches from
          ungoogled-chromium, bromite, brave, inox, iridium, and debian, along with its own
          extensive privacy and UI modifications. It includes uBlock Origin out of the box.
        '';
        homepage = "https://github.com/imputnet/helium";
        license = if enableWideVine then lib.licenses.unfree else lib.licenses.bsd3;
        platforms = lib.platforms.linux;
        mainProgram = "helium";
        hydraPlatforms = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        timeout = 172800;
      };
    }
  );

  sandboxExecutableName = heliumBrowser.passthru.sandboxExecutableName;

  # Optionally add WidevineCdm without rebuilding
  chromiumWV =
    if enableWideVine then
      runCommand (heliumBrowser.name + "-wv") { version = heliumBrowser.version; } ''
        mkdir -p $out
        cp -a ${heliumBrowser}/* $out/
        chmod u+w $out/libexec/helium
        cp -a ${widevine-cdm}/share/google/chrome/WidevineCdm $out/libexec/helium/
      ''
    else
      heliumBrowser;

  runtimeStdenv = chromium.mkDerivation (base: { }).stdenv or stdenv;
in
stdenv.mkDerivation {
  pname = "helium";
  inherit (heliumBrowser) version;

  nativeBuildInputs = [
    makeWrapper
    ed
  ];

  buildInputs = [
    gsettings-desktop-schemas
    glib
    gtk3
    gtk4
    adwaita-icon-theme
    libkrb5
  ];

  outputs = [
    "out"
    "sandbox"
  ];

  buildCommand =
    let
      browserBinary = "${chromiumWV}/libexec/helium/helium";
      libPath = lib.makeLibraryPath ([
        libva
        pipewire
        wayland
        gtk3
        gtk4
        libkrb5
        mesa
        libglvnd
      ]);
    in
    ''
      mkdir -p "$out/bin"

      makeWrapper "${browserBinary}" "$out/bin/helium" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
        --add-flags ${lib.escapeShellArg commandLineArgs} \
        --set-default LIBGL_DRIVERS_PATH "${mesa}/lib/dri" \
        --set-default GBM_BACKENDS_PATH "${mesa}/lib/gbm" \
        --set-default LIBVA_DRIVERS_PATH "${mesa}/lib/dri" \
        --set-default __EGL_VENDOR_LIBRARY_FILENAMES "${mesa}/share/glvnd/egl_vendor.d/50_mesa.json"

      ed -v -s "$out/bin/helium" << EOF
      2i

      if [ -x "/run/wrappers/bin/${sandboxExecutableName}" ]
      then
        export CHROME_DEVEL_SANDBOX="/run/wrappers/bin/${sandboxExecutableName}"
      else
        export CHROME_DEVEL_SANDBOX="$sandbox/bin/${sandboxExecutableName}"
      fi

      # Make generated desktop shortcuts have a valid executable name.
      export CHROME_WRAPPER='helium'

    ''
    + lib.optionalString (libPath != "") ''
      # To avoid loading .so files from cwd, LD_LIBRARY_PATH here must not
      # contain an empty section before or after a colon.
      export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH\''${LD_LIBRARY_PATH:+:}${libPath}"
    ''
    + ''

      # libredirect causes chromium to deadlock on startup
      export LD_PRELOAD="\$(echo -n "\$LD_PRELOAD" | ${coreutils}/bin/tr ':' '\n' | ${gnugrep}/bin/grep -v /lib/libredirect\\\\.so$ | ${coreutils}/bin/tr '\n' ':')"

      export XDG_DATA_DIRS=$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH\''${XDG_DATA_DIRS:+:}\$XDG_DATA_DIRS

    ''
    + lib.optionalString (!xdg-utils.meta.broken) ''
      # Mainly for xdg-open but also other xdg-* tools:
      export PATH="\$PATH\''${PATH:+:}${xdg-utils}/bin"
    ''
    + ''

      .
      w
      EOF

      ln -sv "${heliumBrowser.sandbox}" "$sandbox"

      ln -s "$out/bin/helium" "$out/bin/helium-browser"

      mkdir -p "$out/share"
      for f in '${heliumBrowser}'/share/*; do # hello emacs */
        ln -s -t "$out/share/" "$f"
      done
    '';

  packageName = "helium";
  meta = heliumBrowser.meta;
  passthru = {
    browser = heliumBrowser;
    mkDerivation = mkChromiumDerivation;
    inherit sandboxExecutableName;
  };
}
