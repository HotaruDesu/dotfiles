#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Keep editor logs, theme caches and session files out of the user's state.
test_state=$(mktemp -d "${TMPDIR:-/tmp}/lunavim-tests.XXXXXX")
trap 'rm -rf "$test_state"' EXIT
trap 'exit 1' HUP INT TERM
export XDG_STATE_HOME="$test_state/state"
export XDG_CACHE_HOME="$test_state/cache"
export NVIM_LOG_FILE="$test_state/nvim.log"

for test_file in tests/*.lua; do
  nvim --headless -u NONE -i NONE -n -l "$test_file"
done
stylua --check init.lua lua tests scripts
