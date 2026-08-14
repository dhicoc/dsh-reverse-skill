import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "review_case.py"
SPEC = importlib.util.spec_from_file_location("review_case", SCRIPT_PATH)
REVIEW_CASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REVIEW_CASE)


class ReviewCaseTests(unittest.TestCase):
    def write_case(self, root, include_report=True):
        evidence_dir = root / "evidence"
        report_dir = root / "report"
        evidence_dir.mkdir(parents=True)
        if include_report:
            report_dir.mkdir(parents=True)

        artifact = evidence_dir / "sample.bin"
        artifact.write_bytes(b"reverse-skill case review fixture")
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()

        (root / "scope.md").write_text(
            """# Case Scope

## auth
- status: granted
- basis: lab_only

## in_scope
- assets:
  - sample.bin

## network_profile
- mode: offline

## signoff
- ready_for_act: true
""",
            encoding="utf-8",
        )
        (root / "workitems.md").write_text(
            """# Work Items

| ID | title | role | targets | surface | status | evidence | notes |
|----|-------|------|---------|---------|--------|----------|-------|
| WI-001 | Recover sample behavior | cre | sample.bin | binary | done | E-001 | |
""",
            encoding="utf-8",
        )
        (root / "timeline.md").write_text(
            """# Timeline (append-only)

## 2026-08-02T00:00:00Z | cre | static
- action: inspect local sample
- evidence_ids: [E-001]
""",
            encoding="utf-8",
        )
        (evidence_dir / "E-001.md").write_text(
            """### E-001
- title: Sample hash
- severity: info
- status: observed
- content_hash: sha256:%s
- artifact_path: evidence/sample.bin
- linked_workitem: WI-001
- repro_command: sha256sum evidence/sample.bin
- raw_excerpt: |
    fixture
""" % digest,
            encoding="utf-8",
        )
        if include_report:
            (report_dir / "analysis.md").write_text(
                """### F-001
- title: Sample behavior recovered
- severity: info
- category: reverse_algo
- status: validated
- evidence_ids: [E-001]
- location: sample.bin:0x10
- impact: n/a
- confidence: high
- repro_steps: |
    1. Run the fixture command.
- remediation: n/a

### P-001
- title: Static recovery path
- path_type: callflow
- start: sample.bin
- goal: recovered behavior
- steps: |
    1. Hash the sample with E-001.
- residual_risks: n/a
""",
                encoding="utf-8",
            )

    def test_valid_case_passes_with_hash_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            result = REVIEW_CASE.review_case(root, verify_hashes=True)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["summary"]["evidence"], 1)
            self.assertEqual(result["summary"]["findings"], 1)
            self.assertEqual(result["summary"]["paths"], 1)

    def test_unknown_report_evidence_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            report = root / "report" / "analysis.md"
            report.write_text(report.read_text(encoding="utf-8").replace("E-001", "E-999"), encoding="utf-8")
            result = REVIEW_CASE.review_case(root)
            self.assertEqual(result["status"], "FAIL")
            self.assertTrue(any(item["code"] == "reference.unknown_evidence" for item in result["issues"]))

    def test_hash_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            (root / "evidence" / "sample.bin").write_bytes(b"changed fixture")
            result = REVIEW_CASE.review_case(root, verify_hashes=True)
            self.assertEqual(result["status"], "FAIL")
            self.assertTrue(any(item["code"] == "artifact.hash_mismatch" for item in result["issues"]))

    def test_markdown_output_contains_traceability_table(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            result = REVIEW_CASE.review_case(root)
            output = REVIEW_CASE.render_markdown(result)
            self.assertIn("## Traceability", output)
            self.assertIn("| E-001 | 1 | 1 | 2 |", output)

    def test_documented_offline_evidence_does_not_require_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            (root / "evidence" / "E-002.md").write_text(
                """### E-002
- title: Offline observation
- severity: info
- status: observed
- content_hash: n/a
- repro_command: n/a
- notes: offline-only observation
""",
                encoding="utf-8",
            )
            result = REVIEW_CASE.review_case(root)
            self.assertFalse(any(item["code"] == "evidence.repro_missing" for item in result["issues"]))

    def test_strict_mode_fails_when_report_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root, include_report=False)
            result = REVIEW_CASE.review_case(root, strict=True)
            self.assertEqual(result["status"], "FAIL")
            self.assertTrue(any(item["code"] == "report.missing" for item in result["issues"]))

    def test_completed_workitem_status_matches_current_case_convention(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            workitems = root / "workitems.md"
            workitems.write_text(
                workitems.read_text(encoding="utf-8").replace("| done |", "| completed |"),
                encoding="utf-8",
            )
            result = REVIEW_CASE.review_case(root)
            self.assertFalse(any(item["code"] == "workitem.status" for item in result["issues"]))

    def test_windows_drive_path_is_parsed_as_scope_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_case(root)
            scope = root / "scope.md"
            scope.write_text(
                scope.read_text(encoding="utf-8")
                .replace("  - sample.bin", r"  - D:\reverse-skill")
                .replace("- mode: offline", "- mode: lab_only"),
                encoding="utf-8",
            )
            result = REVIEW_CASE.review_case(root)
            self.assertEqual(result["scope"]["assets"], [r"D:\reverse-skill"])
            self.assertFalse(any(item["code"] == "scope.assets_missing" for item in result["issues"]))


if __name__ == "__main__":
    unittest.main()
