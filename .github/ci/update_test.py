"""Tests for the update entry point."""

import unittest
from unittest import mock

import update
from update import refuse_downgrade


class TestRefuseDowngrade(unittest.TestCase):
    def test_upgrades_and_unchanged_versions_pass(self) -> None:
        refuse_downgrade("qwen-code", "0.24.1", "0.25.1")
        refuse_downgrade("qwen-code", "0.24.1", "0.24.1")
        refuse_downgrade("oh-my-opencode", "5.0.0-beta.86", "5.0.0")

    def test_downgrade_fails(self) -> None:
        with self.assertRaises(SystemExit):
            refuse_downgrade("qwen-code", "0.24.1", "0.21.2")


class TestSandboxWrap(unittest.TestCase):
    def test_drops_runtime_dir_on_read_only_root(self) -> None:
        with (
            mock.patch.object(update.sys, "platform", "linux"),
            mock.patch.dict(update.os.environ, {"UPDATE_SANDBOX": "1"}),
            mock.patch.object(update.shutil, "which", return_value="/bin/bwrap"),
            mock.patch.object(update, "sandbox_works", return_value=True),
        ):
            cmd = update.sandbox_wrap(["true"], "officecli")
        index = cmd.index("--unsetenv")
        self.assertEqual(cmd[index + 1], "XDG_RUNTIME_DIR")


if __name__ == "__main__":
    unittest.main()
