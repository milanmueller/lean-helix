# lean-tui template

Nix dev shell for trying [lean-tui](https://codeberg.org/wvhulle/lean-tui) with Helix and a small Lean 4 project.

## Usage

1. `nix develop` (or `direnv allow`)
2. `hx Demo/Basic.lean` — the first open builds the lean-prism plugin and fetches Lean (slow).
3. In a second terminal: `nix develop`, then `lean-tui`.
4. In Helix, trigger a request on a proof (e.g. `space k`) to make the graph appear.

`Demo/Basic.lean` ends with an unfinished proof (`or_swap`) to inspect.

## Unicode input

Lean's language server doesn't expand abbreviations like `\to` → `→` (VS Code does it client-side). Here Helix runs
[simple-completion-language-server](https://github.com/estin/simple-completion-language-server) (scls) next to lean-prism,
fed `unicode-input/lean.toml` (1839 entries generated from vscode-lean4's `abbreviations.json`; the 26 bracket-pair
entries using `$CURSOR` are left out). The dev shell provides scls and sets `UNICODE_INPUT_PATH`.

Type `\to`, `\alpha`, `\N`… and accept the completion (Tab/Enter); `Ctrl-x` opens the menu manually. Optionally set
`completion-trigger-len = 1` under `[editor]` in your Helix `config.toml` so short ones like `\a` pop up.

Notes: x86_64-linux only (lean-prism limitation). `lean-toolchain` must match a Lean version supported by lean-prism. The flake uses the `wvhulle.cachix.org` cache if your Nix trusts it.
