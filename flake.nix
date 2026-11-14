{
  description = "Nix flake for ASSella (ACCELA Fork)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    assella-src = {
      url = "github:niwia/ASSella?ref=v3.1.1";
      flake = false;
    };

    steam-src = {
      url = "github:solsticegamestudios/steam/1373e885f26bb636225443787f54d4082283e5f3";
      flake = false;
    };

    vdf-src = {
      url = "github:solsticegamestudios/vdf/fb88ea7e38a85476743f5601b0c80d5715034623";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      assella-src,
      steam-src,
      vdf-src,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;

          dotnetRuntime = pkgs.dotnet-runtime_9; # .NET 9 Runtime

          python3 = pkgs.python3.override {
            packageOverrides = selfPy: superPy: {
              vdf = selfPy.buildPythonPackage {
                pname = "vdf";
                version = "3.4";
                src = vdf-src;
                format = "setuptools";
                doCheck = false;
              };

              gevent-eventemitter = selfPy.buildPythonPackage rec {
                pname = "gevent-eventemitter";
                version = "2.1";
                src = selfPy.fetchPypi {
                  inherit pname version;
                  hash = "sha256-AObmiMaiVfe9zvHYyZng0C2auH08b/Ym5twaCXYhB/Q=";
                };
                format = "setuptools";
                doCheck = false;
                propagatedBuildInputs = [ selfPy.gevent ];
              };

              just-playback = selfPy.buildPythonPackage rec {
                pname = "just_playback";
                version = "0.1.8";
                src = selfPy.fetchPypi {
                  inherit pname version;
                  hash = "sha256-5ZdHSfEPque7drPx43eaE2knWrF52HWdrifp8ptBA1A=";
                };
                format = "setuptools";
                doCheck = false;
                propagatedBuildInputs = [
                  selfPy.miniaudio
                  selfPy.tinytag
                ];
              };

              steam-py = selfPy.buildPythonPackage {
                pname = "steam";
                version = "1.4.4";
                src = steam-src;
                format = "setuptools";
                doCheck = false;
                nativeBuildInputs = [ selfPy.pythonRelaxDepsHook ];
                pythonRelaxDeps = [
                  "protobuf"
                  "gevent"
                  "vdf"
                ];
                propagatedBuildInputs = with selfPy; [
                  cachetools
                  gevent
                  gevent-eventemitter
                  protobuf
                  pycryptodomex
                  requests
                  six
                  vdf
                  pyrate-limiter
                  urllib3
                ];
              };
            };
          };

          runtimeLibs = with pkgs; [
            zstd
            alsa-lib
            libpulseaudio
            icu
            openssl
            krb5
          ];

          assella = python3.pkgs.buildPythonApplication {
            pname = "assella";
            version = "0-unstable-${assella-src.shortRev or "unknown"}";

            src = assella-src;
            format = "other";

            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.qt6.wrapQtAppsHook
              pkgs.copyDesktopItems
            ];

            buildInputs = [
              dotnetRuntime
            ] ++ (with pkgs.qt6; [
              qtbase
              qtwayland
              qtsvg
            ]);

            propagatedBuildInputs = with python3.pkgs; [
              pyqt6
              pyqt6-sip
              psutil
              requests
              zstandard
              gevent
              gevent-eventemitter
              just-playback
              tinytag
              beautifulsoup4
              steam-py
              vdf
              pillow
              urwid
              cryptography
              numpy
              urllib3
            ];

            desktopItems = [
              (pkgs.makeDesktopItem {
                name = "assella";
                desktopName = "ASSella";
                comment = "ASSella Application";
                exec = "assella %u";
                icon = "assella";
                terminal = false;
                categories = [
                  "Utility"
                  "Application"
                ];
                mimeTypes = [ "x-scheme-handler/accela" ];
              })
            ];

            installPhase = ''
              runHook preInstall

              mkdir -p $out/lib/assella $out/bin
              cp -R src/. $out/lib/assella/

              if [ -d $out/lib/assella/deps ]; then
                ln -s $out/lib/assella/deps $out/bin/deps
              fi

              # Starter script
              cat <<EOF > $out/bin/assella
              #!/usr/bin/env python3
              import sys
              import os

              sys.path.insert(0, "$out/lib/assella")
              os.chdir("$out/lib/assella")

              import main
              if __name__ == "__main__":
                  main.main() if hasattr(main, "main") else None
              EOF
              chmod +x $out/bin/assella

              if [ -f src/res/logo/icon.png ]; then
                install -Dm644 src/res/logo/icon.png $out/share/icons/hicolor/256x256/apps/assella.png
              fi

              runHook postInstall
            '';

            preFixup = ''
              makeWrapperArgs+=(
                --set PYTHONNOUSERSITE 1
                --set DOTNET_ROOT "${dotnetRuntime}/share/dotnet"
                --prefix PATH : "${dotnetRuntime}/bin"
                --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
              )
            '';

            meta = with lib; {
              description = "ASSella packaged for Nix";
              homepage = "https://github.com/niwia/ASSella";
              license = licenses.unfreeRedistributable;
              platforms = platforms.linux;
              mainProgram = "assella";
            };
          };
        in
        {
          default = assella;
          assella = assella;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.assella}/bin/assella";
        };
        assella = {
          type = "app";
          program = "${self.packages.${system}.assella}/bin/assella";
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
