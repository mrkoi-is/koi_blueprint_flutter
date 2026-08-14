#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
export PATH="$ROOT_DIR/tool:$PATH"
"$ROOT_DIR/tool/dartw" pub get
"$ROOT_DIR/tool/melos" bootstrap
"$ROOT_DIR/tool/melos" run format:check --no-select
"$ROOT_DIR/scripts/check_generated.sh"
"$ROOT_DIR/tool/melos" run analyze --no-select
"$ROOT_DIR/tool/melos" run test --no-select
"$ROOT_DIR/scripts/check_coverage.sh"
