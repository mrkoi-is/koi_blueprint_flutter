"""Provenance bytes survive a real Windows-style Git checkout."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless((ROOT / 'tool/openapi/PROVENANCE.json').is_file(),
                     'Offline workspace has no active OpenAPI provenance')
class OpenApiCheckoutTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('git'), 'Git is unavailable')
    def test_autocrlf_checkout_preserves_contract_and_parser_hashes(self):
        provenance = json.loads((ROOT / 'tool/openapi/PROVENANCE.json').read_text(encoding='utf-8'))
        expected = {}
        for contract in provenance['contracts']:
            expected[contract['sourceFile']] = contract['sourceSha256']
            expected[contract['configFile']] = contract['configSha256']
            for source in (ROOT / contract['outputPackage'] / 'lib').rglob('*.dart'):
                if not source.name.endswith(('.g.dart', '.freezed.dart')):
                    expected[source.relative_to(ROOT).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
        attributes = set()
        for relative in expected:
            parent = (ROOT / relative).parent
            while parent.is_relative_to(ROOT):
                attribute = parent / '.gitattributes'
                if attribute.is_file():
                    attributes.add(attribute.relative_to(ROOT).as_posix())
                if parent == ROOT:
                    break
                parent = parent.parent
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            copied = []
            for relative in [*expected, *sorted(attributes)]:
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
