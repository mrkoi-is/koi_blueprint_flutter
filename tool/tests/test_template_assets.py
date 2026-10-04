from pathlib import Path
import hashlib
import json
import tempfile
from unittest.mock import patch
import unittest

import blueprint
from tool.check_template_assets import check


class RealTemplateAssetsTest(unittest.TestCase):
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
