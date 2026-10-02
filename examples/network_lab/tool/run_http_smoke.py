#!/usr/bin/env python3
"""Run real native/Chrome HTTP behavior tests against an owned fixture process."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", default=shutil.which("flutter"))
    parser.add_argument("--platform", choices=("vm", "chrome", "both"), default="both")
    args = parser.parse_args()
    if not args.flutter:
        parser.error("Set --flutter to the pinned SDK executable")
    tests = sorted((ROOT / "test/http").glob("*_http_test.dart"))
    if not tests:
        parser.error("No installed real HTTP behavior tests found")
    server = subprocess.Popen([sys.executable, str(ROOT / "tool/http_fixture.py"), "--port", "0"], stdout=subprocess.PIPE, text=True)
    try:
        info = json.loads(server.stdout.readline())
        for platform in (["vm", "chrome"] if args.platform == "both" else [args.platform]):
            command = [args.flutter, "test", "--no-pub", "--dart-define=NETWORK_FIXTURE_URL="+info["url"], "--dart-define=NETWORK_FIXTURE_SHA256="+info["sha256"]]
            if platform == "chrome":
                command += ["--platform", "chrome"]
            command += [str(path.relative_to(ROOT)) for path in tests]
            subprocess.run(command, cwd=ROOT, check=True)
    finally:
        server.terminate()
        server.wait(timeout=10)

if __name__ == "__main__":
    main()
