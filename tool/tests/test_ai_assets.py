import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("check_ai_assets", Path(__file__).parents[1] / "check_ai_assets.py")
CHECKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECKER
SPEC.loader.exec_module(CHECKER)


class AiAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="koi-ai-assets-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.canonical = "---\nname: example\ndescription: Create a tested example.\n---\n\nRead [contract](references/contract.md).\n"
        self.write(".agents/skills/example/SKILL.md", self.canonical)
        self.write(".agents/skills/example/references/contract.md", "# Contract\n")
        self.write(".agents/skills/index.yaml", "skills:\n  - id: example\n    description: Create a tested example.\n    keywords: [example, test]\n    path: .agents/skills/example/SKILL.md\n")
        self.write("AGENTS.md", "Read `docs/ai-quickstart.md` and `.agents/skills/index.yaml`.\n\n## 任务路由\n\n| 任务 | Skill |\n| --- | --- |\n| Example | `example` |\n")
        self.write("CLAUDE.md", CHECKER.CLAUDE_ADAPTER)
        self.write("docs/ai-quickstart.md", "Read `AGENTS.md` and `.agents/skills/index.yaml`.\n")
        self.write(".cursor/rules/koi-workspace.mdc", CHECKER.CURSOR_ADAPTER)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def rules(self):
        return {issue.rule for issue in CHECKER.validate_assets(self.root)}

    def test_valid_discovery_graph(self):
        self.assertEqual(CHECKER.validate_assets(self.root), [])

    def test_unknown_and_duplicate_index_fields_fail(self):
        path = self.root / ".agents/skills/index.yaml"
        path.write_text(path.read_text() + "    surprise: value\n")
        self.assertIn("AI_INDEX", self.rules())

    def test_unindexed_canonical_skill_fails(self):
        self.write(".agents/skills/orphan/SKILL.md", "---\nname: orphan\ndescription: Orphan.\n---\n")
        self.assertIn("AI_INDEX", self.rules())

    def test_missing_indexed_skill_fails(self):
        (self.root / ".agents/skills/example/SKILL.md").unlink()
        self.assertIn("AI_INDEX", self.rules())

    def test_parallel_agent_directory_fails(self):
        self.write(".agent/skills/example/SKILL.md", self.canonical)
        self.assertIn("AI_LAYOUT", self.rules())

    def test_noncanonical_index_path_fails(self):
        path = self.root / ".agents/skills/index.yaml"
        path.write_text(path.read_text().replace(".agents/skills/example/SKILL.md", ".agent/skills/example/SKILL.md"), encoding="utf-8")
        self.assertIn("AI_INDEX", self.rules())

    def test_skill_symlink_fails(self):
        skill = self.root / ".agents/skills/example/SKILL.md"
        real = self.root / "skill-body.md"
        real.write_text(skill.read_text(), encoding="utf-8")
        skill.unlink()
        skill.symlink_to(real)
        self.assertIn("AI_LAYOUT", self.rules())

    def test_metadata_drift_fails(self):
        self.write(".agents/skills/example/SKILL.md", self.canonical.replace("Create a tested example.", "Changed description."))
        self.assertIn("AI_METADATA", self.rules())

    def test_broken_required_reference_fails(self):
        (self.root / ".agents/skills/example/references/contract.md").unlink()
        self.assertIn("AI_REFERENCE", self.rules())

    def test_reference_outside_repository_fails(self):
        self.write("docs/outside.md", "[Outside](../../outside.md)\n")
        self.assertIn("AI_REFERENCE", self.rules())

    def test_external_links_and_template_documentation_are_not_local_files(self):
        self.write("docs/example.md", "[Docs](https://example.com/reference)\n`apps/<app>/lib/`\n```dart\nconst example = '[ignore](missing.dart)';\n```\n")
        self.assertEqual(self.rules(), set())

    def test_required_link_between_fences_is_not_removed(self):
        self.write("docs/two-examples.md", "```dart\nconst one = 1;\n```\n[Required contract](missing-required-contract.md)\n```dart\nconst two = 2;\n```\n")
        self.assertIn("AI_REFERENCE", self.rules())

    def test_tilde_and_long_fences_keep_valid_prose_links(self):
        self.write("docs/contract.md", "# Contract\n")
        self.write("docs/fences.md", "~~~~dart\n[Ignored](missing-inside.md)\n~~~\n~~~~\n[Contract](contract.md)\n```dart\n[Also ignored](missing-inside.md)\n```\n")
        self.assertNotIn("AI_REFERENCE", self.rules())

    def test_machine_specific_source_reference_fails(self):
        self.write("docs/outside.md", "[Source](/Users/example/private/source.dart)\n")
        self.assertIn("AI_PORTABLE", self.rules())

    def test_historical_and_research_notes_are_not_active_ai_contracts(self):
        for folder in ("research", "validation"):
            self.write(f"docs/{folder}/note.md", "[Past source](/Users/example/old.dart)\n")
        self.assertEqual(self.rules(), set())

    def test_root_design_contract_references_are_checked(self):
        self.write("DESIGN.md", "[Missing design source](docs/missing-design.md)\n")
        self.assertIn("AI_REFERENCE", self.rules())
        self.write("docs/missing-design.md", "# Design source\n")
        self.assertEqual(self.rules(), set())

    def test_entrypoints_must_route_to_canonical_rules(self):
        self.write("CLAUDE.md", "Use another document.\n")
        self.assertIn("AI_ROUTING", self.rules())

    def test_entrypoint_cannot_append_another_architecture(self):
        self.write("CLAUDE.md", CHECKER.CLAUDE_ADAPTER + "Use GetX for new state.\n")
        self.assertIn("AI_ROUTING", self.rules())

    def test_cursor_entrypoint_cannot_append_another_architecture(self):
        self.write(".cursor/rules/koi-workspace.mdc", CHECKER.CURSOR_ADAPTER + "Use GetX for new state.\n")
        self.assertIn("AI_ROUTING", self.rules())

    def test_agents_task_routing_must_match_index(self):
        path = self.root / "AGENTS.md"
        path.write_text(path.read_text().replace("`example`", "`unknown`"), encoding="utf-8")
        self.assertIn("AI_ROUTING", self.rules())

    def test_generator_must_keep_executable_source_and_test_inputs(self):
        self.write("blueprint.py", "# Fixture generator marker\n")
        self.assertIn("AI_TEMPLATE", self.rules())
        for sample in ("starter_app", "feature_lab", "minimal_module", "workbench_app", "ui_lab"):
            self.write(f"examples/{sample}/pubspec.yaml", f"name: {sample}\n")
            self.write(f"examples/{sample}/lib/main.dart", "void main() {}\n")
            self.write(f"examples/{sample}/test/main_test.dart", "void main() {}\n")
        for feature in ("welcome", "catalog", "draft"):
            self.write(f"examples/feature_lab/lib/features/{feature}/source.dart", "// fixture\n")
            self.write(f"examples/feature_lab/test/features/{feature}/source_test.dart", "// fixture\n")
        self.assertNotIn("AI_TEMPLATE", self.rules())

    def test_unexpanded_generation_placeholder_in_source_fails(self):
        self.write("apps/demo/lib/main.dart", "const app = '{{project_name}}';\n")
        self.assertIn("AI_TEMPLATE", self.rules())


if __name__ == "__main__":
    unittest.main()
