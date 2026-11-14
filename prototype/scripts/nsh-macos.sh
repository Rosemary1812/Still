#!/bin/bash
set -euo pipefail
prototype="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$prototype/.." && pwd)"
export CARGO_HOME="$root/.tools/cargo"
export RUSTUP_HOME="$root/.tools/rustup"
export PATH="$CARGO_HOME/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$root/.tools/clang-cache"
export SWIFT_MODULECACHE_PATH="$root/.tools/swift-cache"
export MACOSX_DEPLOYMENT_TARGET=14.0
nsh="$root/.tools/nsh/nsh/bin/nsh"
if [[ ! -x "$nsh" ]]; then echo 'Install NSH v0.5.0 into .tools/nsh/nsh first.' >&2; exit 1; fi
cd "$prototype"
exec "$nsh" "$@"
