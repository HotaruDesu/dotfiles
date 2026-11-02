# Search backend evaluation

The default remains **Snacks + fd/rg**. FFF v0.11.0 is available as an opt-in
backend behind the same Snacks interface and existing bindings. It did not pass
the promotion gate: correct source coverage, at least 20% lower median time to
first results, and no worse P95. Sources are evaluated independently.

## Local result

Measured on 2026-11-02, macOS arm64, Neovim 0.12.5, fd 10.4.2 and ripgrep 15.2.0.
The sample was the local lazy.nvim plugin directory: 6,722 indexed files. Each
eligible source/backend pair used 20 recorded runs over five queries, following
an unrecorded first open. FFF had finished indexing before comparison. Both
backends used the same current Snacks source hooks, layout and 120ms preview
delay.

| Source / backend | First results median | First results P95 | Input update median | Input update P95 |
| --- | ---: | ---: | ---: | ---: |
| Files: fd + Snacks matcher | 26.73ms | 28.62ms | 33.83ms | 199.70ms |
| Files: FFF | skipped: coverage mismatch | — | — | — |
| Grep: rg | 33.95ms | 66.87ms | 87.31ms | 204.98ms |
| Grep: FFF | 39.60ms | 49.81ms | 54.82ms | 202.70ms |

FFF improved median input updates for the tested grep queries, but the first
results median was slower. It therefore stays optional. The filename inventory
did not match fd's complete inventory, so the compatibility guard selected fd
and no native filename timing is presented as equivalent.

Preparing the worker, scanning and auditing the initial inventories took
120.90ms in this run. Reported worker RSS reached 72,384,512 bytes (69.0MiB).
This includes the embedded Neovim process and native index. With both defaults
set to Snacks, no worker is launched and this memory cost is absent.

These are headless Neovim measurements through real Snacks picker objects and
windows, including finding, matching and list updates. They are not Neovide GPU
frame timings. “First results” ends when a shown list is nonempty; input updates
use the actual TextChangedI listener, include the existing 30ms/200ms throttle,
and wait for the updated list to settle. The input-update P95 includes outliers
near 200ms. Preview rendering finishes separately after selection settles.
OS filesystem caches were not cleared; index preparation is a fresh worker
measurement, not a disk-cold benchmark. This sample does not establish performance
on very large C++ repositories or network filesystems. Raw measurements are in
[search-benchmark.json](search-benchmark.json).

## Correctness and lifecycle

- The native worker owns one canonical project root; project switches replace
  it rather than acquiring a native reindex lock in the editor.
- Initial native filenames are compared with complete fd and rg inventories
  independently. Ignore-file saves trigger a fresh audit. Unsupported custom
  options and query syntax use the original finder without reinterpretation.
- Filename results are loaded in pages of 200. Grep pages advance by file offset
  and retain every match within each returned file. The title indicates more
  pages; scrolling near the end loads another page without moving the selection.
- Each request has a 2s timeout. There is at most one active native request and
  one latest queued request per source. Late replies from superseded queries,
  closed pickers and replaced workers cannot update the current list.
- Tests cover UTF-8 byte columns, spaces/Unicode in paths, 251 matching lines in
  one real file, an adapter page with over 10,000 lines, paging, failures,
  ignore-rule differences, create/rename/delete events,
  nonblocking project switches and shutdown. Actual filesystem watcher tests
  were run successfully outside the restricted execution sandbox.

The native fast path intentionally covers ordinary ASCII filename queries and
identifier grep queries. Advanced matcher syntax, path constraints, regular
expressions, custom options and an unready index keep the original fd/rg path.
Smart/recent/LSP ranking is not replaced. Native ranking can differ from the
Snacks filename matcher, which is another reason to keep the backend selectable.

## Reproduce

Install the configured plugins and native library, then run from this directory:

```sh
LUNAVIM_BENCH_OUTPUT=/tmp/lunavim-search-benchmark.json \
  nvim --headless -u NONE -i NONE -n -l scripts/benchmark_search.lua
```

Pass a project directory after the script path to benchmark that project. The
script checks inventory compatibility before native comparisons and records
whether each source meets the latency gate. It never changes the saved backend
configuration. `LUNAVIM_FFF_PATH` can point to another local checkout for explicit
experiments. Re-run the benchmark and correctness tests before changing defaults
or upgrading the pinned native implementation.

FFF is pinned to tag `v0.11.0`, commit
`95fd777c2529fc7b4d7572dabff64cc07268f2c5`. The installed arm64 macOS binary came
from the [official release](https://github.com/dmtrKovalenko/fff/releases/tag/v0.11.0).
Its SHA-256 is
`cd198f5e2a9dde9b5a5632eabf6ac275d3b880e5b064b1bcceb0882d087e8cbc`.
Normal searches do not download binaries; installation/build is handled by the
plugin manager's explicit build step.
