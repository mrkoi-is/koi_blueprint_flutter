import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / 'create_feature.py'


class CreateFeatureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'apps' / 'demo'
        self.app.mkdir(parents=True)
        (self.app / 'pubspec.yaml').write_text('name: demo\n')

    def run_generator(self, name, *options):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.app), name, *options],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_valid_name_creates_feature_inside_app(self):
        result = self.run_generator('user_profile')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            (self.app / 'lib/features/user_profile/presentation/screens/.gitkeep').is_file()
        )

    def test_presentation_only_avoids_empty_data_and_domain_layers(self):
        result = self.run_generator('welcome', '--presentation-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        feature = self.app / 'lib/features/welcome'
        self.assertTrue((feature / 'presentation/screens/.gitkeep').is_file())
        self.assertFalse((feature / 'data').exists())
        self.assertFalse((feature / 'domain').exists())

    def test_invalid_names_do_not_create_directories(self):
        for name in ('', '../../../escaped', str(self.root / 'elsewhere')):
            with self.subTest(name=name):
                result = self.run_generator(name)
                self.assertEqual(result.returncode, 2)
                self.assertFalse((self.app / 'lib').exists())
                self.assertFalse((self.root / 'elsewhere').exists())


if __name__ == '__main__':
    unittest.main()
