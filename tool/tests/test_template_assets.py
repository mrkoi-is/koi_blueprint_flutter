from pathlib import Path
import hashlib
import json
import tempfile
from unittest.mock import patch
import unittest

import blueprint
from tool.check_template_assets import check
from tool.platform_evidence import source_manifest


class RealTemplateAssetsTest(unittest.TestCase):
    def test_macos_versioned_goldens_are_inherited_with_exact_bytes(self):
        source = Path(__file__).resolve().parents[2] / 'packages/koi_ui/test/golden'
        names = ('empty_narrow_large.png', 'error_dark.png', 'error_light.png')
        with tempfile.TemporaryDirectory(prefix='koi-golden-inherit-') as temporary:
            destination = Path(temporary) / 'golden'
            blueprint.copy(source, destination)
            for family in ('macos-arm64', 'macos-26-arm64'):
                for name in names:
                    relative = Path('baselines') / family / name
                    self.assertTrue((source / relative).is_file())
                    self.assertEqual((source / relative).read_bytes(),
                                     (destination / relative).read_bytes())
            self.assertFalse((destination / 'failures').exists())

    def test_golden_baselines_inherit_but_failure_artifacts_do_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            for relative in ('test/golden/baselines/example.png',
                             'test/golden/fonts/font.ttf',
                             'test/golden/failures/actual.png',
                             'test/fixtures/failures/legitimate.json'):
                path = source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'fixture')
            blueprint.copy(source, root / 'copy')
            self.assertTrue((root / 'copy/test/golden/baselines/example.png').is_file())
            self.assertTrue((root / 'copy/test/golden/fonts/font.ttf').is_file())
            self.assertFalse((root / 'copy/test/golden/failures').exists())
            self.assertTrue((root / 'copy/test/fixtures/failures/legitimate.json').is_file())

    def test_golden_diagnostics_do_not_change_source_but_baselines_do(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            before = source_manifest(root)['source_sha256']
            diagnostics = root / 'packages/ui/test/golden/failures/actual.png'
            diagnostics.parent.mkdir(parents=True)
            diagnostics.write_bytes(b'output')
            self.assertEqual(source_manifest(root)['source_sha256'], before)
            baseline = root / 'packages/ui/test/golden/baselines/state.png'
            baseline.parent.mkdir()
            baseline.write_bytes(b'baseline')
            self.assertNotEqual(source_manifest(root)['source_sha256'], before)

    def test_copy_plan_drives_guidance_baselines_in_recursive_generation(self):
        source = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix='koi-copy-plan-') as temporary:
            first, second = Path(temporary) / 'first', Path(temporary) / 'second'
            for parent, stage, name in ((source, first, 'first'), (first, second, 'second')):
                stage.mkdir()
                with patch.object(blueprint, 'ROOT', parent):
                    plan = blueprint.workspace_asset_plan(parent, name)
                    origins = blueprint.inherit_workspace_assets(stage, name)
                    self.assertEqual(origins, {item['destination']: item['source'] for item in plan
                                             if item['kind'] in ('guidance', 'tooling')})
                    self.assertEqual({item['kind'] for item in plan}, {'guidance', 'tooling', 'reference', 'project_seed'})
                    self.assertFalse((stage / 'docs/research').exists())
                    self.assertFalse((stage / 'docs/validation').exists())
                    (stage / 'blueprint.json').write_text(json.dumps({'schema': 2, 'name': name,
                        'managedFiles': {}, 'capabilities': {}}))
                    app = stage / ('apps/' + name + '_app')
                    template = blueprint.source_root() / 'examples/starter_app'
                    blueprint.copy(template, app)
                    blueprint.finalize_generated_provenance(stage, app, template, origins)
                metadata = json.loads((stage / 'blueprint.json').read_text())
                for entry in plan:
                    if entry['kind'] != 'guidance': continue
                    path = entry['destination']
                    recorded = metadata['managedFiles'][path]
                    self.assertEqual(recorded['sha256'], hashlib.sha256((stage / path).read_bytes()).hexdigest())
                    self.assertEqual(recorded['sourceSha256'], hashlib.sha256((parent / entry['source']).read_bytes()).hexdigest())
                    self.assertEqual((stage / '.blueprint/baseline' / recorded['sha256']).read_bytes(), (stage / path).read_bytes())
                self.assertNotIn('README.md', metadata['managedFiles'])
                self.assertNotIn('CHANGELOG.md', metadata['managedFiles'])
                self.assertIn('Initialize ' + name, (stage / 'CHANGELOG.md').read_text())

    def test_current_inherited_assets_and_source_only_reference_regression(self):
        source = Path(__file__).resolve().parents[2]
        original = blueprint.ROOT
        try:
            self.assertEqual(check(source), [])
            with tempfile.TemporaryDirectory(prefix='koi-real-assets-regression-') as temporary:
                clone = Path(temporary)
                blueprint.inherit_workspace_assets(clone, 'probe')
                self.assertTrue((clone / 'tool/blueprint_test.py').is_file())
                self.assertTrue((clone / 'tool/workspace_lock.py').is_file())
                blueprint.copy(source / 'packages', clone / 'packages')
                (clone / 'pubspec.yaml').write_bytes((source / 'pubspec.yaml').read_bytes())
                research = clone / 'docs/research/source-only.md'
                research.parent.mkdir(parents=True)
                research.write_text('Source-only evidence', encoding='utf-8')
                design = clone / 'DESIGN.md'
                design.write_text(design.read_text(encoding='utf-8') + '\n[Source evidence](docs/research/source-only.md)\n', encoding='utf-8')
                self.assertTrue(research.is_file())
                failures = check(clone)
                self.assertTrue(any('minimal:' in value and 'source-only.md' in value for value in failures), failures)
                self.assertTrue(any('workbench:' in value and 'source-only.md' in value for value in failures), failures)
        finally:
            blueprint.ROOT = original
