from pathlib import Path
import tempfile
import unittest

import blueprint
from tool.check_template_assets import check


class RealTemplateAssetsTest(unittest.TestCase):
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
