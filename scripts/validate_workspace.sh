#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
export PATH="$ROOT_DIR/tool:$PATH"
"$ROOT_DIR/tool/dartw" pub get --enforce-lockfile
"$ROOT_DIR/tool/melos" bootstrap
"$ROOT_DIR/scripts/check_generated.sh"
"$ROOT_DIR/tool/melos" run format:check --no-select
"$ROOT_DIR/tool/melos" run analyze --no-select
"$ROOT_DIR/tool/melos" run test --no-select
python3 -m unittest discover -s scripts/tests

SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/koi-web-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_DIR"' EXIT
"$ROOT_DIR/tool/dartw" compile js \
  packages/koi_api_bootstrap/test/web_compile_smoke.dart \
  -o "$SMOKE_DIR/web-smoke.js"
node "$SMOKE_DIR/web-smoke.js"
(
  cd apps/koi_admin_app
  "$ROOT_DIR/tool/flutterw" build web --release --dart-define=ENV=prod
)

"$ROOT_DIR/scripts/check_coverage.sh"
