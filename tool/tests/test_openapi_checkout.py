"""Provenance bytes survive a real Windows-style Git checkout."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class OpenApiCheckoutTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('git'), 'Git is unavailable')
    def test_autocrlf_checkout_preserves_contract_and_parser_hashes(self):
        provenance = json.loads((ROOT / 'tool/openapi/PROVENANCE.json').read_text(encoding='utf-8'))
        expected = {}
        for contract in provenance['contracts']:
            expected[contract['sourceFile']] = contract['sourceSha256']
            expected[contract['configFile']] = contract['configSha256']
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            copied = []
            for relative in [*expected, 'tool/openapi/.gitattributes', 'tool/koi_swagger_parser/.gitattributes']:
                target = checkout / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
                copied.append(target)
            def git(*args):
                subprocess.run(['git', '-c', 'core.autocrlf=true', *args], cwd=checkout,
                               check=True, capture_output=True)
            git('init', '--quiet')
            git('add', '.')
            for target in copied:
                target.unlink()
            git('checkout-index', '--all', '--force')
            for relative, digest in expected.items():
                with self.subTest(path=relative):
                    data = (checkout / relative).read_bytes()
                    self.assertNotIn(b'\r\n', data)
                    self.assertEqual(hashlib.sha256(data).hexdigest(), digest)


if __name__ == '__main__':
    unittest.main()
