"""Check that release verification detects graph and layout changes."""
import copy
import json
import unittest

from check_atlas_release import DEFAULT_REFS, ROOT, graph_errors, parse_args


class AtlasGraphVerificationTests(unittest.TestCase):
    def test_defaults_follow_current_graph_and_allow_preview_or_ref_override(self):
        current = parse_args([])
        self.assertEqual("3.30.0c", current.version)
        self.assertEqual(DEFAULT_REFS[current.version], current.ref)
        preview = parse_args(["--version", "3.30.0-preview"])
        self.assertEqual(DEFAULT_REFS[preview.version], preview.ref)
        self.assertEqual("custom-ref", parse_args(["--ref", "custom-ref"]).ref)

    def test_default_refs_match_both_bundled_graphs(self):
        for version, ref in DEFAULT_REFS.items():
            for suffix in ("", "-ruthless"):
                path = ROOT / "src" / "Data" / "Atlas" / (version + suffix + ".json")
                graph = json.loads(path.read_text(encoding="utf-8"))
                prefix = "https://raw.githubusercontent.com/grindinggear/atlastree-export/" + ref + "/"
                self.assertTrue(graph["source"].startswith(prefix), path)
                self.assertTrue(graph["leagueSource"].startswith(prefix), path)

    def setUp(self):
        self.source = {
            "nodes": {
                "root": {"out": ["1"]},
                "1": {"name": "", "stats": [], "group": 0, "orbit": 0, "orbitIndex": 0,
                      "out": ["2", "3"], "in": ["root"], "icon": "start"},
                "2": {"name": "Choice", "stats": ["Stat"], "group": 0, "orbit": 1, "orbitIndex": 1,
                      "out": [], "in": ["1"], "icon": "choice", "isNotable": True,
                      "isMultipleChoiceVariant": True, "variantEffects": [{"effect": 7}]},
                "3": {"name": "Decoration", "stats": [], "group": 0, "orbit": 0, "orbitIndex": 0,
                      "out": [], "in": ["1"], "icon": "decoration", "isMastery": True},
            },
            "groups": {"0": {"x": 100, "y": 200, "background": {"image": "background"}}},
            "constants": {"skillsPerOrbit": [1, 4], "orbitRadii": [0, 10]},
            "points": {"totalPoints": 150}, "min_x": -1, "min_y": -2, "max_x": 3, "max_y": 4,
        }
        self.graph = {
            "start": 1, "maxPoints": 150, "bounds": [-1, -2, 3, 4],
            "nodes": {
                "1": {"id": 1, "name": "Atlas start", "stats": [], "x": 100, "y": 200,
                      "links": [2], "kind": "small", "grantedPoints": 0, "icon": "start"},
                "2": {"id": 2, "name": "Choice", "stats": ["Stat"], "x": 110, "y": 200,
                      "links": [1], "kind": "notable", "grantedPoints": 0, "icon": "choice",
                      "variantEffects": [{"effect": 7}]},
            },
            "decorations": [{"id": 3, "name": "Decoration", "stats": [], "x": 100, "y": 200,
                             "links": [1], "kind": "small", "grantedPoints": 0, "icon": "decoration"}],
            "groups": [{"x": 100, "y": 200, "background": "background"}],
        }

    def test_matching_graph_has_no_errors(self):
        self.assertEqual([], graph_errors(self.graph, self.source))

    def test_reports_changed_stats_links_variants_and_layout(self):
        changed = copy.deepcopy(self.graph)
        changed["nodes"]["2"].update(stats=["Wrong"], links=[], variantEffects=[], x=111)
        errors = graph_errors(changed, self.source)
        for field in ("stats", "links", "variantEffects", "x"):
            self.assertIn(f"node 2: {field} differs", errors)

    def test_reports_missing_nodes_and_changed_budget(self):
        changed = copy.deepcopy(self.graph)
        del changed["nodes"]["2"]
        changed["maxPoints"] = 138
        self.assertIn("allocatable node IDs differ", graph_errors(changed, self.source))
        self.assertIn("point budget differs", graph_errors(changed, self.source))

    def test_reports_empty_node_records(self):
        changed = copy.deepcopy(self.graph)
        changed["nodes"]["2"] = {}
        self.assertIn("node 2: id differs", graph_errors(changed, self.source))


if __name__ == "__main__":
    unittest.main()
