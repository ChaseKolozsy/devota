import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SERVER_PATH = Path(__file__).with_name("devota_server.py")
SPEC = importlib.util.spec_from_file_location("devota_server", SERVER_PATH)
devota_server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(devota_server)


def seed_macros(root: Path) -> None:
    store = {
        "format": devota_server.MACRO_STORE_FORMAT,
        "version": devota_server.MACRO_STORE_VERSION,
        "updatedAt": "2026-01-01T00:00:00Z",
        "macros": [
            {
                "id": "m1",
                "name": "TL -> BLD",
                "priority": 1,
                "steps": [
                    {
                        "id": "s1",
                        "type": "shell",
                        "value": "The parent runs GPT-6.1 Sol MEDIUM. "
                        "Dispatch (model=gpt-6.1-sol, reasoning_effort=medium)",
                        "delaySeconds": 0,
                    }
                ],
            },
            {
                "id": "m2",
                "name": "Other",
                "priority": 0,
                "steps": [
                    {"id": "s2", "type": "shell", "value": "echo hello", "delaySeconds": 0}
                ],
            },
        ],
        "usageCounts": {},
    }
    path = devota_server.macros_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(store), encoding="utf-8")


class MacroFindReplaceTests(unittest.TestCase):
    def test_builtin_presets_include_both_model_toggles(self):
        result = devota_server.list_find_replace_presets(Path("/nonexistent"))
        labels = [p["label"] for p in result["presets"]]
        self.assertIn("Model → GPT-6.1 Sol", labels)
        self.assertIn("Model → Muse Wonder 1.0", labels)

    def test_model_swap_registers_preset_and_applies(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed_macros(root)
            result = devota_server.swap_macro_model(
                root,
                {
                    "from": {"name": "GPT-6.1 Sol", "slug": "gpt-6.1-sol"},
                    "to": {"name": "Gemini 3 Pro", "slug": "gemini-3-pro"},
                    "apply": True,
                },
            )
            self.assertEqual(result["replacements"], 2)
            self.assertEqual(result["affected_macros"][0]["name"], "TL -> BLD")
            self.assertEqual(result["preset"]["label"], "Model → Gemini 3 Pro")
            store = devota_server.read_macros_store(root)
            value = store["macros"][0]["steps"][0]["value"]
            self.assertIn("Gemini 3 Pro", value)
            self.assertIn("model=gemini-3-pro", value)
            # The new swapper is now listed for the app and other agents.
            labels = [
                p["label"]
                for p in devota_server.list_find_replace_presets(root)["presets"]
            ]
            self.assertIn("Model → Gemini 3 Pro", labels)

    def test_apply_by_preset_label_and_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed_macros(root)
            result = devota_server.apply_macro_find_replace(
                root, {"preset": "Model → Muse Wonder 1.0", "dry_run": True}
            )
            self.assertEqual(result["replacements"], 2)
            store = devota_server.read_macros_store(root)
            self.assertIn(
                "gpt-6.1-sol", store["macros"][0]["steps"][0]["value"]
            )

    def test_custom_pairs_and_macro_filter(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed_macros(root)
            result = devota_server.apply_macro_find_replace(
                root,
                {
                    "pairs": [{"find": "hello", "replace": "world"}],
                    "macro_names": ["Other"],
                },
            )
            self.assertEqual(result["replacements"], 1)
            store = devota_server.read_macros_store(root)
            self.assertIn("echo world", store["macros"][1]["steps"][0]["value"])

    def test_add_preset_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, "find"):
                devota_server.add_find_replace_preset(
                    root, {"label": "Bad", "pairs": [{"find": "", "replace": "x"}]}
                )
            result = devota_server.add_find_replace_preset(
                root,
                {
                    "label": "Model → Gemini 3 Pro",
                    "pairs": [
                        {"find": "gpt-6.1-sol", "replace": "gemini-3-pro"},
                    ],
                },
            )
            self.assertEqual(result["preset"]["label"], "Model → Gemini 3 Pro")
            self.assertFalse(result["preset"]["builtin"])


if __name__ == "__main__":
    unittest.main()
