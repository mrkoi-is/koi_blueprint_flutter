import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import blueprint


class SDKVersionTest(unittest.TestCase):
    def setUp(self):
        temporary = self.enterContext(tempfile.TemporaryDirectory(prefix='sdk-version-'))
        self.root = Path(temporary).resolve()
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.47.2'}), encoding='utf-8')
        suffix = '.bat' if os.name == 'nt' else ''
        self.flutter = self.root / 'sdk' / 'bin' / ('flutter' + suffix)
        self.flutter.parent.mkdir(parents=True)
        self.flutter.touch()
        self.enterContext(patch.dict(os.environ, {'FLUTTER_BIN': str(self.flutter)}))
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.process = self.enterContext(patch.object(blueprint.subprocess, 'run'))

    @staticmethod
    def response(stdout='', *, returncode=0, stderr=''):
        return subprocess.CompletedProcess([], returncode, stdout=stdout, stderr=stderr)

    def assert_version_queries(self, count):
        self.assertEqual(self.process.call_count, count)
        for invocation in self.process.call_args_list:
            self.assertEqual(invocation.args[0], [str(self.flutter), '--version', '--machine'])
            self.assertEqual(invocation.kwargs['cwd'], self.root)
            self.assertEqual(invocation.kwargs['stdout'], subprocess.PIPE)
            self.assertEqual(invocation.kwargs['stderr'], subprocess.PIPE)

    def test_clean_json_requires_one_query(self):
        self.process.return_value = self.response(' {"frameworkVersion": "3.47.2"}\n')
        sdk = blueprint.SDK(self.root)
        self.assertEqual(sdk.flutter, self.flutter)
        self.assert_version_queries(1)

    def test_cold_start_bootstrap_noise_recovers_on_one_retry(self):
        self.process.side_effect = [
            self.response('Resolving dependencies...\r\nDownloading packages...\r\n'
                          'Got dependencies.\r\n{"frameworkVersion":"3.47.2"}\r\n'),
            self.response('{"frameworkVersion":"3.47.2"}\r\n'),
        ]
        blueprint.SDK(self.root)
        self.assert_version_queries(2)

    def test_repeated_invalid_json_fails_with_bounded_diagnostic(self):
        self.process.side_effect = [self.response(''), self.response('not JSON ' + 'x' * 1000)]
        with self.assertRaises(blueprint.BlueprintError) as failure:
            blueprint.SDK(self.root)
        self.assertIn('invalid JSON after one retry', str(failure.exception))
        self.assertIn('not JSON', str(failure.exception))
        self.assertLess(len(str(failure.exception)), 400)
        self.assertIsInstance(failure.exception.__cause__, json.JSONDecodeError)
        self.assert_version_queries(2)

    def test_failed_command_is_not_retried(self):
        self.process.return_value = self.response('bootstrap output', returncode=1, stderr='SDK startup failed')
        with self.assertRaisesRegex(blueprint.BlueprintError, '^SDK startup failed$'):
            blueprint.SDK(self.root)
        self.assert_version_queries(1)

    def test_valid_mismatched_version_is_not_retried(self):
        self.process.return_value = self.response('{"frameworkVersion":"3.46.0"}')
        with self.assertRaisesRegex(blueprint.BlueprintError, 'Flutter 3.47.2 required, found 3.46.0'):
            blueprint.SDK(self.root)
        self.assert_version_queries(1)

    def test_retry_still_enforces_the_pinned_version(self):
        self.process.side_effect = [
            self.response('Resolving dependencies...\n{"frameworkVersion":"3.46.0"}'),
            self.response('{"frameworkVersion":"3.46.0"}'),
        ]
        with self.assertRaisesRegex(blueprint.BlueprintError, 'Flutter 3.47.2 required, found 3.46.0'):
            blueprint.SDK(self.root)
        self.assert_version_queries(2)

    def test_valid_json_without_version_is_not_retried(self):
        self.process.return_value = self.response('{"frameworkVersion":null}')
        with self.assertRaisesRegex(blueprint.BlueprintError, 'missing a string frameworkVersion'):
            blueprint.SDK(self.root)
        self.assert_version_queries(1)


if __name__ == '__main__':
    unittest.main()
