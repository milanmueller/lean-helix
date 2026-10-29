{
  description = "Lean 4 + lean-tui playground";

  nixConfig = {
    extra-substituters = [ "https://wvhulle.cachix.org" ];
    # Public key is shown by `cachix`/the lean-tui flake; Nix will prompt if missing.
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lean-tui.url = "git+https://codeberg.org/milanmueller/lean-tui?ref=ansi-colors&rev=27e200b3418cffc7aa206c885ea750db56f53bdb";
    lean-prism.url = "git+https://codeberg.org/wvhulle/lean-prism";
    # Matt Paras' Helix fork with the Steel (Scheme) plugin system, see PR #8675.
    helix-steel = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, lean-tui, lean-prism, helix-steel, ... }:
    let
      system = "x86_64-linux"; # lean-prism only builds for x86_64-linux
      pkgs = import nixpkgs { inherit system; };
      # The fork's flake builds without the `steel` cargo feature; enable it here.
      helix-with-steel = (helix-steel.packages.${system}.default.override {
        # The perl grammar fails to compile with the current gcc; unrelated to Lean.
        includeGrammarIf = g: g.name != "perl";
      }).overrideAttrs (old: {
        buildFeatures = (old.buildFeatures or [ ]) ++ [ "steel" ];
      });
    in
    {
      packages.${system}.helix-steel = helix-with-steel;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.elan # provides lean/lake matching ./lean-toolchain
          helix-with-steel # editor with project-local config in .helix/
          pkgs.simple-completion-language-server # unicode input (\to -> →) in Helix
          lean-tui.packages.${system}.default
          lean-prism.packages.${system}.default
        ];
        shellHook = ''
          export UNICODE_INPUT_PATH="$PWD/unicode-input"
          echo "lean-tui playground: run 'hx Demo/Basic.lean' in one terminal and 'lean-tui' in another."
        '';
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
