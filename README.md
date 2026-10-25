# lean-tui template

Nix dev shell for trying [lean-tui](https://codeberg.org/wvhulle/lean-tui) with Helix and a small Lean 4 project.

## Usage

1. `nix develop` (or `direnv allow`)
2. `hx Demo/Basic.lean` — the first open builds the lean-prism plugin and fetches Lean (slow).
3. In a second terminal: `nix develop`, then `lean-tui`.
4. In Helix, trigger a request on a proof (e.g. `space k`) to make the graph appear.

`Demo/Basic.lean` ends with an unfinished proof (`or_swap`) to inspect.

Notes: x86_64-linux only (lean-prism limitation). `lean-toolchain` must match a Lean version supported by lean-prism. The flake uses the `wvhulle.cachix.org` cache if your Nix trusts it.
