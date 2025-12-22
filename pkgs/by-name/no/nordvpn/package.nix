{
  libxslt,
  buildGoModule,
  copyDesktopItems,
  e2fsprogs,
  fetchFromGitHub,
  flutter,
  iproute2,
  iptables,
  lib,
  makeDesktopItem,
  makeWrapper,
  openvpn,
  pkg-config,
  procps,
  systemdMinimal,
  wireguard-tools,
}:
let
  tunnelblickSrc = fetchFromGitHub {
    owner = "Tunnelblick";
    repo = "Tunnelblick";
    tag = "v8.0";
    hash = "sha256-Kj/F7hI6E+giT+4iGDUjXCLgy/6jcohtTWtLXOpZfo0=";
  };

  patchedOpenvpn = openvpn.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ (lib.map
        (fname: "${tunnelblickSrc}/third_party/sources/openvpn/openvpn-${old.version}/patches/${fname}")
        [
          "02-tunnelblick-openvpn_xorpatch-a.diff"
          "03-tunnelblick-openvpn_xorpatch-b.diff"
          "04-tunnelblick-openvpn_xorpatch-c.diff"
          "05-tunnelblick-openvpn_xorpatch-d.diff"
          "06-tunnelblick-openvpn_xorpatch-e.diff"
        ]
      );
  });

in
buildGoModule (finalAttrs: {
  pname = "nordvpn";
  version = "4.3.1";

  src = fetchFromGitHub {
    owner = "NordSecurity";
    repo = "nordvpn-linux";
    tag = finalAttrs.version;
    hash = "sha256-o9+9IiXV2CS/Zj3bDg8EJn/UidwA6Fwn4ySFbwyCp60=";
  };

  guiApp = flutter.buildFlutterApplication {
    pname = "nordvpn-gui";
    version = finalAttrs.version;
    src = finalAttrs.src;
    pubspecLock = lib.importJSON ./pubspec.lock.json;
    sourceRoot = "${finalAttrs.src.name}/gui";
  };

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
    pkg-config
  ];

  vendorHash = "sha256-outOvVAu76Pa9lQbiXQP2wA2cee3Ofq41SwfL6JEKs0=";

  preBuild = ''
    # use path $out/bin instead of /usr/lib
    substituteInPlace internal/constants.go --replace-fail /usr/lib/nordvpn "$out/bin"

    # use path <<openvpnPatch>>/bin/openvpn instead of /usr/lib/nordvpn/openvpn
    old_ovpn_path='filepath.Join(internal.AppDataPathStatic, "openvpn")'
    new_ovpn_path=\"${patchedOpenvpn}/bin/openvpn\"
    substituteInPlace daemon/vpn/openvpn/config.go --replace-fail "$old_ovpn_path" "$new_ovpn_path"
  '';

  ldflags = [
    "-X main.Environment=prod"
    "-X main.Hash=${finalAttrs.version}"
    # changing the salt would result in nordvpnd crash for existing users
    "-X main.Salt=f1nd1ngn3m0"
    "-X main.Version=${finalAttrs.version}"
  ];

  subPackages = [
    "cmd/cli"
    "cmd/daemon"
    "cmd/norduser"
  ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    go test ./cli
    # skip tests that require network access
    go test ./daemon -skip 'TestTransports|TestH1Transport_RoundTrip|Test.*FileList_RealURL'
    go test ./norduser

    runHook postCheck
  '';

  postInstall = ''
    # rename to standard names
    BIN_DIR=$out/bin
    install $BIN_DIR/cli $BIN_DIR/nordvpn
    install $BIN_DIR/daemon $BIN_DIR/nordvpnd
    install $BIN_DIR/norduser $BIN_DIR/norduserd
    rm $BIN_DIR/{cli,daemon,norduser}

    # Copy GUI binary from guiApp
    cp -r ${finalAttrs.guiApp}/bin/* $BIN_DIR/

    # nordvpn needs icons for the system tray and notifications
    ASSETS_PATH=$out/share/icons/hicolor/scalable/apps
    install -D assets/icon.svg $ASSETS_PATH/nordvpn.svg
    for file in assets/*; do
      install "$file" "$ASSETS_PATH/nordvpn-$(basename $file)"
    done
  '';

  postFixup = ''
    wrapProgram $out/bin/nordvpnd --set PATH ${
      lib.makeBinPath [
        e2fsprogs
        libxslt
        iproute2
        iptables
        patchedOpenvpn
        procps
        systemdMinimal
        wireguard-tools
      ]
    }
  '';

  desktopItems = [
    (makeDesktopItem {
      categories = [ "Network" ];
      comment = finalAttrs.meta.description;
      desktopName = "nordvpn";
      exec = "nordvpn click %u";
      icon = "nordvpn";
      mimeTypes = [ "x-scheme-handler/nordvpn" ];
      name = "nordvpn";
      terminal = true;
      type = "Application";
    })
    (makeDesktopItem {
      categories = [ "Network" ];
      comment = "NordVPN graphical user interface.";
      desktopName = "NordVPN GUI";
      exec = "nordvpn-gui";
      icon = "nordvpn";
      name = "nordvpn-gui";
      terminal = false;
      type = "Application";
    })
  ];

  meta = {
    description = "NordVPN application for Linux";
    longDescription = ''
      NordVPN application for Linux.
      This package currently does not support meshnet.
      Additionally, if you enable firewall via `networking.firewall.enable = true;`,
      then you should also set `networking.firewall.checkReversePath = "loose";`.
      Example usage:
      ```
      sudo nordvpnd
      sudo chown myuser:nordvpn /run/nordvpn/nordvpnd.sock
      nordvpn c
      ```
      Contributions welcome!
    '';
    homepage = "https://github.com/nordsecurity/nordvpn-linux";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ different-error ];
    platforms = lib.platforms.linux;
  };
})
