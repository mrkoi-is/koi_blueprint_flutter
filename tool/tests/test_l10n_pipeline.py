from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import blueprint


class LocalizationPipelineTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.app = self.root / 'apps/demo'
        self.app.mkdir(parents=True)
        (self.app / 'l10n.yaml').write_text('arb-dir: lib/l10n\n')
        (self.app / 'pubspec.yaml').write_text('name: demo\ndev_dependencies:\n  build_runner: any\n')
        self.sdk = SimpleNamespace(dart='dart', flutter='flutter')
        self.enterContext(patch.object(blueprint, 'SDK', return_value=self.sdk))
        self.enterContext(patch.object(blueprint, 'members', return_value=[self.app]))

    def test_source_check_precedes_generation_in_both_generate_commands(self):
        for phase in ('generate', 'generate-check'):
            with self.subTest(phase=phase), patch.object(blueprint, 'run') as run:
                blueprint.check(SimpleNamespace(workspace=self.root, phase=phase))
                self.assertEqual(run.call_args_list[0].args,
                                 (['dart', 'run', 'tool/check_l10n.dart', self.app], self.root))
                self.assertEqual(run.call_args_list[1].args,
                                 (['flutter', 'gen-l10n'], self.app))

    def test_invalid_translations_stop_before_generating_fallback_code(self):
        with patch.object(blueprint, 'run', side_effect=blueprint.BlueprintError('missing translation')) as run:
            with self.assertRaisesRegex(blueprint.BlueprintError, 'missing translation'):
                blueprint.check(SimpleNamespace(workspace=self.root, phase='generate-check'))
            self.assertEqual(run.call_count, 1)

    def test_l10n_phase_does_not_generate_or_run_build_runner(self):
        with patch.object(blueprint, 'run') as run:
            blueprint.check(SimpleNamespace(workspace=self.root, phase='l10n'))
            self.assertEqual(run.call_count, 1)
            self.assertIn('tool/check_l10n.dart', run.call_args.args[0])

    def test_nonlocalized_members_are_not_passed_to_the_checker(self):
        plain = self.root / 'packages/domain'
        plain.mkdir(parents=True)
        with patch.object(blueprint, 'run') as run:
            blueprint.check_localizations(self.root, self.sdk, [plain, self.app])
            self.assertEqual(run.call_args.args[0][-1], self.app)
            self.assertNotIn(plain, run.call_args.args[0])
            run.reset_mock()
            blueprint.check_localizations(self.root, self.sdk, [plain])
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
