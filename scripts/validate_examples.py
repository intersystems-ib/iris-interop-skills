#!/usr/bin/env python3
"""Validation suite for the BestPractices example bank.

Wrong examples are worse than no examples: they are what an agent copies, and a
broken one propagates into every production built from it, silently. Before this
existed, nobody had ever run a compiler over the bank -- 10 of 18 files did not
compile, across seven releases.

Two tiers:

  Tier 1  structural   no IRIS, ~1s. Runs in CI on every push.
  Tier 2  compile      needs a live IRIS. Stages every class, compiles it,
                       compares against the recorded baseline, cleans up.

    python3 scripts/validate_examples.py              # tier 1
    python3 scripts/validate_examples.py --compile    # tier 1 + tier 2

Exit code is non-zero if any check fails, so it works as a gate.

CALIBRATION NOTE -- read before adding a check. A noisy gate gets muted, and a
muted gate is worse than none. Every rule here is deliberately the narrow form:

  * C5 asserts no class name *ends* in a Tipo, rather than requiring every class
    to carry one. `Example.CDA.ClinicalDocument` and `Example.Vendor.WSC.SAPClient`
    are legitimately Tipo-less; `Example.MyService.BS` was the real defect (#91).
  * C6 ignores comment lines. The bank *teaches* several of these tokens as
    anti-patterns, and the anonymised `<initials><date>` marker is a documented
    convention (S6.1.7), not leftover vendor cruft. A first draft of this check
    flagged 3 files and was wrong all 3 times.

Tune a new rule against the whole corpus before committing it.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BANK = REPO / "BestPractices" / "examples"
DOC = REPO / "BestPractices" / "BestPractices_Interop_IRIS.md"
README = BANK / "README.md"
BASELINE = Path(__file__).resolve().parent / "examples_baseline.json"
EXTERNAL = REPO / "BestPractices" / "external"
EXTERNAL_BASELINE = Path(__file__).resolve().parent / "external_baseline.json"

# Settings whose VALUE names another item in the same production. Shared by C8 (the bank) and
# dangling_item_refs (the vendored tree) so the two cannot drift apart.
#
# OperationDuplexName is NOT a platform setting: measured, ZERO classes on the instance declare such a
# property. It is the DICOM workshop's own convention -- its BPs carry
# `Parameter SETTINGS = "OperationDuplexName"` plus a matching Property -- and `dicom:148` documents it
# as the Process-to-Operation direction. A project-defined setting still names an item, so a dangling
# value fails the same way, and leaving it unchecked is how the vendored tree's broken STOW-RS round trip
# stayed invisible: the handler reaches its operation, and the operation's return path names nothing.
ITEM_REF_SETTINGS = (
    "TargetConfigNames",
    "BadMessageHandler",
    "JGService",
    "DuplexTargetConfigName",
    "OperationDuplexName",
)

ARTEFACT_SUFFIXES = (".cls", ".xml", ".sh")
TIPOS = ("BS", "BP", "BO", "DT", "DTS", "RUL", "MSG", "DAT", "ADP", "UTL", "HL7")

# Tokens the audit proved wrong. Each entry: (regex, why).
# Matched only against non-comment lines -- see the calibration note above.
BANNED = [
    (r"\bAs\s+%SOAP\.Security\s*$", "%SOAP.Security is a package, not a class -- use %SOAP.Security.Header"),
    (r"\bEnsLib\.Email\.", "no such package -- it is EnsLib.EMail (capital M)"),
    (r"\bSendAlertOnError\b", "not a real property -- the Ens.Host setting is AlertOnError"),
    (r'ADAPTER\s*=\s*"EnsLib\.RecordMap\.Service\.', "that is a Business Service, not an adapter -- Extend it instead"),
    (r"\$SYSTEM\.Semaphore\.(Signal|Wait)\b", "%SYSTEM.Semaphore has no Signal/Wait -- use Increment/Decrement on an instance"),
    (r"\b%SYS\.TaskSuper\b", "internal-only superclass with no OnTask -- subclass %SYS.Task.Definition"),
    (r"\bNumDaysToKeep\b", "no such property anywhere -- the purge task setting is NumberOfDaysToKeep"),
    (r"\bEns\.Rule\.Definition\b.*\bExtends\b.*\bRule\b\.", "rule classes are <Pkg>.RUL.<Name>"),
    (r"[A-Z]:\\\\|[A-Z]:\\", "hardcoded absolute Windows path -- parametrise it as a Setting"),
    (r"\bINTEGRACIONS>", "leftover namespace prompt from a customer transcript"),
]

COMMENT_PREFIXES = ("///", "//", "#", "<!--", "rem ")


class Report:
    def __init__(self) -> None:
        self.failures: list[tuple[str, str]] = []
        self.checks_run = 0

    def check(self, cid: str, title: str, bad: list[str]) -> None:
        self.checks_run += 1
        if bad:
            for item in bad:
                self.failures.append((cid, item))
            print(f"  FAIL  {cid}  {title}  ({len(bad)})")
            for item in bad[:12]:
                print(f"          {item}")
            if len(bad) > 12:
                print(f"          ... and {len(bad) - 12} more")
        else:
            print(f"  ok    {cid}  {title}")

    def done(self, tier: str) -> bool:
        if self.failures:
            print(f"\n{tier}: {len(self.failures)} problem(s) across {self.checks_run} checks\n")
            return False
        print(f"\n{tier}: all {self.checks_run} checks pass\n")
        return True


def artefacts() -> list[Path]:
    return sorted(
        p for p in BANK.rglob("*")
        if p.suffix in ARTEFACT_SUFFIXES or p.name.endswith(".cls.xml")
    )


# A test is EVIDENCE that a subject example works; it is not a template anyone copies to build a
# component. Requiring its own pointer would add 52 lines of noise to SKILL.md bodies that S7 caps at
# 500 lines, and deriving the subject automatically is not possible: measured, only 20 of the 52
# have a subject recoverable from the filename (`tdd-dicom-mwl-date.cls` tests
# `dicom-mwl-date-functionset.cls` -- no prefix relation). So they are exempt by convention, and the
# convention is stated here rather than hidden in a regex.
TEST_TIER = ("tdd-", "fixture")


def unpointed_subjects() -> list[str]:
    """Bank subject examples that NO skill markdown reaches by a full ${CLAUDE_PLUGIN_ROOT} path.

    ONE function, called by C20 and by --update-baseline both. The check and its baseline computed
    separately is how a ratchet silently measures two different things.

    STRICT, not "the basename is mentioned somewhere", and the difference is the whole point: a model
    cannot open `msg-censo-validated.cls` from a bare filename. Measured, strict costs 9 files more
    than loose -- and those 9 are the worst state in the tree, cited by name so they look covered
    with no path to open them. C19 already guarantees every such path resolves, so strict + C19 is
    reachable AND correct; loose is neither.
    """
    pointed = set()
    for md in skill_markdown():
        for m in re.finditer(r"\$\{CLAUDE_PLUGIN_ROOT\}/(BestPractices/examples/[^\s`)'\"]+\.cls)",
                             read(md)):
            pointed.add(m.group(1).rstrip(".,;"))
    out = []
    for f in artefacts():
        if f.suffix != ".cls":
            continue
        if any(k in f.name for k in TEST_TIER):
            continue
        if str(f.relative_to(REPO)) not in pointed:
            out.append(rel(f))
    return sorted(out)


def skill_assets() -> list[Path]:
    """Standalone `.cls` files bundled inside a skill, at `skills/<name>/assets/`.

    THESE ARE COMPILED BY TIER 2 AND ARE OTHERWISE UNGATED. Measured before this existed: a real
    bank class copied to `skills/messages/assets/` left every tier unchanged -- 170 artefacts, 169
    staged, tier 1 and tier 2 both green and both blind to it. #335 proposes moving the 49
    uniquely-owned bank classes into the skill that cites them; done without this, all 49 would
    leave compile coverage in the same commit that moved them, silently.

    Kept SEPARATE from artefacts() on purpose rather than merged into it. `rel()` is
    BANK-relative and raises for anything outside the bank, and it is called from a dozen places
    in tier 1; widening artefacts() would mean auditing every one of them to find the crash.
    A second source costs one loop and cannot break the bank's own checks.

    `assets/` and not `references/` is the DIRECTION test, not an importance one: references/ is
    material the model reads to understand, and it costs context when opened; assets/ is material
    the model copies into its output, and it costs nothing until copied. A standalone
    compile-verified class carrying its own `/// Rule:` provenance header is emit-shaped by
    construction. A reference filed as an asset is never read, so the trap it documents goes
    untaught; an asset filed as a reference costs a full context load to use a file that should
    have been copied unread. Both directions hurt.
    """
    return sorted(SKILLS.glob("*/assets/*.cls"))


def rel(p: Path) -> str:
    return str(p.relative_to(BANK))


def repo_rel(p: Path) -> str:
    """Repo-relative path. `rel()` is bank-relative and raises for anything outside it."""
    return str(p.relative_to(REPO))


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def is_comment(line: str) -> bool:
    s = line.strip()
    return any(s.startswith(c) for c in COMMENT_PREFIXES)


def class_names(text: str) -> list[str]:
    return re.findall(r"^Class\s+([A-Za-z0-9_.%]+)", text, re.M)


def doc_headings() -> set[str]:
    return set(re.findall(r"^#+\s*(\d+\.\d+(?:\.\d+)?)", read(DOC), re.M))


# --------------------------------------------------------------------------
# Tier 1 -- structural
# --------------------------------------------------------------------------

FIXTURES = Path(__file__).with_name("atelier_fixtures.json")


def tier0() -> bool:
    """Check the INSTRUMENT before measuring the bank with it.

    Tier 2's verdict is only as good as `parse_failures`, and for one whole family of IRIS
    errors that verdict was silently inverted: the gate printed "compiled clean" for a class
    IRIS had refused (#159). A green tier 2 could not have revealed that -- it IS the thing
    that was wrong -- so the parser gets its own red case, from real captured payloads.

    No IRIS and no network: these are frozen responses, so this runs in CI on every PR while
    the live `--compile` job runs only where an instance exists.

    WHAT THESE FIXTURES DO AND DO NOT PIN DOWN, established by mutating the parser and watching
    which case went red -- not by reading it:

      dependency_5373           carried by the params scan OR the quoted-name extraction
      dependency_console_only   carried by the quoted-name extraction OR `Skipping class`
      unattributed              carried by the reconciliation ALONE

    So the first two survive any SINGLE mechanism being removed and only die when two are
    (mutants M1, M2, M4, M5, M7 all survived; M6 killed both). That redundancy is deliberate
    -- the original defect was three paths failing on the same input at once -- but it means
    a green here does NOT prove each mechanism is individually live. The reconciliation is the
    exception and the one that matters: it is singly covered, and its mutant dies.

    AND THE REDUNDANCY IS NOT SYMMETRIC IN PRACTICE. A batch document that succeeds AND compiles
    a table clears `status.errors` for the whole batch (isolated by experiment: same batch, same
    #5373, ok classes as %RegisteredObject -> populated, as %Persistent -> empty). 6 of the bank's
    34 classes are persistent, so EVERY real tier 2 run returns `status.errors == []` and the
    status-side scanning contributes nothing. Verified end to end with two real bank classes plus
    one broken class: status.errors=0, failure still attributed from the console.

    So for the bank this gate exists to guard, `Skipping class` and the console scan are not a
    backup for the status path -- they ARE the path, and the reconciliation is the floor beneath
    them. Read the mutation map above with that in mind: M2 survives the fixtures, but removing
    `Skipping class` in the real single-error-family case would leave only the quoted-name match.
    """
    print("Tier 0 -- the compile-result parser\n")
    rep = Report()
    try:
        cases = json.loads(read(FIXTURES))
    except (OSError, ValueError) as exc:
        print(f"  FAIL  fixtures unreadable: {exc}")
        return False

    for name, case in cases.items():
        if name.startswith("_"):
            continue
        got = sorted(parse_failures(case["payload"], set(case["staged"])))
        want = sorted(case["expect"])
        rep.check(f"P-{name}", f"{name} -> {want or 'clean'}",
                  [] if got == want else [f"expected {want}, got {got}"])

    return rep.done("Tier 0")


def tier1() -> bool:
    print("Tier 1 -- structural\n")
    r = Report()
    files = artefacts()
    files = [f for f in files if f.name != "README.md"]
    heads = doc_headings()
    readme = read(README)
    doc = read(DOC)

    r.check("C1", "every artefact carries a /// Rule: header",
            [rel(f) for f in files if "Rule:" not in read(f)[:500]])

    unresolved = []
    for f in files:
        for ref in sorted(set(re.findall(r"§(\d+\.\d+(?:\.\d+)?)", read(f)))):
            if ref not in heads:
                unresolved.append(f"{rel(f)} -> §{ref} is not a heading in the deliverable")
    r.check("C2", "every §ref resolves to a real doc heading", unresolved)

    r.check("C3", "one class per .cls file (keeps every example one loadable unit)",
            [f"{rel(f)} defines {len(class_names(read(f)))}"
             for f in files if f.suffix == ".cls" and len(class_names(read(f))) != 1])

    missing_row = [rel(f) for f in files if f.name not in readme]
    dangling = [
        path for path in set(re.findall(r"`(ch\d+[^`]+\.(?:cls|xml|sh|cls\.xml))`", readme))
        if not (BANK / path).exists()
    ]
    r.check("C4", "README index and the directory agree, both ways",
            missing_row + [f"README row points at missing file: {p}" for p in dangling])

    tipo_last = []
    for f in files:
        for cn in class_names(read(f)):
            if cn.rsplit(".", 1)[-1] in TIPOS:
                tipo_last.append(f"{rel(f)} -> {cn} puts the Tipo last; use <Pkg>.<Tipo>.<Name>")
    r.check("C5", "no class name ends in a Tipo (#91)", tipo_last)

    banned_hits = []
    for f in files:
        for n, line in enumerate(read(f).splitlines(), 1):
            if is_comment(line):
                continue  # the bank documents several of these as anti-patterns
            for pattern, why in BANNED:
                if re.search(pattern, line):
                    banned_hits.append(f"{rel(f)}:{n} -- {why}")
    r.check("C6", "no token the audit proved wrong (comments exempt)", banned_hits)

    broken_links = []
    asset_names = {f.name for f in skill_assets()}
    for path in re.findall(r"\*\*Example\.\*\*\s*`examples/([^`]+)`", doc):
        # The deliverable cites `examples/<ch>/<file>` by its bank path. After the asset move the
        # file may live in skills/<name>/assets instead, and it is still shipped -- so a basename
        # match there resolves the pointer. The deliverable keeps the historical path on purpose:
        # rewriting 45 §-anchored citations to per-skill paths would couple the book to the skill
        # layout, and the book is the stable half.
        if (BANK / path).exists() or os.path.basename(path) in asset_names:
            continue
        broken_links.append(f"deliverable cites examples/{path}, which does not exist")
    # ── C8 ────────────────────────────────────────────────────────────────────────────────
    # A production <Setting> value is a STRING, so tier 2 compiles a production whose
    # BusinessRuleName names a class that does not exist anywhere. Found by audit: three of the
    # four .cls productions in this bank pointed at rule classes that were never written, and
    # every one of them compiled clean. That is the gate being green on the wrong thing, which
    # is the failure this bank exists to prevent -- so it gets a check rather than a note.
    #
    # Covers .xml artefacts too: the alert-circuit production is XML, which tier 2 skips
    # entirely, so it is the one place a dangling name would never be compiled at all.
    # BANK PLUS SKILL ASSETS, and this is the whole reason the asset move needed the gate first.
    # C7/C8/C10 ask "does this name resolve to something we ship". `files` is bank-only, so the
    # moment 63 examples moved into skills/*/assets these three started reporting real, shipped
    # classes as dangling: 45 C7 failures, 2 C8, 1 C10 -- measured, not predicted, on the first run
    # after the move. Messages use repo_rel(), never rel(), because rel() is bank-relative and RAISES
    # outside it.
    gated = [f for f in files if f.suffix in (".cls", ".xml")] + skill_assets()
    CLASS_SETTINGS = ("BusinessRuleName", "RecordMap")
    ITEM_SETTINGS = ITEM_REF_SETTINGS
    shipped = {cn for f in gated if f.suffix == ".cls" for cn in class_names(read(f))}
    dangling = []
    for f in gated:
        text = read(f)
        if "<Production " not in text:
            continue
        # NOT r'<Item\s[^>]*Name="...' -- [^>]* is greedy and happily swallows up to
        # ClassName=", so that form collects CLASS names and every item reference then looks
        # dangling. Parse the tag's attributes, and use a lookbehind so ClassName does not match.
        items = set()
        for attrs in re.findall(r"<Item\s+([^>]*)>", text):
            m = re.search(r'(?<![A-Za-z])Name="([^"]+)"', attrs)
            if m:
                items.add(m.group(1))
        for name, value in re.findall(r'Name="([^"]+)">([^<]+)</Setting>', text):
            for raw in value.split(","):
                v = raw.strip()
                if not v:
                    continue
                # an item reference resolves against this production's own items
                if name in ITEM_SETTINGS and v in items:
                    continue
                # a class reference must be a class this bank ships, or an InterSystems class
                if name in CLASS_SETTINGS:
                    if v in shipped or v.startswith(("Ens", "EnsLib", "HS", "%")):
                        continue
                    dangling.append(f"{repo_rel(f)} -> {name}=\"{v}\" names no shipped class")
                elif name in ITEM_SETTINGS:
                    dangling.append(f"{repo_rel(f)} -> {name}=\"{v}\" names no item in this production")
    r.check("C8", "production settings resolve to a shipped class or an item in the same production",
            dangling)

    r.check("C7", "every 'Example.' pointer in the deliverable resolves", broken_links)

    # ── C10 ───────────────────────────────────────────────────────────────────────────────
    # C8 checks the settings INSIDE a production. It cannot see the other direction: a routing
    # rule names a production and `<send target="X">` an item in it, and X is just a string. A
    # rule sending to an item that does not exist matches, fires, routes nowhere and reports
    # nothing -- the same silent shape as the dangling BusinessRuleName C8 was added for, arriving
    # from the opposite side.
    #
    # Motivated by §7.1: the alert circuit's entire failure mode is "the rule matched and the
    # message went nowhere", and until v1.21.0 the shipped circuit was an .xml that no tier
    # compiled at all.
    rule_targets = []
    prod_items: dict[str, set[str]] = {}
    for f in gated:
        text = read(f)
        if "<Production " not in text:
            continue
        for cn in class_names(text) or re.findall(r'<Production\s+Name="([^"]+)"', text):
            items = set()
            for attrs in re.findall(r"<Item\s+([^>]*)>", text):
                mm = re.search(r'(?<![A-Za-z])Name="([^"]+)"', attrs)
                if mm:
                    items.add(mm.group(1))
            prod_items[cn] = items
    for f in gated:
        text = read(f)
        m_prod = re.search(r'<ruleDefinition[^>]*\sproduction="([^"]*)"', text)
        if not m_prod or not m_prod.group(1):
            continue                      # a rule naming no production cannot be checked
        prod = m_prod.group(1)
        if prod not in prod_items:
            # A NON-EMPTY name that is not shipped is itself the defect, and skipping it was how
            # this check first missed one: routing-rule-fanout named "Example.Production" while
            # every shipped production is "Example.Productions.*" (plural). It compiles -- the
            # attribute is a string in XData -- and C8 does not look here. Use production="" for a
            # rule that is deliberately standalone; the empty case is skipped above.
            rule_targets.append(
                f'{rel(f)} -> <ruleDefinition production="{prod}"> names no shipped production '
                f'(use production="" if the rule is standalone)')
            continue
        for target in re.findall(r'<send\b[^>]*\starget="([^"]*)"', text):
            for one in [t.strip() for t in target.split(",") if t.strip()]:
                if one not in prod_items[prod]:
                    rule_targets.append(
                        f'{rel(f)} -> <send target="{one}"> names no item in {prod}')
    r.check("C10", "a routing rule's <send target> resolves to an item in the production it names",
            rule_targets)

    # ── C11 ───────────────────────────────────────────────────────────────────────────────
    # A router's BadMessageHandler must not be an item the rule also <send>s to. If they are the
    # same, a rejected message lands exactly where an accepted one does -- measured on 2026.1 by
    # feeding three messages through a running production: valid, unknown-type and
    # malformed-structure ALL arrived at BO.AdtOut, because BadMessageHandler named it. A malformed
    # message is then written to the normal output beside the valid ones, and no test can tell the
    # paths apart, so "validation is on" becomes unfalsifiable.
    collide_bad = []
    for f in files:
        if f.suffix not in (".cls", ".xml"):
            continue
        text = read(f)
        if "<Production " not in text:
            continue
        prods = class_names(text) or re.findall(r'<Production\s+Name="([^"]+)"', text)
        bad = {}
        for name, value in re.findall(r'Name="([^"]+)">([^<]+)</Setting>', text):
            if name == "BadMessageHandler":
                bad[value.strip()] = True
        rules = {}
        for name, value in re.findall(r'Name="([^"]+)">([^<]+)</Setting>', text):
            if name == "BusinessRuleName":
                rules[value.strip()] = True
        if not bad or not rules:
            continue
        # find the rule artefact(s) this production names, and read their send targets
        sends = set()
        for other in files:
            if other.suffix != ".cls":
                continue
            otext = read(other)
            if not any(rn in class_names(otext) for rn in rules):
                continue
            sends |= {t.strip() for t in re.findall(r'<send\b[^>]*\starget="([^"]*)"', otext)}
        for b in bad:
            if b in sends:
                collide_bad.append(
                    f'{rel(f)} -> BadMessageHandler="{b}" is also a <send target> of its rule: '
                    f'a rejected message lands where an accepted one does')
    r.check("C11", "a router's BadMessageHandler is not also one of its rule's send targets",
            collide_bad)

    # ── C12 ───────────────────────────────────────────────────────────────────────────────
    # `--` inside an XML comment is illegal and fails the XData parse:
    #   ERROR #6301: SAX XML Parser Error: '--' sequence is illegal in comment
    # `hl7-schemas` documents this trap, and it still cost a full tier-2 round trip when I wrote
    # a production comment with an em-dash-as-double-hyphen. Worse, it does not present as itself:
    # the projection error aborted the batch, so the visible failure was
    # `<CLASS DOES NOT EXIST> ... Ens.DTL.Transform` on an unrelated DTL whose message class had
    # not been reached yet, and the class-level attribution still reported every class clean --
    # only the unattributed-error detector caught the run at all. One second here beats that.
    bad_comments = []
    for f in files:
        if f.suffix not in (".cls", ".xml"):
            continue
        for block in re.findall(r"<!--.*?-->", read(f), re.S):
            inner = block[4:-3]
            if "--" in inner:
                snippet = " ".join(inner.split())[:70]
                bad_comments.append(f"{rel(f)} -> '--' inside an XML comment (#6301): \"{snippet}…\"")
    r.check("C12", "no '--' inside an XML comment (#6301 kills the whole XData parse)", bad_comments)

    # ── C13 ───────────────────────────────────────────────────────────────────────────────
    # A DTL's Transform method is GENERATED, and the generator needs the sourceClass/targetClass
    # already compiled. Measured on 2026.1, same batch, same classes:
    #     no DependsOn -> FAILS        DependsOn -> all compile
    # So a DTL without DependsOn compiles only while the batch happens to reach its dependencies
    # first. dtl-order-to-vendor shipped that way for releases and failed the moment an unrelated
    # projection error perturbed the order -- reporting `<CLASS DOES NOT EXIST> <MessageClass> ...
    # Ens.DTL.Transform`, which names neither the cause nor the omission.
    #
    # Narrow deliberately: it asks only that each project class named in sourceClass/targetClass
    # appears in DependsOn. Platform classes (Ens*, EnsLib*, HS*, %*) are not required -- they are
    # always already compiled -- and a DTL whose source and target are both platform classes needs
    # nothing.
    dtl_deps = []
    for f in files:
        if f.suffix != ".cls":
            continue
        text = read(f)
        if "Ens.DataTransformDTL" not in text or "<transform" not in text:
            continue
        m_dep = re.search(r"Extends\s+Ens\.DataTransformDTL\s*(?:\[([^\]]*)\])?", text)
        declared = m_dep.group(1) if (m_dep and m_dep.group(1)) else ""
        referenced = set()
        for attr in ("sourceClass", "targetClass"):
            for val in re.findall(attr + r"='([^']+)'", text):
                if not val.startswith(("Ens", "EnsLib", "HS", "%")):
                    referenced.add(val)
        missing = sorted(c for c in referenced if c not in declared)
        if missing:
            dtl_deps.append(f"{rel(f)} -> DependsOn omits {missing} (its generator needs them compiled first)")
    r.check("C13", "a DTL declares DependsOn for the project classes it transforms", dtl_deps)

    # ── C14 ───────────────────────────────────────────────────────────────────────────────
    # A class that extends a PREBUILT Ens host and overrides OnInit must call ##super(). Measured
    # on 2026.1 via %Dictionary.CompiledMethod.Origin: EnsLib.RecordMap.Service.Standard and
    # EnsLib.HL7.Service.FileService define their OWN OnInit, so an override that omits ##super()
    # silently replaces real setup. It compiles, the production starts, and the failure surfaces
    # later as records that do not parse.
    #
    # Scope: only subclasses of EnsLib.* hosts, because a custom Ens.BusinessService subclass has
    # nothing but Ens.Host's no-op to call and requiring it there would be noise (the calibration
    # note at the top of this file). CR-14 is the conformance criterion this mirrors.
    missing_super = []
    for f in files:
        if f.suffix != ".cls":
            continue
        text = read(f)
        if not re.search(r"^Class\s+[\w.]+\s+Extends\s+EnsLib\.", text, re.M):
            continue
        m_init = re.search(r"^Method\s+OnInit\s*\([^)]*\)[^\n]*\n\{(.*?)^\}", text, re.S | re.M)
        if not m_init:
            continue
        if "##super" not in m_init.group(1):
            missing_super.append(
                f"{rel(f)} -> OnInit overrides a prebuilt EnsLib host without calling ##super()")
    r.check("C14", "an OnInit override on a prebuilt EnsLib host calls ##super()", missing_super)

    # ── C15 ───────────────────────────────────────────────────────────────────────────────
    # An `Ens.Alert` item with no BusinessRuleName is WORSE than no Ens.Alert item at all: the
    # framework routes every Ens.AlertRequest to that name, the rule that would forward them does
    # not exist, and the alerts are captured and dropped in silence.
    #
    # Found by Example.UTL.PreflightValidator on its first real run: FIVE of the six gated
    # productions carried exactly that -- an Ens.Alert item with AlertOnError=0 and no rule, added
    # to look like an alert circuit. AlertOnError=1 on ordinary items feeds the real circuit
    # (ch07_alerting), which is a production of its own and needs no local router.
    alert_norule = []
    for f in files:
        if f.suffix not in (".cls", ".xml"):
            continue
        text = read(f)
        if "<Production " not in text:
            continue
        for block in re.findall(r"<Item\s[^>]*>.*?</Item>", text, re.S):
            m_name = re.search(r'(?<![A-Za-z])Name="([^"]+)"', block)
            if not m_name or m_name.group(1) != "Ens.Alert":
                continue
            if "BusinessRuleName" not in block:
                alert_norule.append(
                    f"{rel(f)} -> Ens.Alert item has no BusinessRuleName: it captures every "
                    f"Ens.AlertRequest and drops it. Wire it, or omit the item entirely.")
    r.check("C15", "an Ens.Alert item carries a BusinessRuleName (or is not there at all)",
            alert_norule)

    # ── C16 ───────────────────────────────────────────────────────────────────────────────
    # An INVISIBLE character in an artefact compiles clean and cannot be seen in a diff.
    #
    # Found the hard way (v1.58.0): a zero-width non-joiner (U+200C) landed inside a method name --
    # `Method Test\u200cReturnedErrorReachesTheAlert()` -- and IRIS ACCEPTED IT. Tier 2 was green, the
    # suite ran, and %UnitTest still found the method because the name happens to start with "Test".
    # Any reference to that method by name from anywhere else would have failed, and the reason would
    # have been invisible in every tool a reader has. Zero-width characters get in through copy-paste
    # and through generated text; nothing else in this gate would ever notice.
    #
    # Scoped to characters with no legitimate use in source: zero-width, BOM, non-breaking space,
    # and the bidi overrides. Ordinary accented text and typographic dashes are left alone -- the
    # deliverable and the headers use them deliberately.
    INVISIBLE = {
        "\u200b": "ZERO WIDTH SPACE", "\u200c": "ZERO WIDTH NON-JOINER",
        "\u200d": "ZERO WIDTH JOINER", "\u2060": "WORD JOINER",
        "\ufeff": "BOM / ZERO WIDTH NO-BREAK SPACE", "\u00a0": "NO-BREAK SPACE",
        "\u202a": "LEFT-TO-RIGHT EMBEDDING", "\u202b": "RIGHT-TO-LEFT EMBEDDING",
        "\u202d": "LEFT-TO-RIGHT OVERRIDE", "\u202e": "RIGHT-TO-LEFT OVERRIDE",
        "\u2066": "LEFT-TO-RIGHT ISOLATE", "\u2067": "RIGHT-TO-LEFT ISOLATE",
    }
    invisible = []
    for f in files:
        if f.suffix not in (".cls", ".xml", ".md"):
            continue
        text = read(f)
        for ch, name in INVISIBLE.items():
            if ch not in text:
                continue
            line = text[: text.index(ch)].count("\n") + 1
            invisible.append(
                f"{rel(f)}:{line} -> contains U+{ord(ch):04X} {name}, which is invisible in every "
                f"diff and compiles clean. Delete it.")
    r.check("C16", "no invisible character in an artefact (they compile clean)", invisible)

    # ── C17 ───────────────────────────────────────────────────────────────────────────────
    # Prose cross-references are gated by NOTHING, and splitting a skill breaks them wholesale.
    # Measured over v1.91.0-v1.93.0: five §"Heading" citations were broken by a split, one of them
    # SHIPPED in v1.91.0 and was found two releases later by hand. Tiers 0-3 compile code; nothing
    # reads a pointer. So this is the check, not a habit.
    #
    # TWO ARMS, because the obvious one arm would have caught NONE of the five.
    #
    #   (a) DEAD TARGET. A §"Heading" that matches no heading anywhere under skills/. This is the
    #       arm people expect, and it found exactly one real case (bpl citing an `alerting` heading
    #       that no longer exists).
    #
    #   (b) MOVED OUT FROM UNDER THE CITATION. A SKILL.md citing §"X" where X resolves ONLY in that
    #       same skill's own references/. The citation still "resolves", which is why arm (a) is
    #       blind to it -- but the prose around it says "below"/"above"/"this file" and the section
    #       is no longer in this file. Every one of the five was this shape. The remedy is a link to
    #       the reference file, not a § to a section that left.
    #
    # NORMALISATION matters more than the matching. A citation wrapped across two lines carries the
    # continuation prefix (`///`, `//`, `>`) into the middle of the quoted text, and a first draft of
    # this check reported four such citations as dead when all four resolved fine. Strip the
    # prefixes and collapse whitespace before comparing, or the check cries wolf and gets muted.
    #
    # MATCHED BY SUBSTRING, deliberately: citations are routinely shortened (§"Required parameters"
    # for a heading that continues "— `PRODUCTION` is COMPILE-TIME mandatory"). Requiring equality
    # would fail on the repo's own established style.
    #
    # `§<number>` is NOT matched, and that is load-bearing: `ESQL §3.1`, `GOBJ §2.6.3`, `EGDV §12.3`
    # are citations into external InterSystems books, they have no heading here, and there are
    # nine of them. The regex requires a quote immediately after the §, which excludes all of them.
    #
    # WHAT THIS DOES NOT COVER, so a clean run is not read as more than it is: a prose pointer with
    # no § at all ("see the BO skeleton above") is invisible to this check. Four of those were fixed
    # by hand in v1.93.0 and nothing stops the next one.
    skill_md = sorted(SKILLS.glob("*/*.md")) + sorted(SKILLS.glob("*/*/*.md"))
    headings: dict[str, list[Path]] = {}
    for md in skill_md:
        for h in re.findall(r"^#{2,4} (.+)$", read(md), re.M):
            headings.setdefault(h.strip(), []).append(md)

    def _norm(s: str) -> str:
        """Drop continuation prefixes a wrapped citation drags in, then collapse whitespace."""
        s = re.sub(r"\n\s*(?:///|//|>|\*)?\s*", " ", s)
        return re.sub(r"\s+", " ", s).strip()

    dead, moved = [], []
    for md in skill_md:
        skill = md.relative_to(SKILLS).parts[0]
        for m in re.finditer(r'§"([^"]+)"', read(md), re.S):
            want = _norm(m.group(1))
            if not want:
                continue
            where = {f for h, fs in headings.items() if want in _norm(h) for f in fs}
            if not where:
                dead.append(f"{repo_rel(md)} -> §\"{want}\" matches no heading under skills/")
            elif md.name == "SKILL.md" and md not in where and \
                    all(str(f).startswith(str(SKILLS / skill / "references")) for f in where):
                moved.append(
                    f"{repo_rel(md)} -> §\"{want}\" now lives only in "
                    f"{', '.join(sorted(repo_rel(f) for f in where))}; link the reference file "
                    f"instead of citing a section this file no longer contains")
    r.check("C17", "every §\"Heading\" citation in a skill resolves, and none points at a section "
                   "that moved into that skill's own references/", dead + moved)

    # ── C18 ───────────────────────────────────────────────────────────────────────────────
    # A `.cls` bundled in a skill is a copy-and-adapt template, so it needs the same provenance a
    # bank artefact needs: C1 requires `/// Rule:` there, and an asset the model pastes into a
    # production without knowing which measured rule it encodes is worse than no asset.
    #
    # Deliberately NOT the full C1..C16 set. Those run off artefacts(), which is BANK-relative
    # (see skill_assets()), and C4 in particular checks the bank README both ways -- a skill asset
    # is not indexed there and never should be. Header and one-class-per-file are the two that
    # carry meaning outside the bank.
    asset_bad = []
    for f in skill_assets():
        text = read(f)
        if "/// Rule:" not in text:
            asset_bad.append(f"{repo_rel(f)} -> no `/// Rule:` header; an asset is pasted into a "
                             f"production, so it must say which measured rule it encodes")
        if len(class_names(text)) != 1:
            asset_bad.append(f"{repo_rel(f)} -> {len(class_names(text))} classes in one file; an "
                             f"asset is copied whole, so it must be exactly one loadable unit")
    r.check("C18", "every .cls bundled in skills/*/assets carries a /// Rule: header and one class",
            asset_bad)

    # ── C19 ───────────────────────────────────────────────────────────────────────────────
    # A skill reaches the example bank by an absolute `${CLAUDE_PLUGIN_ROOT}/...` path, and until now
    # NOTHING checked that the path resolves. C17 catches a dead §"Heading" citation inside the
    # prose; this is the same defect one layer over, pointing out of the skill at a file.
    #
    # It is cheap and it is the natural moment to add it: #343-a added 14 of these paths by hand in
    # this same release, taking the cited count from 54 to 68 of 169, and a typo in any of them would
    # have been a pointer to nothing -- indistinguishable from a working one to every reader, and
    # exactly the shape that makes a model conclude the example does not exist.
    #
    # Rename or move an example and this fires, which is the point: the bank's README is reconciled
    # by C4, but a skill citing the old name was unguarded in both directions.
    # BOTH path forms, and the second arm is why: moving a bank example into skills/<name>/assets/
    # replaces its `${CLAUDE_PLUGIN_ROOT}/...` citation with one RELATIVE to the citing file, which
    # is the portability win (no variable to resolve) -- and which the first arm cannot see. Without
    # this arm the move would silently drop 63 citations out of path verification in the same commit
    # that created them. Resolved against the citing file's own directory, so `assets/x.cls` from a
    # SKILL.md and `../assets/x.cls` from a references/ file both work.
    plugin_refs, dangling = 0, []
    for md in skill_markdown():
        body = read(md)
        for m in re.finditer(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\s`)'\"]+)", body):
            target = m.group(1).rstrip(".,;")
            plugin_refs += 1
            if not (REPO / target).exists():
                dangling.append(f"{repo_rel(md)} -> ${{CLAUDE_PLUGIN_ROOT}}/{target} does not exist")
        for m in re.finditer(r"(?<![\w/.$}])((?:\.\./)?assets/[^\s`)'\"]+\.cls)", body):
            target = m.group(1).rstrip(".,;")
            plugin_refs += 1
            if not (md.parent / target).resolve().exists():
                dangling.append(f"{repo_rel(md)} -> relative asset {target} does not resolve")
    r.check("C19", "every example path a skill cites resolves on disk — plugin-root and relative",
            dangling)
    # A clean C19 means nothing if it scanned no paths at all.
    if not plugin_refs:
        r.check("C19-control", "C19 actually found plugin-root references to check", ["found 0"])

    # ── C20 ───────────────────────────────────────────────────────────────────────────────
    # An example no skill points at is UNREACHABLE: the model has no way to learn it exists.
    # Measured, 101 of 169 were unreferenced by basename and 110 by a usable path; excluding the
    # test tier leaves 69 subject examples out of 117.
    #
    # A RATCHET, not an equality, and for the same reason as C9: 69 cannot fail the build today, but
    # a NEW example with no pointer is new unreachable surface and must. A drop only prints, because
    # working the debt down is the goal and a gate that fails on progress gets muted.
    #
    # WHAT THIS MEASURES AND WHAT IT DOES NOT. Reachability, not reading. #335 measured 1,589
    # presentations of resolved example paths against 0 opens, so C20 at zero debt would still not
    # mean the examples get used. This stops the SUPPLY problem getting worse; the demand side is the
    # write-time hook in #335's proposal 2 and is not this check's business.
    unpointed = unpointed_subjects()
    _bl = json.loads(read(BASELINE)) if BASELINE.exists() else {}
    recorded_list = _bl.get("unpointed_subjects")
    # The LIST, not just a count, because a count can only say "one more than before" -- and the
    # first version of this check did exactly that: it failed and then printed the first eight
    # entries of the whole sorted debt, none of which was the file the author had just added. A gate
    # that names the wrong files is one people learn to ignore.
    recorded_up = len(recorded_list) if isinstance(recorded_list, list) else recorded_list
    grew_up = []
    # A MISSING baseline makes a ratchet inert, and an inert check reports "ok" -- which is the
    # silent-pass shape this repo keeps being bitten by. --update-baseline always writes the key, so
    # its absence means the file was hand-edited. Say so rather than pass.
    if recorded_up is None:
        grew_up.append("no `unpointed_subjects` count in examples_baseline.json, so this ratchet is "
                       "measuring nothing -- run --update-baseline after a green gate")
    if recorded_up is not None:
        if len(unpointed) > recorded_up:
            fresh = ([u for u in unpointed if u not in set(recorded_list)]
                     if isinstance(recorded_list, list) else [])
            grew_up.append(
                f"{len(unpointed)} subject examples are reachable from no skill, baseline "
                f"{recorded_up} -- {len(unpointed) - recorded_up} new one(s). Add a "
                f"`${{CLAUDE_PLUGIN_ROOT}}/BestPractices/examples/<ch>/<file>.cls` pointer to the "
                f"owning skill, or re-record deliberately.")
            grew_up += [f"    NEW and unreachable: {u}" for u in fresh[:8]]
    r.check("C20", "no new bank example is unreachable from every skill (ratchet)", grew_up)
    if recorded_up is not None and len(unpointed) < recorded_up:
        print(f"          note: unreachable subject examples down to {len(unpointed)} from "
              f"{recorded_up} -- progress; re-record with --update-baseline")
    # The test-tier exemption must actually exempt something, or the convention has rotted.
    exempted = [f for f in artefacts() if f.suffix == ".cls" and any(k in f.name for k in TEST_TIER)]
    if not exempted:
        r.check("C20-control", "the tdd-/fixture exemption still matches files",
                ["matched 0 -- the naming convention changed and C20 is now measuring the test tier"])

    # ── C9 ────────────────────────────────────────────────────────────────────────────────
    # Tier 3 compiles only the fences holding a COMPLETE class. The remainder -- bare
    # Method/ClassMethod, and loose statements -- is printed on every run but was asserted by
    # nothing except a sentence in CLAUDE.md. That sentence said 33 while the real figure had
    # become 34, and the one fence that made the difference was the 1.13.0 Foundation-namespace
    # recipe: the most load-bearing fact added that week landed in the exact fence shape no tier
    # compiles, and no number tracked it. A count nobody asserts rots, so it gets a check.
    #
    # Deliberately a RATCHET and not an equality. Growth fails -- that is new ungated surface.
    # A drop only prints: bringing a fence under the gate is the GOAL, and a gate that fails on
    # progress is one people learn to mute (see the calibration note at the top of this file).
    _, bare, loose, _ = snippets()
    recorded = (json.loads(read(SNIPPET_BASELINE)) if SNIPPET_BASELINE.exists() else {}).get("ungated", {})
    grew, shrank = [], []
    for label, actual, key in (("bare member", bare, "bare_members"),
                               ("loose fragment", loose, "loose_fragments")):
        cap = recorded.get(key)
        if cap is None:
            continue
        if actual > cap:
            grew.append(f"{label}s: {actual}, baseline {cap} -- {actual - cap} new fence(s) that "
                        f"no tier compiles; give them a host class, or re-record deliberately")
        elif actual < cap:
            shrank.append(f"{label}s down to {actual} from {cap} -- progress; "
                          f"re-record with --update-baseline")
    r.check("C9", "no SKILL.md fence has escaped the gate since the baseline", grew)
    for note in shrank:
        print(f"          note: {note}")

    print(f"  {len(files)} artefacts, {sum(1 for f in files if f.suffix == '.cls')} classes")
    return r.done("Tier 1")


# --------------------------------------------------------------------------
# Tier 2 -- compile against a live IRIS
# --------------------------------------------------------------------------

class Atelier:
    """Minimal Atelier REST client -- stdlib only, so CI needs no dependencies.

    This is a test harness, not production code: the plugin's own rule is that
    interop work reaches IRIS through the MCP. A CI job has no MCP, so the gate
    talks to the same REST API the MCP itself uses.
    """

    def __init__(self) -> None:
        self.host = os.environ.get("IRIS_HOST", "localhost")
        self.port = os.environ.get("IRIS_PORT", "43080")
        self.ns = os.environ.get("IRIS_NAMESPACE", "APP")
        user = os.environ.get("IRIS_USER", "_SYSTEM")
        pwd = os.environ.get("IRIS_PASSWORD", "SYS")
        token = base64.b64encode(f"{user}:{pwd}".encode()).decode()
        self.auth = f"Basic {token}"
        # The namespace goes in the URL path, so it must be encoded: %SYS and any namespace
        # with a % in it otherwise returns HTTP 400 and gets misreported as "unreachable".
        self.base = f"http://{self.host}:{self.port}/api/atelier/v1/{urllib.parse.quote(self.ns, safe='')}"

    def _call(self, method: str, path: str, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"{self.base}{path}", data=data, method=method)
        req.add_header("Authorization", self.auth)
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())

    def put(self, name: str, source: str):
        return self._call("PUT", f"/doc/{name}?ignoreConflict=1",
                          {"enc": False, "content": source.splitlines()})

    def compile(self, names: list[str]):
        return self._call("POST", "/action/compile?flags=cuk", names)

    def delete(self, name: str):
        return self._call("DELETE", f"/doc/{name}")

    def query(self, sql: str):
        """Run SQL. Warns — loudly — when the response carries an error, because the default
        failure mode of this endpoint is a SILENT EMPTY RESULT.

        A query naming a column that does not exist returns `content: []` with the reason only in
        `status.summary` (`SQLCODE -29, Field 'X' not found`). A caller that reads `content` and not
        the status therefore sees "nothing matches" for what is actually a broken query. That cost
        three confident wrong conclusions in one session — including "this class carries no index"
        about a class that has one, which in turn produced a published finding that had to be
        retracted (coverage-map X14).

        The warning is ADDITIVE: the response is returned unchanged, so no caller's behaviour moves.
        It exists so the error reaches a human in the run output instead of waiting to be asked for.
        """
        resp = self._call("POST", "/action/query", {"query": sql, "parameters": []})
        errors = (resp.get("status") or {}).get("errors") or []
        if errors:
            summary = str((resp.get("status") or {}).get("summary") or errors[0])
            print(f"  SQL WARNING -- this query FAILED and returned no rows, which is not the same "
                  f"as 'no rows matched':\n      {summary[:300]}\n      query: {sql[:200]}")
        return resp


def preflight() -> bool:
    """Prove the environment is usable BEFORE compiling anything.

    Without this, a misconfigured target produces a uniformly red run that reads as "the
    examples are broken" when it actually means "this IRIS has no Interoperability". That is
    a worse outcome than no CI check at all, because it trains people to ignore the result.
    Each failure below names which of the two it is.
    """
    print("Preflight\n")
    iris = Atelier()
    print(f"  target {iris.base}")

    try:
        ver = iris._call("GET", "")
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
        print(f"  FAIL  cannot reach IRIS: {exc}")
        print("        ENVIRONMENT problem, not an example problem.")
        print("        Check IRIS_HOST / IRIS_PORT / IRIS_USER / IRIS_PASSWORD.")
        return False
    content = (ver.get("result") or {}).get("content") or {}
    dbs = ", ".join(d.get("name", "?") for d in (content.get("db") or [])[:6])
    print(f"  ok    reachable — namespace {content.get('name', iris.ns)} over [{dbs}]")

    try:
        rows = (iris.query(
            "SELECT COUNT(*) AS n FROM %Dictionary.CompiledClass WHERE Name = 'Ens.Director'"
        ).get("result") or {}).get("content") or []
        has_ens = rows and int(list(rows[0].values())[0]) > 0
    except Exception as exc:
        print(f"  FAIL  could not query the dictionary in namespace {iris.ns}: {exc}")
        print("        ENVIRONMENT problem, not an example problem.")
        return False

    if not has_ens:
        print(f"  FAIL  namespace {iris.ns} has no Ens.Director — Interoperability is not enabled")
        print("        ENVIRONMENT problem, not an example problem. Every Ens.* example would")
        print("        fail for the same reason and the run would say nothing about the bank.")
        return False
    print(f"  ok    namespace {iris.ns} is Interoperability-enabled")

    try:
        rows = (iris.query(
            "SELECT COUNT(*) AS n FROM %Dictionary.CompiledClass WHERE Name = 'EnsLib.HL7.Message'"
        ).get("result") or {}).get("content") or []
        has_hl7 = rows and int(list(rows[0].values())[0]) > 0
    except Exception:
        has_hl7 = False

    if not has_hl7:
        print("  FAIL  EnsLib.HL7.Message is absent — this is IRIS, not IRIS for Health")
        print("        ENVIRONMENT problem. Several examples legitimately need the HL7 library;")
        print("        use an irishealth image rather than recording them as failures.")
        return False
    print("  ok    HL7 library present")

    print("\nPreflight: environment is usable\n")
    return True


UNATTRIBUTED = "<unattributed compile errors>"


def _class_candidates(text: str):
    """Every class name a diagnostic mentions, member suffixes stripped.

    A #5373 reads: Class 'A', used by 'B:property:P', does not exist. **A is the class
    that is MISSING and B is the class that FAILED.** Yield both and let `known` decide
    which one was staged — picking one position is how this went wrong before.
    """
    for raw in re.findall(r"'([^']+)'", text):
        yield raw.split(":")[0]
    for raw in re.findall(r"([A-Za-z0-9_.%]+)\.cls", text):
        yield raw


def parse_failures(result: dict, known: set[str]) -> dict[str, str]:
    """Pull class -> first error out of an Atelier compile response.

    VERIFIED against live IRIS 2026.1 on a two-class batch, one deliberately broken.
    The previous version of this function returned {} for that batch — i.e. reported
    "all classes compile" for a class IRIS had refused — on three independent counts:

      1. It read `params[0]` as the failing class. For the whole dependency family of
         errors `params[0]` is the class that is ABSENT, which is never in `known`, so
         it was dropped. The failing class sits in `params[1]` as `B:property:P`.
      2. The `\\.cls` regex found nothing: Atelier diagnostics name classes bare and
         quoted, not with a file extension.
      3. The console line that states the outcome is `Skipping class B`, which carries
         no ERROR token and so was `continue`d past by the ERROR filter.

    Attribution is still best-effort — IRIS's error vocabulary is larger than anything
    verified here — so the GUARANTEE does not rest on it; see the reconciliation below.
    """
    failed: dict[str, str] = {}

    def note(name: str, msg: str) -> None:
        if name in known:
            failed.setdefault(name, " ".join(msg.split())[:220])

    for err in (result.get("status") or {}).get("errors") or []:
        text = err.get("error", "") if isinstance(err, dict) else str(err)
        params = err.get("params") or [] if isinstance(err, dict) else []
        for p in params:
            if isinstance(p, str) and p:
                note(p.split(":")[0], text)
        for cn in _class_candidates(text):
            note(cn, text)

    console = result.get("console") or []
    for line in console:
        # IRIS's own statement that a class did not compile. It carries no ERROR token,
        # so it must be matched BEFORE the ERROR filter below, not after it.
        m = re.search(r"Skipping class ([A-Za-z0-9_.%]+)", line)
        if m:
            note(m.group(1), line)
        if "ERROR" not in line.upper():
            continue
        for cn in _class_candidates(line):
            note(cn, line)
        m = re.search(r"compiling class '([\w.%]+)'", line, re.IGNORECASE)
        if m:
            note(m.group(1), line)

    # RECONCILIATION -- the actual guarantee.
    #
    # Every check above is a pattern match against error text, and a pattern match only
    # ever covers the shapes someone thought of. IRIS independently reports HOW MANY
    # errors it detected, so use that as the oracle: a non-zero count with nothing
    # attributed is an unattributed failure and must fail the run LOUDLY. Returning {}
    # there is precisely what let a class print "Skipping class X" and be recorded clean.
    #
    # Scope, stated so a clean run is not read as more than it is: this catches TOTAL
    # attribution failure only. Errors do not map 1:1 to classes (one class easily
    # produces several), so a partial miss cannot be detected by counting -- but a
    # partial miss still leaves `failed` non-empty, which already fails the build and
    # puts a human in front of the console. The silent-green case is the one closed here.
    detected = 0
    for line in console:
        m = re.search(r"Detected (\d+) error", line)
        if m:
            detected = max(detected, int(m.group(1)))
    if detected and not failed:
        failed[UNATTRIBUTED] = (
            f"IRIS detected {detected} compile error(s) that could not be attributed to "
            "any staged class. Read the console below before trusting this run: "
            + " | ".join(l for l in console if l.strip())[:400]
        )

    return failed


def deregister_search_tables(iris, staged, sources, label: str = "") -> None:
    """Drop Ens_Config.SearchTableProp rows left by staged SearchTable classes.

    Deleting the CLASS does not deregister a SearchTable's properties: a row survives in
    Ens_Config.SearchTableProp keyed `<Class>~<ExtentSuperclass>`. Re-staging the same name is
    fine, so a repeated run stays green and the leak is invisible -- but RENAME a SearchTable and
    the next run fails with

        <EnsSearchTable>PropCollision: Property 'X' in class 'New' cannot override the
        definition from class 'Old'

    naming a class that no longer exists anywhere. Measured on 2026-09-18: that is exactly what N8
    (MyApp.Search.HL7 -> MyApp.Search.Hl7Adt) hit. CI never sees it -- a fresh container has no
    prior row -- which is precisely why it is cleaned here rather than left to be rediscovered.

    THIS LIVED ONLY IN TIER 3 UNTIL v1.41.0, and the reason is worth keeping: the bank had no
    SearchTable, so tier 2 leaking was unobservable. S19 added the first one
    (`Example.Search.Hl7Adt`), and the leak was immediately real -- 4 props surviving a clean run.
    Shared by both tiers now so the pair cannot drift apart again.
    """
    # THE TWO TIERS HOLD `sources` IN DIFFERENT SHAPES, and the first version of this helper was
    # silently a no-op in tier 2 because of it: tier 2 maps name -> text (a str), tier 3 maps
    # name -> (text, skill) (a tuple). `sources.get(cn, ("", ""))[0]` therefore took the FIRST
    # CHARACTER of tier 2's source, so `"SearchTable" in "/"` was always False. It ran, printed
    # nothing, cleaned nothing, and the props it was written to remove were still there afterwards
    # -- caught only by counting the rows before and after. Normalise, and never index blind.
    def _text(cn: str) -> str:
        v = sources.get(cn, "")
        return v[0] if isinstance(v, tuple) else v

    registered = [cn for cn in staged if "SearchTable" in _text(cn)]
    if not registered:
        return
    where = " OR ".join(f"ClassDerivation LIKE '{cn}~%'" for cn in registered)
    try:
        iris.query(f"DELETE FROM Ens_Config.SearchTableProp WHERE {where}")
        print(f"  deregistered{label}: {len(registered)} SearchTable prop set(s)")
    except (urllib.error.HTTPError, urllib.error.URLError) as exc:
        print(f"  SearchTable props LEFT REGISTERED ({exc}) -- a later rename will "
              f"fail with PropCollision naming a class that no longer exists")


def tier2() -> bool:
    print("Tier 2 -- compile against live IRIS\n")
    sources: dict[str, str] = {}
    for f in artefacts():
        if f.suffix != ".cls":
            continue
        text = read(f)
        names = class_names(text)
        if len(names) == 1:
            sources[names[0]] = text

    assets = 0
    for f in skill_assets():
        names = class_names(read(f))
        if len(names) == 1:
            sources[names[0]] = read(f)
            assets += 1

    iris = Atelier()
    print(f"  target {iris.base}")
    print(f"  staging {len(sources)} classes"
          + (f" ({assets} from skills/*/assets)" if assets else "") + "\n")

    staged: list[str] = []
    ok = False
    try:
        try:
            for cn, src in sources.items():
                iris.put(f"{cn}.cls", src)
                staged.append(cn)
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            print(f"  CANNOT REACH IRIS: {exc}")
            print("  set IRIS_HOST / IRIS_PORT / IRIS_NAMESPACE / IRIS_USER / IRIS_PASSWORD")
            return False

        # Compile twice on purpose. A DTL's Transform method is built by a generator
        # that resolves sourceClass/targetClass at generation time, so a DTL compiled
        # in the same batch as its own message classes can fail with
        #   #5001 <CLASS DOES NOT EXIST>  >  #5490 Error running generator
        # even though those classes are in the batch. It is an ordering artefact, not
        # a defect: the second pass succeeds unchanged. Only pass 2 is authoritative --
        # anything that compiled in pass 1 is skipped as up-to-date, so what pass 2
        # still reports is a genuine, persistent failure.
        docs = [f"{cn}.cls" for cn in sources]
        iris.compile(docs)
        failed = parse_failures(iris.compile(docs), set(sources))

        clean = sorted(set(sources) - set(failed))
        baseline = json.loads(read(BASELINE)) if BASELINE.exists() else {}
        expected = set(baseline.get("expected_clean", []))
        regressions = sorted(expected & set(failed))
        newly_clean = sorted(set(clean) - expected)

        print(f"  compiled clean : {len(clean)} / {len(sources)}")
        if failed:
            print(f"  failed         : {len(failed)}")
            for cn, err in sorted(failed.items()):
                flag = "REGRESSION vs baseline" if cn in expected else "not in baseline"
                print(f"      {cn}  [{flag}]")
                print(f"        {err}")
        if newly_clean:
            print(f"  new since baseline: {', '.join(newly_clean)}")
            print("  -> re-record with --update-baseline once reviewed")

        ok = not failed
    finally:
        left = []
        for cn in staged:
            try:
                iris.delete(f"{cn}.cls")
            except (urllib.error.HTTPError, urllib.error.URLError):
                left.append(cn)
        deregister_search_tables(iris, staged, sources, "   ")
        msg = f"  cleanup        : {len(staged) - len(left)} deleted"
        if left:
            msg += f", {len(left)} LEFT BEHIND: {left}"
        print(msg)

    print(f"\nTier 2: {'all classes compile' if ok else 'FAILED'}\n")
    return ok


SKILLS = REPO / "skills"
SNIPPET_BASELINE = Path(__file__).resolve().parent / "snippets_baseline.json"

# A fence may hold more than one class (messages/SKILL.md does), and may be preceded by an
# Include line that belongs to the class. Split on the class boundary, keeping any Include.
_CLASS_START = re.compile(r"(?im)^(?=(?:Include\s+[^\n]+\n+)?\s*Class\s+[\w.%]+\s+Extends)")
# Lines that legitimately PRECEDE a class and belong to it: blank lines, `//` comments (`///`
# included), `;` comments, and `Include` directives.
#
# `Include` is here because _CLASS_START's optional `(?:Include...)?` prefix cannot do the job: the
# lookahead matches at the Include position AND at the Class position, so re.split() always cut
# between them and the directive was dropped from the staged class. `$$$Str2MsgTyp` / `$$$Sql*` come
# from an Include, so a fence that needs one was being compiled without it.
_COMMENT_ONLY = re.compile(
    r"\A(?:[^\S\n]*(?://[^\n]*|;[^\n]*|Include\s+[^\n]*)?\n)*[^\S\n]*\Z")


def skill_markdown() -> list[Path]:
    """Every markdown file in a skill that could carry a fence -- NOT just SKILL.md.

    THIS GLOB IS THE COMPILE GATE OVER skills/. Both tier 3 and C9 read `snippets()`, so whatever
    this misses is ungated by the whole pipeline, silently and while every check stays green.

    It was `*/SKILL.md`, and that is a trap the moment any content moves to a reference file --
    which is the direction #337 chose. Measured before changing it: a deliberately UNCOMPILABLE
    class placed in `skills/bpl/references/zzprobe.md` left tier 3 green at the same 33 classes,
    never seeing it. C9 is worse than neutral there -- its ungated counts come from this same
    function, so relocating a fence out of reach makes those counts DROP, and C9 prints a drop as
    "progress". The gate would have congratulated us for removing content from it.

    So the reach widens BEFORE any content moves, never in the same change and never after.

    Two patterns, matching the two shapes Anthropic's Agent Skills docs actually show: files
    bundled beside SKILL.md (the PDF skill's `FORMS.md`, `REFERENCE.md`) and one subdirectory of
    them (the BigQuery skill's `reference/finance.md`). Nothing deeper -- "keep references one
    level deep from SKILL.md" is the documented rule, and a file reachable only through a chain is
    one the docs say Claude may only partially read.
    """
    return sorted(SKILLS.glob("*/*.md")) + sorted(SKILLS.glob("*/*/*.md"))


def provenance(md: Path) -> str:
    """`bpl` for a SKILL.md, `bpl:rules` for `bpl/references/rules.md`.

    `md.parent.name` was correct while every source was a SKILL.md; for a reference file it returns
    the literal "references", so every reference fence in every skill would report the same
    provenance and a broken snippet could not be traced back to the skill that owns it.
    """
    rel = md.relative_to(SKILLS)
    return rel.parts[0] if md.name == "SKILL.md" else "%s:%s" % (rel.parts[0], md.stem)


def snippets() -> tuple[dict[str, tuple[str, str]], int, int, list[str]]:
    """Extract every compilable class out of the ```objectscript fences in skills/.

    Returns (class -> (source, provenance), bare_members, loose_fragments, duplicate_names).

    WHAT THIS GATE DOES NOT COVER, stated here so a clean run is not read as more than it is
    (the same reason the S5 note exists in CLAUDE.md): only fences containing a COMPLETE class
    are compiled. A fence holding a bare Method/ClassMethod has no host class and no knowable
    superclass, and a fence holding loose statements has no compilation unit at all. Both are
    counted and printed, never silently skipped -- if that count is large, the gate is narrower
    than it looks.
    """
    out: dict[str, tuple[str, str]] = {}
    dupes: list[str] = []
    indented: list[str] = []
    members = fragments = 0
    for md in skill_markdown():
        skill = provenance(md)
        for m in re.finditer(r"```objectscript\n(.*?)```", read(md), re.S):
            block = m.group(1)
            if not re.search(r"(?im)^\s*Class\s+[\w.%]+\s+Extends", block):
                if re.search(r"(?im)^\s*(Method|ClassMethod)\s+\w+", block):
                    members += 1
                else:
                    fragments += 1
                continue
            parts = [p for p in _CLASS_START.split(block) if p.strip()]
            # _CLASS_START splits immediately BEFORE `Class`, so a `///` doc comment written
            # above the class becomes a nameless part: counted as a loose fragment AND dropped
            # from what is compiled, i.e. the class is gated without the `/// Rule:` header that
            # is this repo's whole convention. Re-attach it to the class it documents.
            #
            # MEASURED, so the comment does not overclaim: this was LATENT, not active. Re-running
            # the fixed parser over the pre-fix content gives an identical 26 classes / 34
            # fragments, so no fence had ever carried a leading doc comment. It was tripped by the
            # first snippet class written with one -- which C9 caught on its first real outing, as
            # a fragment count that rose 34 -> 35 for an edit that added no fragment.
            pending = ""
            for part in parts:
                names = class_names(part)
                if len(names) != 1:
                    if not names and _COMMENT_ONLY.match(part):
                        pending += part
                    else:
                        # A fence whose `Class` line is INDENTED (written inside a markdown list)
                        # reaches here: the outer search tolerates leading whitespace but
                        # class_names() does not -- correctly, since ObjectScript requires column 0.
                        # Counting it as a loose fragment was silent, and hid a class the reader
                        # would copy verbatim into something that cannot compile. Say so.
                        if re.search(r"(?m)^[ \t]+Class\s+[\w.%]+\s+Extends", part):
                            indented.append(f"{skill}: {re.search(r'(?m)^[ \t]+Class\s+([\w.%]+)', part).group(1)}")
                        fragments += 1
                        pending = ""
                    continue
                part, pending = pending + part, ""
                # A name that appears in two fences used to be SILENTLY OVERWRITTEN here, so the
                # run printed "staging N classes" while one fence was never compiled at all --
                # the exact shape of silent gap this tier exists to close. Measured when found:
                # 26 complete-class fences, 25 unique names, MyApp.MSG.PersonReq twice inside
                # `messages`. Collide now and the tier says so.
                if names[0] in out:
                    dupes.append("%s (in %s and %s)" % (names[0], out[names[0]][1], skill))
                out[names[0]] = (part, skill)
            if pending.strip():
                fragments += 1  # trailing comment with no class after it
    if indented:
        print("  INDENTED CLASS FENCE -- not staged, and not copy-pasteable (ObjectScript needs")
        print("  `Class` at column 0). Dedent the fence:")
        for i in indented:
            print(f"      {i}")
    return out, members, fragments, dupes


def external_classes() -> dict[str, tuple[str, str]]:
    """class name -> (source, repo-relative path) for every .cls under BestPractices/external."""
    out: dict[str, tuple[str, str]] = {}
    for f in sorted(EXTERNAL.rglob("*.cls")):
        text = read(f)
        for cn in class_names(text):
            out[cn] = (text, repo_rel(f))
    return out


def dangling_item_refs(files) -> list[str]:
    """Item-reference settings that name no <Item> in their own production.

    The same rule C8 applies to the bank, factored out so the vendored tree can be held to it too.
    A <Setting> value is a STRING, so nothing here is a compile error -- tier 2b compiles the
    upstream snapshot clean with a duplex partner that does not exist.
    """
    ITEM_SETTINGS = ITEM_REF_SETTINGS
    out: list[str] = []
    for f in sorted(files):
        if f.suffix not in (".cls", ".xml"):
            continue
        text = read(f)
        if "<Production " not in text:
            continue
        items = set()
        for attrs in re.findall(r"<Item\s+([^>]*)>", text):
            m = re.search(r'(?<![A-Za-z])Name="([^"]+)"', attrs)
            if m:
                items.add(m.group(1))
        for name, value in re.findall(r'Name="([^"]+)">([^<]+)</Setting>', text):
            if name not in ITEM_SETTINGS:
                continue
            for raw in value.split(","):
                v = raw.strip()
                if v and v not in items:
                    out.append(f'{repo_rel(f)} -> {name}="{v}"')
    return out


def tier2_external() -> bool:
    """Compile the vendor reference tree that no tier used to touch.

    `dicom` calls this tree "the canonical reference for every pattern here" and points readers
    straight at it -- 19 classes, 1934 lines, and until now compiled by NOTHING. It had already
    drifted twice (a deprecated JavaGateway item; a duplex target naming an item that does not
    exist), which is what a reference nobody compiles does.

    TWO DELIBERATE ASYMMETRIES WITH TIER 2.

    1. It gets the compile tier and NOT tier 1. Measured before writing this: 0 of the 19 files
       carry a `/// Rule:` header, so C1 would fail all 19 and the only way to green it would be to
       edit vendor source. The structural checks encode OUR conventions; this tree is not ours.
    2. A failure here means "the vendor tree no longer matches this IRIS version", NOT "go fix the
       file". The repair is a conscious re-sync with upstream, or a note at the `dicom` pointer --
       never a local edit that makes the mirror diverge silently.

    They are compiled as ONE batch because they reference each other; class-at-a-time would report
    dependency failures that do not exist.
    """
    print("Tier 2b -- compile the external reference tree\n")
    sources = external_classes()

    # LOUD ON ZERO. This directory is tracked and non-empty, so "no classes found" means the
    # walker broke, not that there is nothing to check -- and a silent skip would read in the log
    # exactly like a pass. (See CLAUDE.md: a clean zero needs a positive control.)
    if not sources:
        print(f"  NO CLASSES FOUND under {repo_rel(EXTERNAL)} -- expected 19.")
        print("  Either the tree was removed (update this tier) or the walk is broken.")
        print("\nTier 2b: FAILED\n")
        return False

    # The same shadowing guard tier 3 applies to the bank: one class name must mean one body.
    bank = {cn for f in artefacts() if f.suffix == ".cls" for cn in class_names(read(f))}
    snips = set(snippets()[0])
    collide = sorted((set(sources) & bank) | (set(sources) & snips))
    if collide:
        print(f"  NAME COLLISION with the bank or an inline snippet: {collide}")
        print("  Rename the BANK/SNIPPET copy -- the external tree is a read-only mirror.")
        print("\nTier 2b: FAILED\n")
        return False

    iris = Atelier()
    print(f"  target {iris.base}")
    print(f"  staging {len(sources)} classes from {repo_rel(EXTERNAL)}")

    staged: list[str] = []
    ok = False
    try:
        try:
            for cn, (src_text, _) in sources.items():
                iris.put(f"{cn}.cls", src_text)
                staged.append(cn)
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            print(f"  CANNOT REACH IRIS: {exc}")
            print("\nTier 2b: FAILED\n")
            return False

        docs = [f"{cn}.cls" for cn in sources]
        failed = parse_failures(iris.compile(docs), set(sources))

        baseline = json.loads(read(EXTERNAL_BASELINE)) if EXTERNAL_BASELINE.exists() else {}
        expected = set(baseline.get("expected_clean", []))
        clean = sorted(set(sources) - set(failed))
        print(f"\n  compiled clean : {len(clean)} / {len(sources)}")
        if failed:
            print(f"  DRIFTED        : {len(failed)}")
            for cn, err in sorted(failed.items()):
                flag = "REGRESSION vs baseline" if cn in expected else "not in baseline"
                print(f"      {cn}  [{sources[cn][1]}]  [{flag}]")
                print(f"        {err}")
            print("  This is the mirror disagreeing with this IRIS version. Re-sync upstream or")
            print("  note the divergence at the `dicom` pointer -- do not patch the mirror.")
        missing = sorted(expected - set(clean))
        if missing:
            print(f"  in baseline but no longer clean/present: {', '.join(missing)}")
        newly = sorted(set(clean) - expected)
        if newly and expected:
            print(f"  new since baseline: {', '.join(newly)}")
        ok = not failed
    finally:
        left = []
        for cn in staged:
            try:
                iris.delete(f"{cn}.cls")
            except (urllib.error.HTTPError, urllib.error.URLError):
                left.append(cn)
        msg = f"  cleanup        : {len(staged) - len(left)} deleted"
        if left:
            msg += f", {len(left)} LEFT BEHIND: {left}"
        print(msg)

    print(f"\nTier 2b: {'the external tree still compiles' if ok else 'FAILED'}\n")
    # ── the vendored tree's DANGLING ITEM REFERENCES ──────────────────────────────────────
    # Tier 1 deliberately does not touch this tree (see external_baseline.json's comment), and a
    # <Setting> value is a string, so a duplex partner that does not exist compiles clean here.
    # The upstream snapshot HAS one: `DICOM Store DCM TCP Out` names `DICOM STOWRS Process`, while
    # the item that exists is `DICOM StowRs Handler` -- a rename near-miss in both the casing and
    # the final word, so even a case-insensitive check would not match it. It is someone else's
    # repo, so it is RECORDED rather than fixed; what fails the gate is a NEW one appearing.
    found = dangling_item_refs(EXTERNAL.rglob("*"))
    known = set(json.loads(read(EXTERNAL_BASELINE)).get("known_dangling", [])) \
        if EXTERNAL_BASELINE.exists() else set()
    fresh = [d for d in found if d not in known]
    stale = sorted(known - set(found))
    if found:
        print(f"  dangling item refs      : {len(found)} ({len(found) - len(fresh)} known upstream)")
        for d in found:
            print(f"      {'NEW  ' if d in fresh else 'known'} {d}")
    if stale:
        print(f"  recorded but no longer present: {len(stale)} -- re-record with --update-baseline")
        for d in stale:
            print(f"      gone  {d}")
    if fresh:
        print(f"  FAILED: {len(fresh)} NEW dangling item reference(s) in the vendored tree")
        ok = False

    return ok


def tier3(record: bool = False) -> bool:
    print("Tier 3 -- compile the INLINE snippets in skills/*/SKILL.md"
          " and any reference markdown bundled beside it\n")
    sources, members, fragments, dupes = snippets()
    if dupes:
        print("  DUPLICATE CLASS NAME across fences -- one of each pair is never compiled:")
        for d in dupes:
            print(f"      {d}")
        print("  rename one, or the gate silently stages fewer classes than it reports\n")
        return False

    collide = sorted(set(sources) & {n for f in artefacts() if f.suffix == ".cls"
                                    for n in class_names(read(f))})
    if collide:
        print(f"  NAME COLLISION with the example bank: {collide}")
        print("  rename the snippet class -- staging both would compile one over the other\n")
        return False

    iris = Atelier()
    print(f"  target {iris.base}")
    print(f"  staging {len(sources)} classes extracted from fences")
    print(f"  not compiled: {members} bare member(s), {fragments} loose fragment(s) "
          f"-- no compilation unit; see snippets() docstring\n")

    staged: list[str] = []
    ok = False
    try:
        try:
            for cn, (src_text, _) in sources.items():
                iris.put(f"{cn}.cls", src_text)
                staged.append(cn)
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            print(f"  CANNOT REACH IRIS: {exc}")
            return False

        docs = [f"{cn}.cls" for cn in sources]
        iris.compile(docs)
        failed = parse_failures(iris.compile(docs), set(sources))

        # A snippet legitimately names a class it does not ship (MyApp.Msg.SomeRequest). That is
        # an illustrative placeholder, not a defect, so #5373 is reported and does NOT fail the
        # tier. Everything else -- wrong signature, undefined macro, unparseable member -- is a
        # copy-paste that cannot work, which is the whole point of this tier.
        dep = {c: e for c, e in failed.items() if "5373" in e or "used by" in e.lower()}
        real = {c: e for c, e in failed.items() if c not in dep}

        baseline = json.loads(read(SNIPPET_BASELINE)) if SNIPPET_BASELINE.exists() else {}
        expected = set(baseline.get("expected_clean", []))
        clean = sorted(set(sources) - set(failed))

        print(f"  compiled clean          : {len(clean)} / {len(sources)}")
        if dep:
            print(f"  placeholder dependency  : {len(dep)} (illustrative name, not a defect)")
            for cn in sorted(dep):
                print(f"      {cn}  [{sources[cn][1]}]")
        if real:
            print(f"  BROKEN SNIPPETS         : {len(real)}")
            for cn, err in sorted(real.items()):
                flag = "REGRESSION vs baseline" if cn in expected else "not in baseline"
                print(f"      {cn}  [{sources[cn][1]}]  [{flag}]")
                print(f"        {err}")
        newly_clean = sorted(set(clean) - expected)
        if newly_clean and expected:
            print(f"  new since baseline: {', '.join(newly_clean)}")

        # `expected_clean` for snippets can ONLY be computed from a live compile, and this is the one
        # place that has one. Before this, --update-baseline called update_snippet_baseline() with no
        # argument, which preserves the recorded list -- so the gate would print "new since baseline"
        # for a newly gated fence and then be unable to record it, for ever. The cost was a mislabel,
        # not a miss: a later break in such a class printed "not in baseline" instead of
        # "REGRESSION vs baseline", which is the weaker of the two signals and the wrong one.
        if record:
            update_snippet_baseline(clean)

        ok = not real
    finally:
        left = []
        for cn in staged:
            try:
                iris.delete(f"{cn}.cls")
            except (urllib.error.HTTPError, urllib.error.URLError):
                left.append(cn)

        # Deleting the CLASS does not deregister a SearchTable's properties: a row survives in
        # Ens_Config.SearchTableProp keyed `<Class>~<ExtentSuperclass>`. Re-staging the same name
        # is fine, so a repeated run stays green and the leak is invisible -- but RENAME a
        # SearchTable snippet and the next run fails with
        #   <EnsSearchTable>PropCollision: Property 'X' in class 'New' cannot override the
        #   definition from class 'Old'
        # naming a class that no longer exists anywhere. Measured on 2026-09-18: that is exactly
        # what N8 (MyApp.Search.HL7 -> MyApp.Search.Hl7Adt) hit, and renaming is a Wave 0 activity,
        # so it would have recurred. CI never sees it -- a fresh container has no prior row -- which
        # is precisely why it has to be cleaned here rather than left to be rediscovered.
        deregister_search_tables(iris, staged, sources, "            ")

        msg = f"  cleanup                 : {len(staged) - len(left)} deleted"
        if left:
            msg += f", {len(left)} LEFT BEHIND: {left}"
        print(msg)

    print(f"\nTier 3: {'every inline class snippet compiles' if ok else 'FAILED'}\n")
    return ok


def update_snippet_baseline(clean: list[str] | None = None) -> None:
    """Re-record the snippet baseline, MERGING rather than replacing.

    This used to take `clean` and write only that key -- and it was never called from anywhere,
    so it was dead code whose one behaviour was to silently drop any other key. `expected_clean`
    can only be recomputed from a live compile, so when called without it the recorded list is
    preserved and only the offline-computable `ungated` counts are refreshed.
    """
    data = json.loads(read(SNIPPET_BASELINE)) if SNIPPET_BASELINE.exists() else {}
    if clean is not None:
        data["expected_clean"] = sorted(clean)
    _, bare, loose, _ = snippets()
    data["ungated"] = {"bare_members": bare, "loose_fragments": loose}
    SNIPPET_BASELINE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"snippet baseline recorded: {len(data.get('expected_clean', []))} classes, "
          f"ungated {bare} bare / {loose} loose -> {SNIPPET_BASELINE.name}")


def update_external_baseline() -> None:
    names = sorted(external_classes())
    dangling = dangling_item_refs(EXTERNAL.rglob("*"))
    EXTERNAL_BASELINE.write_text(json.dumps({
        "_comment": "Vendor reference tree under BestPractices/external. Compiled by tier 2b, and "
                    "deliberately NOT subject to tier 1 -- none of these files carries a "
                    "/// Rule: header, and they are a read-only mirror of someone else's repo. A "
                    "failure means the mirror and this IRIS version disagree; re-sync upstream "
                    "rather than editing the file.",
        "expected_clean": names,
        "_dangling_comment": "Item-reference settings in the vendored tree that name no item in "
                             "their own production. Upstream defects, recorded because this tree is "
                             "a read-only mirror. A NEW one fails tier 2b; fix it upstream or "
                             "re-sync, and only then re-record.",
        "known_dangling": dangling,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"external baseline recorded: {len(names)} classes, "
          f"{len(dangling)} known dangling item ref(s) -> {EXTERNAL_BASELINE.name}")


def update_baseline() -> None:
    sources = []
    for f in artefacts():
        if f.suffix == ".cls":
            sources += class_names(read(f))
    # Skill assets are compiled by tier 2 as well (see skill_assets), so they belong in the
    # expected-clean list. Without this, moving a bank class into skills/<name>/assets/ makes a later
    # break report "not in baseline" instead of "REGRESSION vs baseline" -- the weaker of the two
    # signals, and the wrong one.
    for f in skill_assets():
        sources += class_names(read(f))
    unpointed = unpointed_subjects()
    BASELINE.write_text(json.dumps({
        "_comment": "Classes expected to compile clean. Any of these failing is a "
                    "regression and fails the build. Update only with a verified run.",
        "expected_clean": sorted(sources),
        "_unpointed_comment": "Count of bank SUBJECT examples (tdd-*/fixture excluded) that no "
                              "skill reaches by a full ${CLAUDE_PLUGIN_ROOT} path. C20 ratchets "
                              "this: growth fails, a drop only prints. The LIST is recorded, not "
                              "just its length, so a failure can name the newly-unreachable file "
                              "rather than the first eight of the existing debt. Computed by "
                              "unpointed_subjects(), the same function C20 calls.",
        "unpointed_subjects": unpointed,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"baseline recorded: {len(sources)} classes, {len(unpointed)} unreachable subject "
          f"example(s) -> {BASELINE.name}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--compile", action="store_true", help="also run tier 2 against a live IRIS")
    ap.add_argument("--preflight", action="store_true",
                    help="only check that the IRIS target is usable, then exit")
    ap.add_argument("--update-baseline", action="store_true", help="re-record the expected-clean list")
    args = ap.parse_args()

    if args.update_baseline:
        update_baseline()
        # tier3(record=True) rather than update_snippet_baseline(): the snippet expected_clean needs a
        # live compile, and tier 3 already stages, compiles and cleans up. Without a usable target the
        # ungated counts are still refreshed offline, and the recorded class list is preserved rather
        # than silently emptied.
        if preflight():
            tier3(record=True)
        else:
            print("  no usable IRIS target: refreshing the offline snippet counts only")
            update_snippet_baseline()
        update_external_baseline()
        return 0

    if args.preflight:
        return 0 if preflight() else 1

    ok = tier0()
    ok = tier1() and ok
    if args.compile:
        # A failed preflight means the environment is wrong, not the bank. Say which,
        # and do not stage 34 classes into an instance that cannot compile them.
        # One preflight for both live tiers; a bad target is an environment fault, not a
        # content fault, and must not be reported as 69 broken classes.
        if preflight():
            ok = tier2() and ok
            ok = tier2_external() and ok
            ok = tier3() and ok
        else:
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
