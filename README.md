# Lean Helix template

Nix dev shell for working on a small Lean 4 project in Helix, with a pane that shows the goals and hypotheses at the cursor.
A Zed setup (unicode input only, no goal view) is included too.

## Usage

1. `nix develop` (or `direnv allow`). The first time builds Helix from source (a few minutes).
2. `hx Demo/Basic.lean`. The first open fetches Lean (slow).
3. Move the cursor into a proof; the pane on the right shows its goals.

`Demo/Basic.lean` ends with an unfinished proof (`or_swap`) to inspect.

### Helix

The dev shell's `hx` is built from the [Steel plugin fork](https://github.com/helix-editor/helix/pull/8675) of Helix; the
config lives in `.helix/`. `.helix/lean-goals.scm` adds a pane on the right showing the goals and hypotheses at the cursor.
It asks `lake serve` with Lean's built-in `$/lean/plainGoal` (falling back to `$/lean/plainTermGoal`) 75 ms after the last
cursor movement or edit, so holding `j` sends one request at the end, not one per line. `:lean-goals-toggle` hides or
shows it.

Helix's block cursor sits *on* a character, so at the last character of a tactic line the pane shows the goal before that
tactic; move to the next line to see its result.

The shell sets `HELIX_STEEL_CONFIG` so Helix loads `init.scm`/`helix.scm` from `.helix/`, and `STEEL_HOME` to `.steel/`.

### Zed

`zed .` from inside the dev shell (config in `.zed/settings.json`). Zed is not provided by the flake, so install it separately,
and launch it from the shell so it finds `simple-completion-language-server` and `UNICODE_INPUT_PATH`.

1. Trust the worktree, otherwise Zed won't start language servers or read project settings.
2. Install the **Lean 4** (owlx56) extension, which runs `lake serve`.

Zed extensions can't add panels, so there is no goal view.

## Unicode input

Lean's language server doesn't expand abbreviations like `\to` → `→` (VS Code does it client-side). Here the editor runs
[simple-completion-language-server](https://github.com/estin/simple-completion-language-server) (scls) next to `lake serve`,
fed `unicode-input/lean.toml` (1839 entries generated from vscode-lean4's `abbreviations.json`; the 26 bracket-pair
entries using `$CURSOR` are left out). The dev shell provides scls and sets `UNICODE_INPUT_PATH`.

Type `\to`, `\alpha`, `\N`… and accept the completion (Tab/Enter); `Ctrl-x` opens the menu manually. Optionally set
`completion-trigger-len = 1` under `[editor]` in your Helix `config.toml` so short ones like `\a` pop up (in Zed, `.zed/settings.json` sets `show_completions_on_input`).

Notes: the flake defines `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`; only `x86_64-linux` has been built and tried.
