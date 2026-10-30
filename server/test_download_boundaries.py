import tempfile
import unittest
from pathlib import Path

from devota_server import resolve_download_target


class DownloadBoundariesTest(unittest.TestCase):
    def test_apks_are_limited_to_each_apps_registered_build_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            cradle, other = repo / 'cradle', repo / 'other'
            manifest = {'apps': [
                {'id': 'cradle', 'root': {'absolute': cradle}, 'buildDirs': [
                    {'absolute': cradle / 'dist/on'}, {'absolute': cradle / 'dist/off'}]},
                {'id': 'other', 'root': {'absolute': other}, 'buildDirs': [
                    {'absolute': other / 'build'}]},
            ]}
            for path in ('dist/on/a.apk', 'dist/off/b.apk'):
                self.assertEqual(resolve_download_target(repo, manifest, f'apps/cradle/{path}')[0], cradle / path)
            self.assertEqual(resolve_download_target(repo, manifest, 'apps/other/build/c.apk')[0], other / 'build/c.apk')
            for path in ('build/old.apk', 'dist/old/old.apk'):
                with self.assertRaises(FileNotFoundError):
                    resolve_download_target(repo, manifest, f'apps/cradle/{path}')
            with self.assertRaises(PermissionError):
                resolve_download_target(repo, manifest, 'apps/cradle/../other/build/c.apk')
            self.assertEqual(resolve_download_target(repo, manifest, 'apps/cradle/readme.txt')[0], cradle / 'readme.txt')


if __name__ == '__main__':
    unittest.main()
