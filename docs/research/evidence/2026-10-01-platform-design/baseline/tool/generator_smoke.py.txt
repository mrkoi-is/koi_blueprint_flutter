#!/usr/bin/env python3
"""Compile and test renamed generator outputs in an owned temporary workspace."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    source = args.source.resolve()

    def run(script: Path, *arguments: str, cwd: Path) -> None:
        command = [sys.executable, str(script), *map(str, arguments)]
        print("+ " + " ".join(command), flush=True)
        subprocess.run(command, cwd=cwd, check=True)

    temporary = tempfile.mkdtemp(prefix="koi-generator-smoke-")
    try:
        output = Path(temporary) / "renamed workspace 中文"
        run(
            source / "blueprint.py", "create", "renamed_project",
            "--output", str(output), "--org", "io.blueprint.smoke",
            "--platforms", "web", cwd=source,
        )
        generated = output / "blueprint.py"
        app = output / "apps/renamed_project_app"
        if (output / "docs/validation").exists() or (output / "docs/research").exists():
            raise AssertionError("Generated project inherited source validation or research")
        changelog = (output / "CHANGELOG.md").read_text(encoding="utf-8")
        if "Initialize renamed_project" not in changelog or "Koi" in changelog:
            raise AssertionError("Generated project did not initialize its own changelog")
        descendant = Path(temporary) / "second generation"
        run(generated, "create", "second_project", "--output", str(descendant),
            "--org", "io.blueprint.smoke", "--platforms", "web", cwd=output)
        if (descendant / "docs/validation").exists() or (descendant / "docs/research").exists() or "Initialize second_project" not in (descendant / "CHANGELOG.md").read_text(encoding="utf-8"):
            raise AssertionError("Recursive generation retained the parent project's history")
        run(descendant / "blueprint.py", "check", "ai", "--workspace", str(descendant), cwd=descendant)
        for parent_template, parent in (("minimal", output), ("workbench", Path(temporary) / "workbench parent")):
            if parent_template == "workbench":
                run(source / "blueprint.py", "create", "renamed_workbench", "--output", str(parent),
                    "--org", "io.blueprint.smoke", "--template", "workbench", "--platforms", "web", cwd=source)
                run(parent / "blueprint.py", "validate", "--workspace", str(parent), cwd=parent)
            for child_template in ("minimal", "workbench"):
                if parent_template == "minimal" and child_template == "minimal":
                    continue  # Covered by second_project above.
                child = Path(temporary) / f"{parent_template}-to-{child_template}"
                run(parent / "blueprint.py", "create", "template_descendant", "--output", str(child),
                    "--org", "io.blueprint.smoke", "--template", child_template, "--platforms", "web", cwd=parent)
                run(child / "blueprint.py", "check", "ai", "--workspace", str(child), cwd=child)
                run(child / "blueprint.py", "check", "analyze", "--workspace", str(child), cwd=child)
        for name, kind in (
            ("new_api", "api"),
            ("local_draft", "local"),
            ("welcome_panel", "presentation"),
        ):
            run(generated, "feature", str(app), name, "--kind", kind, cwd=output)
        run(generated, "module", "warehouse_ops", "--workspace", str(output), cwd=output)
        run(
            generated, "feature", str(output / "modules/warehouse_ops"),
            "inventory", "--kind", "api", cwd=output,
        )
        run(generated, "check", "bootstrap", "--workspace", str(output), cwd=output)
        run(generated, "check", "generate-check", "--workspace", str(output), cwd=output)
        run(generated, "validate", "--workspace", str(output), cwd=output)
        print("Generator smoke passed: both templates, four recursive combinations, three features, module and module API feature.")

    except BaseException:
        print(f"Failed generator workspace retained at {temporary}", file=sys.stderr)
        raise
    else:
        shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
