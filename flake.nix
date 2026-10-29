{
  description = "Lean 4 playground with a goal pane for Helix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Matt Paras' Helix fork with the Steel (Scheme) plugin system, see PR #8675.
    helix-steel = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, helix-steel, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # The fork's flake builds without the `steel` cargo feature; enable it here.
      helix-with-steel = (helix-steel.packages.${system}.default.override {
        # The perl grammar fails to compile with the current gcc; unrelated to Lean.
        includeGrammarIf = g: g.name != "perl";
      }).overrideAttrs (old: {
        # buildFeatures is consumed by buildRustPackage before overrideAttrs, so pass the flag directly.
        cargoBuildFlags = (old.cargoBuildFlags or [ ]) ++ [ "--features" "steel" ];
      });
    in
    {
      packages.${system}.helix-steel = helix-with-steel;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.elan # provides lean/lake matching ./lean-toolchain
          helix-with-steel # editor with project-local config in .helix/
          pkgs.simple-completion-language-server # unicode input (\to -> →)
        ];
        shellHook = ''
          export UNICODE_INPUT_PATH="$PWD/unicode-input"
          # Keep Steel (Helix plugin) config and data in the repo instead of $HOME.
          export HELIX_STEEL_CONFIG="$PWD/.helix"
          export STEEL_HOME="$PWD/.steel"
          echo "Lean playground: run 'hx Demo/Basic.lean'."
        '';
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
