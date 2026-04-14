{
  description = "Chatterbox TTS - Open Source TTS and Voice Conversion by Resemble AI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      jetpack-nixos,
    }:
    let
      lib = nixpkgs.lib;

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
            cudaCapabilities =
              if system == "aarch64-linux" then
                [ "8.7" ] # Orin
              else
                [ "8.9" ]; # RTX 2000 Ada
          };
          overlays = lib.optionals (system == "aarch64-linux") [
            jetpack-nixos.overlays.default
            (final: _prev: { inherit (final.nvidia-jetpack) cudaPackages; })
          ];
        };

      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          python = pkgs.python311;
          pp = python.pkgs;

          # --- packages missing from nixpkgs ---

          pyloudnorm = pp.buildPythonPackage rec {
            pname = "pyloudnorm";
            version = "0.2.0";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-i/WXZY6k4ZdcJ1rfSQ9t61Np6kCfKQH5OZFe+ktoGxY=";
            };
            build-system = [ pp.setuptools ];
            dependencies = [
              pp.numpy
              pp.scipy
            ];
            doCheck = false;
            pythonImportsCheck = [ "pyloudnorm" ];
          };

          conformer = pp.buildPythonPackage rec {
            pname = "conformer";
            version = "0.3.2";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-Mu80+kYf8y4cMwYQJcD1g4hPGdLwq6IAI09Odx93fto=";
            };
            build-system = [ pp.setuptools ];
            dependencies = [
              pp.einops
              pp.torch
            ];
            doCheck = false;
            pythonImportsCheck = [ "conformer" ];
          };

          s3tokenizer = pp.buildPythonPackage rec {
            pname = "s3tokenizer";
            version = "0.3.0";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-eGpf+LXKAjUH4Kaox3k6aqGxVQpz12doUdG4yLEoicU=";
            };
            build-system = [ pp.setuptools ];
            pythonRemoveDeps = [ "pre-commit" ];
            dependencies = [
              pp.einops
              pp.numpy
              pp.onnx
              pp.torch
              pp.torchaudio
              pp.tqdm
            ];
            doCheck = false;
            pythonImportsCheck = [ "s3tokenizer" ];
          };

          pyrubberband = pp.buildPythonPackage rec {
            pname = "pyrubberband";
            version = "0.4.0";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-dHB+yMpsYjToStLZpKpcCKYvz9g9oBHVNdQfQ4isSfc=";
            };
            build-system = [ pp.setuptools ];
            dependencies = [
              pp.numpy
              pp.scipy
              pp.soundfile
            ];
            propagatedBuildInputs = [ pkgs.rubberband ];
            doCheck = false;
            pythonImportsCheck = [ "pyrubberband" ];
          };

          sox-python = pp.buildPythonPackage rec {
            pname = "sox";
            version = "1.5.0";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-Ese+W7H1SNiR/hHoLAjPXxoddOIlKY9gCC5a6yRpraA=";
            };
            build-system = [ pp.setuptools ];
            dependencies = [
              pp.numpy
              pp.typing-extensions
            ];
            propagatedBuildInputs = [ pkgs.sox ];
            doCheck = false;
            pythonImportsCheck = [ "sox" ];
          };

          # nixpkgs omegaconf fails on remote builders (pydevd test failure cascade),
          # so we build from PyPI source and regenerate ANTLR grammars with nixpkgs antlr4.
          omegaconf = pp.buildPythonPackage rec {
            pname = "omegaconf";
            version = "2.3.0";
            pyproject = true;
            src = pp.fetchPypi {
              inherit pname version;
              hash = "sha256-1dS20plVzFCtUMRtwmm82SxuAPX5DSOrX+57/KS6TMc=";
            };
            build-system = [ pp.setuptools ];
            nativeBuildInputs = [ pkgs.jre_minimal ];
            postPatch = ''
              substituteInPlace requirements/base.txt \
                --replace-fail "antlr4-python3-runtime==4.9.*" "antlr4-python3-runtime"
              substituteInPlace build_helpers/build_helpers.py \
                --replace-fail \
                  'str(build_dir / "bin" / "antlr-4.9.3-complete.jar")' \
                  '"${pkgs.antlr4.out}/share/java/antlr-${pkgs.antlr4.version}-complete.jar"'
            '';
            dependencies = [
              pp.antlr4-python3-runtime
              pp.pyyaml
            ];
            doCheck = false;
            pythonImportsCheck = [ "omegaconf" ];
          };

          resemble-perth = pp.buildPythonPackage {
            pname = "resemble-perth";
            version = "1.0.1-unstable-2025-06-20";
            src = pkgs.fetchFromGitHub {
              owner = "resemble-ai";
              repo = "Perth";
              rev = "ce86c49d029f42272c1902eccb675556b9ed2330";
              hash = "sha256-sVsuzdguQyWYHl1QgpkbqpQIlwM4GTRNcfudkt7ajb0=";
            };
            pyproject = true;
            build-system = [ pp."uv-build" ];
            dependencies = [
              pp.bitstring
              pp.librosa
              pp.matplotlib
              pp.numpy
              pp.pandas
              pp.parselmouth
              pp.pillow
              pp.pydub
              pp.pywavelets
              pp.pyyaml
              pp."scikit-learn"
              pp.soundfile
              pp.tabulate
              pp.tensorboard
              pp.torch
              pp.torchaudio
              pp.tqdm
              pyloudnorm
              pyrubberband
              sox-python
            ];
            doCheck = false;
            # pythonImportsCheck triggers numba JIT caching which fails in sandbox
          };
        in
        {
          default = self.packages.${system}.chatterbox-tts;

          chatterbox-tts = pp.buildPythonPackage {
            pname = "chatterbox-tts";
            version = "0.1.7";
            src = ./.;
            pyproject = true;

            build-system = [ pp.setuptools ];

            pythonRelaxDeps = [
              "diffusers"
              "numpy"
              "safetensors"
              "torch"
              "torchaudio"
              "transformers"
            ];
            pythonRemoveDeps = [
              "gradio" # only needed for demo web apps
            ];
            postPatch = ''
              substituteInPlace pyproject.toml \
                --replace-fail \
                  'resemble-perth @ git+https://github.com/resemble-ai/Perth.git@master' \
                  'resemble-perth'
            '';

            dependencies = [
              conformer
              omegaconf
              pp.diffusers
              pp.librosa
              pp.numpy
              pp.pykakasi
              pp.safetensors
              pp."spacy-pkuseg"
              pp.torch
              pp.torchaudio
              pp.transformers
              pyloudnorm
              resemble-perth
              s3tokenizer
            ];

            doCheck = false;
            # pythonImportsCheck triggers numba JIT caching (via librosa) which fails in sandbox

            meta = {
              description = "Open Source TTS and Voice Conversion by Resemble AI";
              homepage = "https://github.com/resemble-ai/chatterbox";
              license = lib.licenses.mit;
              platforms = lib.platforms.linux;
            };
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          python = pkgs.python311;
          chatterbox = self.packages.${system}.chatterbox-tts;
        in
        {
          default = pkgs.mkShell {
            packages = [
              (python.withPackages (_: chatterbox.propagatedBuildInputs ++ [ chatterbox ]))
            ];
            shellHook = ''
              export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            '';
          };
        }
      );
    };
}

