#!/usr/bin/env python3
"""Compile and test renamed generator outputs in an owned temporary workspace."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import os
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

    def run(script: Path, *arguments: str, cwd: Path, without_chrome: bool = False) -> None:
        command = [sys.executable, str(script), *map(str, arguments)]
        print("+ " + " ".join(command), flush=True)
        environment = dict(os.environ)
        if without_chrome:
            environment['CHROME_EXECUTABLE'] = str(Path(temporary) / 'unavailable-chrome')
        subprocess.run(command, cwd=cwd, env=environment, check=True)

    def assert_assets(project: Path, parent: Path) -> None:
        metadata = json.loads((project / 'blueprint.json').read_text())
        for guide in ('AGENTS.md', 'CLAUDE.md', 'DESIGN.md', 'docs/architecture/ARCHITECTURE.md',
                      'docs/architecture/state-management.md', '.agents/skills/state-management/SKILL.md',
                      'tool/architecture/README.md', '.cursor/rules/agent-entry.mdc'):
            if not (project / guide).is_file():
                if guide.startswith('.cursor/'):
                    continue  # Adapter filename is discovered below, never invented.
                raise AssertionError(f'Missing inherited guidance: {guide}')
            entry = metadata['managedFiles'][guide]
            if entry['sha256'] != hashlib.sha256((project / guide).read_bytes()).hexdigest():
                raise AssertionError(f'Generated guidance digest mismatch: {guide}')
            if entry['sourceSha256'] != hashlib.sha256((parent / entry['source']).read_bytes()).hexdigest():
                raise AssertionError(f'Source guidance digest mismatch: {guide}')
            if (project / '.blueprint/baseline' / entry['sha256']).read_bytes() != (project / guide).read_bytes():
                raise AssertionError(f'Guidance baseline mismatch: {guide}')
        for adapter in (project / '.cursor/rules').rglob('*'):
            if adapter.is_file() and adapter.relative_to(project).as_posix() not in metadata['managedFiles']:
                raise AssertionError(f'Untracked client rule: {adapter}')
        if any(key.startswith(('docs/research/', 'docs/validation/')) for key in metadata['managedFiles']):
            raise AssertionError('Historical guidance is managed in a generated project')
        if 'README.md' in metadata['managedFiles'] or 'CHANGELOG.md' in metadata['managedFiles']:
            raise AssertionError('Initial project documents incorrectly treated as copied guides')

    def assert_feature(member: Path, name: str, prefix: str, kind: str) -> None:
        package = re.search(r'^name: (.+)$', (member / 'pubspec.yaml').read_text(), re.M)[1]
        feature = member / f'lib/{prefix}/{name}'
        if not (feature / f'{name}.dart').is_file():
            raise AssertionError(f'Wrong Feature layout: {feature}')
        tests = list((member / f'test/features/{name}').rglob('*.dart'))
        if not tests:
            raise AssertionError(f'Feature behavior tests were not inherited: {feature}')
        for test in tests:
            if 'package:' + package + '/' + prefix + '/' + name + '/' not in test.read_text():
                raise AssertionError(f'Wrong Feature test import: {test}')
        if kind != 'presentation':
            if not (feature / f'{name}_composition.dart').is_file():
                raise AssertionError('Missing Feature host composition entry')
            public = (feature / f'{name}.dart').read_text()
            if "export 'data/" in public or "export 'presentation/providers/" in public:
                raise AssertionError('Business entry leaks assembly implementation')
        if kind == 'local' and not any(test.name == f'{name}_lifecycle_test.dart' for test in tests):
            raise AssertionError('Local Feature did not inherit session and route lifecycle tests')

    temporary = tempfile.mkdtemp(prefix="koi-generator-smoke-")
    try:
        output = Path(temporary) / "renamed workspace 中文"
        run(
            source / "blueprint.py", "create", "renamed_project",
            "--output", str(output), "--org", "io.blueprint.smoke",
            "--platforms", "web", cwd=source,
        )
        assert_assets(output, source)
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
        assert_assets(descendant, output)
        if (descendant / "docs/validation").exists() or (descendant / "docs/research").exists() or "Initialize second_project" not in (descendant / "CHANGELOG.md").read_text(encoding="utf-8"):
            raise AssertionError("Recursive generation retained the parent project's history")
        run(descendant / "blueprint.py", "check", "ai", "--workspace", str(descendant), cwd=descendant)
        for parent_template, parent in (("minimal", output), ("workbench", Path(temporary) / "workbench parent")):
            if parent_template == "workbench":
                run(source / "blueprint.py", "create", "renamed_workbench", "--output", str(parent),
                    "--org", "io.blueprint.smoke", "--template", "workbench", "--platforms", "web", cwd=source)
                assert_assets(parent, source)
                run(parent / "blueprint.py", "validate", "--workspace", str(parent), cwd=parent)
            for child_template in ("minimal", "workbench"):
                if parent_template == "minimal" and child_template == "minimal":
                    continue  # Covered by second_project above.
                child = Path(temporary) / f"{parent_template}-to-{child_template}"
                run(parent / "blueprint.py", "create", "template_descendant", "--output", str(child),
                    "--org", "io.blueprint.smoke", "--template", child_template, "--platforms", "web", cwd=parent)
                assert_assets(child, parent)
                run(child / "blueprint.py", "check", "ai", "--workspace", str(child), cwd=child)
                run(child / "blueprint.py", "check", "analyze", "--workspace", str(child), cwd=child)
        for name, kind in (
            ("new_api", "api"),
            ("local_draft", "local"),
            ("welcome_panel", "presentation"),
        ):
            if kind == 'local':
                run(output / 'scripts/create_feature.py', str(app), name, '--kind', kind, cwd=output)
                if not (app / f'lib/features/{name}/data/file_{name}_repository_native.dart').is_file():
                    raise AssertionError('Inherited compatibility entry did not preserve local kind')
            else:
                run(generated, "feature", str(app), name, "--kind", kind, cwd=output)
            assert_feature(app, name, "features", kind)
        run(generated, "module", "warehouse_ops", "--workspace", str(output), cwd=output)
        run(
            generated, "feature", str(output / "modules/warehouse_ops"),
            "inventory", "--kind", "api", cwd=output,
        )
        assert_feature(output / "modules/warehouse_ops", "inventory", "src/features", "api")
        if (output / 'modules/warehouse_ops/lib/features').exists():
            raise AssertionError('Module Feature created an accidental App layout')
        package = output / 'packages/feature_host'
        package.mkdir()
        (package / 'pubspec.yaml').write_text('name: feature_host\nresolution: workspace\nenvironment:\n  sdk: ^3.13.0\n')
        manifest = output / 'pubspec.yaml'
        spec = manifest.read_text()
        spec = spec.replace('workspace:\n', 'workspace:\n  - packages/feature_host\n', 1)
        manifest.write_text(spec)
        run(generated, "feature", str(package), "package_catalog", "--kind", "api", cwd=output)
        assert_feature(package, "package_catalog", "src/features", "api")
        (package / 'lib/feature_host.dart').write_text("export 'src/features/package_catalog/package_catalog.dart';\n")
        run(generated, "check", "bootstrap", "--workspace", str(output), cwd=output)
        run(generated, "check", "generate-check", "--workspace", str(output), cwd=output)
        run(generated, "validate", "--workspace", str(output), cwd=output, without_chrome=True)
        print("Generator smoke passed: both templates, four recursive combinations, three features, module and module API feature.")

    except BaseException:
        print(f"Failed generator workspace retained at {temporary}", file=sys.stderr)
        raise
    else:
        shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
