#!/usr/bin/env python3
"""Tests for the report-issue fingerprint helper.

Same house style as scripts/test_hooks.py: stdlib only, a failures list, a non-zero exit, and
positive controls that matter more than the negative ones.

TWO DIRECTIONS, AND THE SECOND IS THE ONE PEOPLE FORGET.

  MERGE   the same defect reported by two different people must produce the SAME fingerprint,
          or the dedup search misses and the tracker fills with duplicates.
  SPLIT   two genuinely DIFFERENT defects must produce DIFFERENT fingerprints, or the second
          report is filed as a "+1" comment on an unrelated issue and is lost for good.

A normaliser that only satisfies MERGE is trivially achievable -- return a constant -- and is
strictly worse than no normaliser at all. Every MERGE case below is therefore paired with a
SPLIT case that the constant-returning version would fail.

    python3 scripts/test_issue_fingerprint.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import issue_fingerprint as f  # noqa: E402

failures: list[str] = []


def check(name: str, got, want) -> None:
    if got == want:
        print(f"  ok    {name}")
    else:
        failures.append(name)
        print(f"  FAIL  {name}")
        print(f"          got  {got!r}")
        print(f"          want {want!r}")


def merge(name: str, a: str, b: str) -> None:
    """Two reports of one defect must normalise to the same thing."""
    na, nb = f.normalize(a), f.normalize(b)
    if na == nb:
        print(f"  ok    MERGE {name}  -> {na!r}")
    else:
        failures.append(f"MERGE {name}")
        print(f"  FAIL  MERGE {name}")
        print(f"          a -> {na!r}")
        print(f"          b -> {nb!r}")


def split(name: str, a: str, b: str) -> None:
    """Two different defects must NOT collapse onto one fingerprint."""
    na, nb = f.normalize(a), f.normalize(b)
    if na != nb:
        print(f"  ok    SPLIT {name}")
    else:
        failures.append(f"SPLIT {name}")
        print(f"  FAIL  SPLIT {name}  both -> {na!r}  (a real report would be lost as a +1)")


print("\nMERGE -- the same defect from two reporters\n")

merge("project class name",
      "NO_TESTS_FOUND for Demo.Tests.OrderToVendor",
      "NO_TESTS_FOUND for MyApp.Tests.CensoRouting")
merge("namespace",
      "ExecuteUpdateParmArray bound nothing in namespace=APP",
      'ExecuteUpdateParmArray bound nothing in namespace="FHIRTEST"')
merge("ISO timestamp",
      "queue stalled at 2026-09-18T07:12:00Z",
      "queue stalled at 2026-01-02 23:59:59")
merge("HL7/IRIS timestamp",
      "DocType unresolved for message 20260918071200",
      "DocType unresolved for message 20250101235959")
merge("message header id",
      "trace empty for session 148372",
      "trace empty for session 99001122")
merge("absolute path",
      "RecordMap service saw no file at /data/censo/in/",
      "RecordMap service saw no file at /srv/feeds/adt/drop/")
merge("all four volatiles at once",
      "iris_test NO_TESTS_FOUND in namespace APP for Demo.Tests.Foo id 148372 at 2026-09-18T07:12:00Z",
      "iris_test NO_TESTS_FOUND in namespace PROD for Acme.Tests.Bar id 90887766 at 2026-02-03T11:00:00Z")

print("\nSPLIT -- different defects must stay apart\n")

# Each of these would pass MERGE under a constant-returning normaliser. They are the reason
# the rules above are the narrow form.
split("different error codes",
      "iris_test NO_TESTS_FOUND for Demo.Tests.Foo",
      "iris_test COMPILE_FAILED for Demo.Tests.Foo")
split("different platform class -- NOT volatile",
      "EnsLib.HL7.Service.FileService hand-parses rows",
      "EnsLib.RecordMap.Service.FileService hand-parses rows")
split("different tool",
      "iris_production returned an empty item list",
      "iris_interop_query returned an empty item list")
split("different symptom, same class",
      "Demo.BS.Censo started and consumed nothing",
      "Demo.BS.Censo raised <UNDEFINED> on every message")
split("different CR criterion",
      "CR-2 file service hand-parses instead of RecordMap",
      "CR-5 router has no business rule")

print("\nPROPERTIES\n")

# Idempotence. A fingerprint that changes when re-normalised cannot be searched for: the
# second reporter would produce a different title from the one already in the tracker.
for probe in (
    "NO_TESTS_FOUND in namespace=APP for Demo.Tests.Foo id 148372 at 2026-09-18T07:12:00Z",
    "no volatile bits here at all",
    "path /data/censo/in/ and class Acme.BS.Feed",
):
    once = f.normalize(probe)
    check(f"idempotent: {probe[:38]!r}...", f.normalize(once), once)

# Platform roots survive verbatim -- they ARE the signature.
check("platform Ens.* kept",
      f.normalize("Ens.MessageHeader row missing"), "Ens.MessageHeader row missing")
check("platform %-class kept",
      f.normalize("%UnitTest.TestProduction needs PRODUCTION"),
      "%UnitTest.TestProduction needs PRODUCTION")
check("platform HS.* kept",
      f.normalize("HS.FHIRServer.Interop.Service not found"),
      "HS.FHIRServer.Interop.Service not found")

# KNOWN LIMIT, asserted so that it stays known rather than being rediscovered as a bug: a bare
# namespace name with no "namespace" keyword survives. The alternative -- treating any uppercase
# word as a namespace -- would also mask NO_TESTS_FOUND and PRODUCTION, i.e. it would merge
# unrelated defects. If this assertion ever starts failing, someone widened the rule; make sure
# they widened it deliberately.
check("bare namespace NOT masked (documented limit)",
      f.normalize("NO_TESTS_FOUND in APP for Demo.Tests.Foo"),
      "NO_TESTS_FOUND in APP for <class>")
check("error codes survive (what widening the ns rule would break)",
      f.normalize("NO_TESTS_FOUND and PRODUCTION both matter"),
      "NO_TESTS_FOUND and PRODUCTION both matter")

# A filename is not a class reference.
check("filename not masked",
      f.normalize("validate_examples.py skipped it"), "validate_examples.py skipped it")

# Title and search term are built from the same pair, so they cannot drift.
check("fingerprint title",
      f.fingerprint("MCP", "iris_test", "NO_TESTS_FOUND in namespace=APP for Demo.Tests.Foo"),
      "[mcp:iris_test] NO_TESTS_FOUND in namespace <ns> for <class>")
check("search term matches the title's key",
      f.search_term("mcp", "iris_test"), "in:title mcp:iris_test")
check("conformance form",
      f.fingerprint("conformance", "CR-2", "file BS hand-parses rows instead of RecordMap"),
      "[conformance:CR-2] file BS hand-parses rows instead of RecordMap")

# The search term must actually occur in the title it is meant to find -- the one assertion
# that ties the two functions together rather than testing each in isolation.
title = f.fingerprint("mcp", "iris_test", "anything at all")
key_part = f.search_term("mcp", "iris_test").replace("in:title ", "")
check("search term is a substring of the title", key_part in title, True)

print(f"\n{len(failures)} failure(s)\n")
if failures:
    for name in failures:
        print(f"  - {name}")
sys.exit(1 if failures else 0)
