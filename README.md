# Lean Helix template

Nix dev shell for working on a small Lean 4 project in Helix, with a pane that shows the goals and hypotheses at the cursor.

## Usage

1. `nix develop` (or `direnv allow`). The first time builds Helix from source (a few minutes).
2. `hx Demo/Basic.lean`. The first open fetches Lean (slow).
3. Move the cursor into a proof; the pane on the right shows its goals.

`Demo/Basic.lean` ends with an unfinished proof (`or_swap`) to inspect.

## Goal pane

The dev shell's `hx` is built from the [Steel plugin fork](https://github.com/helix-editor/helix/pull/8675) of Helix; the
config lives in `.helix/`. `.helix/lean-goals.scm` opens a vertical split on the right showing, like VS Code's infoview, what
Lean knows at the cursor:

- **Tactic state**: the goals and hypotheses (`$/lean/plainGoal`).
- **Expected type** of the term at the cursor (`$/lean/plainTermGoal`).
- **Messages**: errors, warnings and `#eval`/`#check` output for the cursor line. Helix doesn't pass diagnostics on to
  plugins, so these come from Lean's RPC (`Lean.Widget.getInteractiveDiagnostics`), as in the infoview.

It asks `lake serve` 75 ms after the last cursor movement or edit, so holding `j` sends one round of requests at the end,
not one per line. Empty sections are left out. `:lean-goals-toggle` hides or shows the pane.

The pane is an ordinary split showing a file under `/tmp/lean-goals-*/`, which the plugin rewrites and reloads. You can
move into it with `Space w l` / `Ctrl-w l`, and select and yank text there as in any buffer. It only updates while
the focused buffer is a Lean file. Helix has no split resizing, so it takes the same width as the other splits. Since it
is its own window, `:q` in the Lean buffer leaves the pane open; use `:qa` to quit both.

Helix's block cursor sits *on* a character, so at the last character of a tactic line the pane shows the goal before that
tactic; move to the next line to see its result.

The shell sets `HELIX_STEEL_CONFIG` so Helix loads `init.scm`/`helix.scm` from `.helix/`, and `STEEL_HOME` to `.steel/`.

The fork pins workspace trust to a hash of `.helix/`. After that directory changes (e.g. after a `git pull`), Helix
ignores the local config and says so in the status line; run `:workspace-trust` from a Lean buffer to allow it again.

## Unicode input

Lean's language server doesn't expand abbreviations like `\to` → `→` (VS Code does it client-side). Here the editor runs
[simple-completion-language-server](https://github.com/estin/simple-completion-language-server) (scls) next to `lake serve`,
fed `unicode-input/lean.toml` (1839 entries generated from vscode-lean4's `abbreviations.json`; the 26 bracket-pair
entries using `$CURSOR` are left out). The dev shell provides scls and sets `UNICODE_INPUT_PATH`.

Type `\to`, `\alpha`, `\N`… and accept the completion (Tab/Enter); `Ctrl-x` opens the menu manually. Optionally set
`completion-trigger-len = 1` under `[editor]` in `.helix/config.toml` so short ones like `\a` pop up.

Notes: the flake defines `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`; only `x86_64-linux` has been built and tried.
