"""Exercise the exact promotion gate run by Mobile CI, without GitHub access."""
import os
from pathlib import Path
import subprocess
import textwrap
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/ci.yml"
JOB = WORKFLOW.read_text().split("  staging-promotion:\n", 1)[1].split(
    "  analyze-and-test:\n", 1
)[0]
SCRIPT = textwrap.dedent(JOB.split("        run: |\n", 1)[1])
REPOSITORY = "Gilmore-Tech/MyShop-mobile"


class PromotionPolicyTest(unittest.TestCase):
    def check_policy(self, expected, *, base="main", head="staging",
                     repository=REPOSITORY, event="pull_request"):
        result = subprocess.run(
            ["bash", "-c", SCRIPT],
            env={**os.environ, "GITHUB_EVENT_NAME": event,
                 "GITHUB_REPOSITORY": REPOSITORY, "BASE_BRANCH": base,
                 "HEAD_BRANCH": head, "HEAD_REPOSITORY": repository},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_allows_staging_promotion(self):
        self.check_policy(0)

    def test_rejects_feature_fix_and_release_shortcuts(self):
        for head in ("feature/new-ui", "fix/tracking", "release/new-version", "main", ""):
            with self.subTest(head=head):
                self.check_policy(1, head=head)

    def test_rejects_a_forks_staging_branch(self):
        self.check_policy(1, repository="another-owner/MyShop-mobile")
        self.check_policy(1, repository="")

    def test_allows_changes_and_main_syncs_into_staging(self):
        for head in ("feature/new-ui", "release/new-version", "main"):
            with self.subTest(head=head):
                self.check_policy(0, base="staging", head=head)

    def test_push_ci_still_runs(self):
        self.check_policy(0, event="push", base="", head="", repository="")


if __name__ == "__main__":
    unittest.main()
