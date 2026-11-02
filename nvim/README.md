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

The default Neovide profile uses a subtle frosted native background, uniform
panel colors and short animations. Adjacent floating windows stay opaque inside
Neovim to avoid seams from repeated transparency, blur and shadows. Terminal Neovim shares the color
palette; desktop transparency and blur are controlled by the terminal emulator.

Set these globals **before** `require("lunavim").setup()` to choose another mode:

```lua
vim.g.lunavim_ui_style = "solid" -- default: "glass"
vim.g.lunavim_reduced_motion = true -- default: false
```

`config/ui.lua` owns the palette, float blending, animation timing and responsive
picker threshold. `config/neovide.lua` owns native rendering settings and the
existing zoom, save and fullscreen bindings.

## Editing behavior

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

Search windows open without an intentional display delay. File previews wait
120ms after selection settles: files below 256KiB keep normal highlighting,
256KiB–1MiB files use bounded plain-text previews, and larger files show an
explanation. Loaded buffers use their current, unsaved text. Closing a picker,
changing the selection or hiding its preview cancels stale work.

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
UI layouts. For UI changes, also inspect actual Neovide
windows at wide and narrow sizes, including completion, search and diagnostics.
