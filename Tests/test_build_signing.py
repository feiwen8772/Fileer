"""Exercise the signing arguments the build script passes to every bundled component."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildSigningTests(unittest.TestCase):
    def arguments(self, identity):
        script = (ROOT / "scripts/build.sh").read_text()
        start = script.index("sign=(")
        end = script.index("# Inside out:", start)
        result = subprocess.run(
            ["bash", "-c", script[start:end] + '\nprintf "%s\\n" "${sign[@]}"'],
            env={**os.environ, "identity": identity, "STRATA_TIMESTAMP": "0"},
            check=True, text=True, capture_output=True,
        )
        return result.stdout.splitlines()

    def test_ad_hoc_builds_can_load_their_bundled_framework(self):
        for identity in ["", "-"]:
            with self.subTest(identity=identity):
                self.assertEqual(self.arguments(identity), ["--force", "--sign", "-"])

    def test_developer_id_builds_keep_the_hardened_runtime(self):
        identity = "Developer ID Application: Build Fixture (EXAMPLE123)"
        self.assertEqual(self.arguments(identity),
                         ["--force", "--sign", identity, "--options", "runtime"])
