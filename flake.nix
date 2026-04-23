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
            (final: _prev: { inherit (final.nvidia-jetpack6) cudaPackages; })
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
          python = pkgs.python311.override {
            packageOverrides = _: prev: {
              # Disable triton: it's only used by `torch.compile`, which
              # chatterbox never calls. Dropping it avoids a multi-hour
              # LLVM+triton build on aarch64.
              torch = (prev.torch.override { tritonSupport = false; }).overrideAttrs {
                requiredSystemFeatures = [ ];
                NIX_BUILD_CORES = 2;
              };
              # einops pulls in jupyter only for tests, not runtime.
              # Skip its tests to drop the entire jupyter dependency tree
              # (jupyter-server, jupyterlab, django, etc.) from the build.
              einops = prev.einops.overrideAttrs {
                doCheck = false;
              };
              # pydevd's test_utilities suite spawns Python subprocesses that
              # require ptrace/tracing behavior that Nix's build sandbox
              # doesn't allow, causing 3 tests to fail. pydevd is pulled in
              # as a test-only dep of omegaconf, so those failures cascade
              # and block omegaconf from building. Skipping pydevd's own
              # tests lets it build, and omegaconf (which doesn't actually
              # use pydevd at runtime) builds normally.
              pydevd = prev.pydevd.overrideAttrs {
                doCheck = false;
              };
            };
          };
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
              "resemble-perth" # watermarking stubbed out below
            ];
            # Replace `import perth` with a no-op watermarker shim in every
            # file that uses it, so we don't need to build Perth or any of
            # its deps (pydub, soundfile, pyrubberband, sox, librosa-extras,
            # pandas, pillow, pywavelets, scikit-learn, tensorboard, etc.).
            # All four call sites follow the same pattern:
            #   self.watermarker = perth.PerthImplicitWatermarker()
            #   watermarked_wav = self.watermarker.apply_watermark(wav, sample_rate=self.sr)
            # Returning `wav` unchanged is a safe no-op since it's a numpy
            # array fed back into `torch.from_numpy` immediately after.
            postPatch = ''
              for f in src/chatterbox/tts.py src/chatterbox/tts_turbo.py \
                       src/chatterbox/vc.py src/chatterbox/mtl_tts.py; do
                substituteInPlace "$f" --replace-fail \
                  'import perth' \
                  'class _NoopWatermarker:
    def apply_watermark(self, wav, sample_rate=None): return wav
class _PerthShim:
    PerthImplicitWatermarker = _NoopWatermarker
perth = _PerthShim()'
              done
            '';

            dependencies = [
              conformer
              pp.diffusers
              pp.librosa
              pp.numpy
              pp.omegaconf
              pp.pykakasi
              pp.safetensors
              pp."spacy-pkuseg"
              pp.torch
              pp.torchaudio
              pp.transformers
              pyloudnorm
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
          chatterbox = self.packages.${system}.chatterbox-tts;
          python = chatterbox.pythonModule;
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

