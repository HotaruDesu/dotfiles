# LunaVim

A Neovim configuration for C++ development, with native LSP, CMake tools and a
shared dark UI for Neovide and terminal Neovim. Existing keyboard gestures are
preserved; `tests/fixtures/keymaps.lua` records their effective definitions.

## Startup and code layout

`init.lua` calls `lunavim.setup()`. It creates the `LunaVim` compatibility API,
loads editor options, automatic commands and keymaps, then starts lazy.nvim.

- `config/`: editor behavior, key definitions, Neovide rendering and UI profiles.
- `plugins/`: plugin specifications and integrations; `ui_specs/` owns UI plugins.
- `lsp/cmake.lua`: project-specific compilation databases and clangd refresh.
- `plugins/lsp/signature/`: syntax parsing/conversion, target discovery, edit
  plans and floating-window interaction. The adjacent `signature.lua` is the
  public entry point. Signature edits remain unsaved for review.
- `after/queries/cpp/`: local highlighting and textobject queries.
- `search/`: project scope, bounded previews, optional native worker and Snacks
  source adapters. Backend selection lives in `config/search.lua`.
- `util/`: explicit public helpers and window movement.

Keep feature state inside its module. Automatic commands belong to named groups
and setup functions must replace their own listeners when called again. UI
styles derive from the central palette rather than copying literal colors.

## Appearance

Terminal Neovim and Neovide use the same solid TokyoNight Night palette.
Starting either editor without a file opens the Snacks dashboard with its
Neovim header, shortcuts and startup time. Opening a file goes directly to it.
The active editor uses the theme background. Inactive splits, sidebars and the
status line recede into a darker surface, and floating panels sit on a slightly
lighter one.
In Normal mode the status line matches the selected tab's blue marker and
blue-gray background. The mode label and marker turn green in Insert, purple in
Visual, amber in Command, red in Replace and cyan in Terminal mode. The label
has a fixed width so the filename stays in place when you press `:`.
Both bars use thin vertical dividers. The right end shows the cursor position.
At 50 columns it also shows progress through the buffer, at 76 columns it adds
the attached language servers, and at 100 columns it shows a file's encoding
and line endings.
Split labels sit one cell inside the editor and show a dot for unsaved edits
even after focus moves away. Neovide uses Maple Mono at 14pt, extra line spacing
and 10px of padding. The terminal emulator controls its own font and padding.

Press `:` to open the command line in the upper third of the window. The prompt
and its completion menu share the editor background. A rounded gray-blue border
outlines the prompt, which starts at 48 text columns when space permits.
Searches with `/` and `?` use the bottom edge. In terminal Neovim, Snacks
animates keyboard scrolling in editing buffers for up to 140ms. In Neovide,
window positions animate over 120ms and navigation over 140ms. Short horizontal
cursor moves take 50ms, including as you type in Insert mode. The cursor also
uses a short trail and blue particles. Reduced motion disables typing animations.

The file picker has a single outer frame and shows the preview beside the
results at 140 columns or more, and below them in narrower windows. The input
row is slightly lighter and the preview is darker than the results. The status
line retains the editing file's context while the picker is open. A floating
terminal has a fine outline and uses the panel background. A terminal in a
split uses the editor background.

Set these globals **before** `require("lunavim").setup()` to choose another mode:

```lua
vim.g.lunavim_ui_style = "glass" -- terminal background or a 96% opaque Neovide window
vim.g.lunavim_reduced_motion = true -- default: false
```

`config/ui.lua` owns the palette, float blending, animation timing and responsive
picker threshold. `config/neovide.lua` owns native rendering settings and the
zoom and fullscreen bindings. Both frontends support Command-S when the
terminal or window system forwards the shortcut.

## Editing behavior

- `:W` saves the current file using the same write hooks and checks as `:w`.
- After two characters, insert completion can suggest words from loaded editing
  buffers, including unsaved text in other tabs. When a buffer word duplicates
  an in-scope language server suggestion, the menu keeps the semantic entry.
  Identical LSP suggestions share one row. Different overloads, snippets and
  imports retain their own entries. After `.`, `->` or `::`, matching members
  take priority, including those that add a required header. If none match,
  the menu can suggest buffer words marked `[BUF]`.
- Use `Ctrl+j` and `Ctrl+k` to preview a name, then keep typing. Press `Enter`
  on a selection to expand its snippet or apply its suggested import.
  `Ctrl+e` cancels the preview. `Ctrl+\` opens the full menu for this prefix.
- Markdown links complete paths relative to the document, including paths
  such as `assets/images/`. In English prose, four letters can bring up to
  three dictionary suggestions after project words when a system word list is available.
- `<leader>wn` moves a split to the next tab, creating one when needed. Its
  cursor and view travel with it, and focus stays in the source tab.
- Formatting remains manual through the existing `<leader>,,` binding.
- `:LunaSpellFix` explicitly runs codespell; ordinary formatting does not correct
  words. `:ConformInfo` shows formatter availability. External formatters must be
  installed separately (`cmake-format` for CMake, `clang-format` for C++).
- `ghc` keeps its outgoing-call action. `:LunaIncomingCalls` exposes incoming calls
  that were previously hidden by the duplicate definition.
- Closing a window removes saved, hidden file buffers. Modified files, visible
  buffers and special buffers remain available. `:BufPrune` also cleans hidden
  saved files explicitly.
- CMake configure success refreshes only clangd clients belonging to that project.
  Database directories are remembered per project for the current editor session;
  explicit clangd database settings take precedence. Selecting a preset takes
  effect after the next successful configure.
- Signature changes support one distinct declaration and definition. Overloads
  with ambiguous targets, virtual hierarchies and unsupported declaration forms
  are rejected. Call sites are listed in quickfix for manual follow-up.

## Search

Existing search bindings and the Snacks interface are preserved. File search
uses fd and live grep uses rg by default. The optional FFF v0.11.0 backend is
installed and pinned, but did not meet the measured promotion threshold. See
[the performance report](docs/search-performance.md) for results and reproduction.
The default configuration does not start a native indexer or file watcher.

Search windows open without an intentional display delay. Selection previews
follow Snacks' existing throttle even while navigation keys repeat. Regular
files are read asynchronously, with one active read and one latest pending
request per picker. Finding/matching and typed queries take priority: new
preview work waits until matching finishes and the query is unchanged for 80ms.
Files below 256KiB show content first and gain syntax highlighting after the
selection is stable for 80ms; 256KiB–1MiB files use bounded plain text, and larger
files show an explanation. Loaded buffers keep their current, unsaved text and
existing highlighting. Closing a picker, changing the selection or hiding its
preview prevents stale work from updating the window. Custom, image, directory
and URI previewers retain their existing semantics.

See the [motion performance report](docs/motion-performance.md) for paired
latency measurements, continuous-preview checks, and the remaining limitations
of the separate batch stress test.

The search scope honors an explicit `cwd`, then native window/tab local
directories, the deepest containing LSP workspace, Git, project markers and
finally the current working directory. Smart, recent and LSP pickers keep their
original search/ranking behavior; the scope and preview hooks apply to the file
sources only.

To evaluate FFF for the current editor session, reopen the picker after changing
its backend:

```vim
:LunaSearchBackend
:LunaSearchBackend files fff
:LunaSearchBackend grep fff
:LunaSearchRefresh
:LunaSearchBackend files snacks
:LunaSearchBackend grep snacks
```

Switching both sources back to Snacks stops the native worker. To persist a
choice, edit `config/search.lua`. An unready, missing or incompatible index,
advanced query syntax, custom filters and hidden/ignored/follow options use the
original finder. The picker title explains native pagination or fallback. FFF
runs in a separate process with bounded requests; native locks cannot stall the
editor's event loop. Ignore-file saves and `:LunaSearchRefresh` rebuild the index
and discard prepared pages.

## Validation

Run `sh tests/run.sh` after installing the configured plugins, parsers and StyLua.
Tests use temporary cache/state directories and disable update checks during
startup checks. They do not download missing dependencies. The real CMake/clangd
integration test reports a skip when either executable is unavailable.
The native search test also reports a skip when the FFF library is missing. Its
watcher checks require normal filesystem event access; restricted sandboxes can
run `LUNAVIM_SKIP_WATCHER_TEST=1 sh tests/run.sh`, then run `tests/search_fff.lua`
separately outside that sandbox to verify create/rename/delete events.

The suite covers keyboard compatibility, repeated setup, buffer cleanup,
Treesitter recovery, textobject ranges, formatting, project isolation, signature
edits/cancellation, search scopes/fallback/pagination, asynchronous previews and
UI layouts. For UI changes, also inspect terminal Neovim and Neovide at wide
and narrow sizes, including completion, search and diagnostics.
