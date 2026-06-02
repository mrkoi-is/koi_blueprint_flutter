#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
export PATH="$ROOT_DIR/tool:$PATH"
./tool/dartw pub get
./tool/dartw run melos bootstrap
./tool/dartw run melos run generate --no-select
./tool/dartw run melos run analyze --no-select
./tool/dartw run melos run test --no-select
