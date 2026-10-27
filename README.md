# lean-tui template

Nix dev shell for trying [lean-tui](https://codeberg.org/wvhulle/lean-tui) with Helix or Zed and a small Lean 4 project. Both setups are semi-working (see the notes per editor).

## Usage

1. `nix develop` (or `direnv allow`)
2. Open `Demo/Basic.lean` in your editor (see below) — the first open builds the lean-prism plugin and fetches Lean (slow).
3. In a second terminal: `nix develop`, then `lean-tui`.
4. Trigger a request on a proof to make the graph appear (see the per-editor notes).

`Demo/Basic.lean` ends with an unfinished proof (`or_swap`) to inspect.

### Helix

`hx Demo/Basic.lean` (config in `.helix/`). Helix sends no LSP request on plain cursor movement, and lean-prism only updates
lean-tui on requests, so `.helix/config.toml` chains a `hover` after `j`/`k`/arrows, undo/redo and leaving insert mode. Other
motions (`w`, `gg`, search, mouse…) don't update the graph; trigger one manually, e.g. `space k`.

### Zed

`zed .` from inside the dev shell (config in `.zed/settings.json`). Zed is not provided by the flake, so install it separately,
and launch it from the shell so it finds `lean-prism`, `simple-completion-language-server` and `UNICODE_INPUT_PATH`.

1. Trust the worktree, otherwise Zed won't start language servers or read project settings.
2. Install the **Lean 4** (owlx56) extension.
3. The settings replace the extension's `lake serve` (server id `lean4-lsp`) with `lean-prism serve` and add `scls`.
   Restart the language server after changing them.

## Unicode input

Lean's language server doesn't expand abbreviations like `\to` → `→` (VS Code does it client-side). Here the editor runs
[simple-completion-language-server](https://github.com/estin/simple-completion-language-server) (scls) next to lean-prism,
fed `unicode-input/lean.toml` (1839 entries generated from vscode-lean4's `abbreviations.json`; the 26 bracket-pair
entries using `$CURSOR` are left out). The dev shell provides scls and sets `UNICODE_INPUT_PATH`.

Type `\to`, `\alpha`, `\N`… and accept the completion (Tab/Enter); `Ctrl-x` opens the menu manually. Optionally set
`completion-trigger-len = 1` under `[editor]` in your Helix `config.toml` so short ones like `\a` pop up (in Zed, `.zed/settings.json` sets `show_completions_on_input`).

Notes: x86_64-linux only (lean-prism limitation). `lean-toolchain` must match a Lean version supported by lean-prism. The flake uses the `wvhulle.cachix.org` cache if your Nix trusts it.
