{
  description = "Lean 4 + lean-tui playground";

  nixConfig = {
    extra-substituters = [ "https://wvhulle.cachix.org" ];
    # Public key is shown by `cachix`/the lean-tui flake; Nix will prompt if missing.
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lean-tui.url = "git+https://codeberg.org/wvhulle/lean-tui";
    lean-prism.url = "git+https://codeberg.org/wvhulle/lean-prism";
  };

  outputs =
    { self, nixpkgs, lean-tui, lean-prism, ... }:
    let
      system = "x86_64-linux"; # lean-prism only builds for x86_64-linux
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.elan # provides lean/lake matching ./lean-toolchain
          pkgs.helix # editor with project-local config in .helix/
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
