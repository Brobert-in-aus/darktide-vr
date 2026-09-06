import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("audit", ROOT / "tools/stereo/audit-ui-binding-hints.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class BindingInventory(unittest.TestCase):
    def test_comments_strings_and_nested_arguments(self):
        source = '''-- Text.localize_with_button_hint("fake", "fake")
local ignored = [=[InputUtils.input_text_for_current_input_device("View", "fake")]=]
--[==[ _get_view_input_text("fake") ]==]
local text = Text.localize_with_button_hint(
    cursor and "right_pressed" or "gamepad_confirm_pressed",
    "loc_talent_menu_tooltip_button_hint_remove_level", nil, "View",
    Localize("template", true, {value="comma, bracket)"}))
local another = InputUtils.input_text_for_current_input_device("View", alias)
'''
        found = audit.scan(source, "fixture.lua")
        self.assertEqual(len(found), 2)
        self.assertEqual(found[0]["line"], 4)
        self.assertEqual(found[0]["action_candidates"], ["right_pressed", "gamepad_confirm_pressed"])
        self.assertEqual(len(found[0]["arguments"]), 5)
        self.assertIsNone(found[0]["literal_action"])
        self.assertEqual(found[1]["action_expression"], "alias")

    def test_helper_declaration_is_not_a_call(self):
        found = audit.scan('''local function _get_view_input_text(action)
return InputUtils.input_text_for_current_input_device("View", action)
end
local text = _get_view_input_text("hotkey_inventory")
''', "fixture.lua")
        self.assertEqual(len(found), 2)
        self.assertEqual(found[1]["literal_action"], "hotkey_inventory")

    def test_missing_cases_are_not_reported_fixed(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            ui = root / "scripts/ui"
            ui.mkdir(parents=True)
            (ui / "fixture.lua").write_text('Text.localize_with_button_hint("back", "Back")')
            report = audit.inventory(root)
            self.assertEqual(report["summary"]["calls"], 1)
            self.assertTrue(all(not case["found"] for case in report["user_acceptance_cases"].values()))
            self.assertEqual(report["calls"][0]["controller_status"], "route_and_live_check_required")

    def test_shared_helpers_and_method_declarations(self):
        found = audit.scan('''function ViewElementWithLongName:_get_input_text(action)
return self:_localized_input_text(action)
end
local left = _get_input_text("navigate_primary_left_pressed")
local tab = self:_get_input_text(input_action_left)
local tutorial = self:_get_localized_input_text("interact")
''', "fixture.lua")
        self.assertEqual(len(found), 4)
        self.assertEqual([r["line"] for r in found], [2, 4, 5, 6])
        self.assertTrue(all(r["kind"] == "hint_helper" for r in found))
        self.assertEqual(found[1]["literal_action"], "navigate_primary_left_pressed")
        self.assertEqual(found[2]["resolution"], "dynamic_review_required")

    def test_raw_key_data_is_not_a_gameplay_action(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            ui = root / "scripts/ui"
            ui.mkdir(parents=True)
            (ui / "fixture.lua").write_text('''
local preview = InputUtils.localized_string_from_key_info(value)
local cancel = InputUtils.key_axis_locale("escape")
local hint = self:_localized_input_text(action)
''')
            report = audit.inventory(root)
            self.assertEqual(report["summary"]["calls"], 3)
            self.assertEqual(report["summary"]["dynamic"], 1)
            self.assertEqual(report["summary"]["by_kind"]["raw_key_formatter"], 2)
            for record in report["calls"][:2]:
                self.assertIsNone(record["action_expression"])
                self.assertIsNone(record["literal_action"])
                self.assertEqual(record["action_candidates"], [])
                self.assertEqual(record["resolution"], "key_data_not_action")
                self.assertEqual(record["controller_status"], "preserve_device_key_text_review")
            self.assertEqual(report["calls"][1]["key_expression"], '"escape"')

    def test_empty_source_is_an_error(self):
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaises(ValueError):
                audit.inventory(Path(name))


if __name__ == "__main__":
    unittest.main()
