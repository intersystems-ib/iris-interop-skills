#!/usr/bin/env python3
"""PreToolUse conformance GATE for iris_doc / iris_compile / iris_execute (iris-interop-skills).

Unlike the PostToolUse advisories (which a weak model ignores), this BLOCKS the write/compile
when a class violates a hard, unambiguous iris-interop convention, forcing a fix before the
class lands. It denies only high-confidence violations (no false positives on ordinary code).

SCOPE, stated so the next reader does not have to infer it from the code: the naming and content
rules cover classes the model AUTHORS, in packages that are not InterSystems'. Reads are the
documented introspection path and are never gated (#221); system packages are not ours to rename.

  1. Non-standard package "type" segment in the class name — the convention is
     <Package>.<Tipo>.<Name> with Tipo in BS/BP/BO/DT/RUL/MSG. A class named `.Operation.`,
     `.Service.`, `.Process.`, `.Transform.` or `.Message.` is the wrong form of a known type.
  2. A class named like a Business Service/Operation that `Extends` an *InboundAdapter /
     *OutboundAdapter directly — a BS/BO must Extend Ens.BusinessService / Ens.BusinessOperation
     and declare the adapter via `Parameter ADAPTER`. (A genuine custom adapter, not named
     .BS./.BO./.Service./.Operation., is left alone.)
  3. Loading/compiling/importing classes through `iris_execute` ($SYSTEM.OBJ.Load /
     $SYSTEM.OBJ.Import / $SYSTEM.OBJ.Compile) — this bypasses the iris_doc/iris_compile path
     AND checks 1-2 above. Source must be written with iris_doc(mode=put) and compiled with
     iris_compile. (Deleting/exporting via iris_execute — Delete/DeletePackage/Export — is fine.)

Everything else is allowed (no output = allow). Deny is emitted as a PreToolUse permissionDecision.
"""
import sys, json, re

# wrong name segment -> correct Tipo abbreviation
NONSTD = {
    "Operation": "BO", "BusinessOperation": "BO",
    "Service": "BS", "BusinessService": "BS",
    "Process": "BP", "BusinessProcess": "BP",
    "Transform": "DT", "Transformation": "DT", "Transformations": "DT",
    "Message": "MSG", "Messages": "MSG",
}
BS_BO_SEGS = {"BS", "BO", "Service", "Operation", "BusinessService", "BusinessOperation"}

# Class load/compile/import driven through iris_execute instead of iris_doc/iris_compile.
# Matches both `$SYSTEM.OBJ.Load(` and the `##class(%SYSTEM.OBJ).Load(` form (optional `)`),
# for Load*/Import*/Compile* only — Delete/DeletePackage/Export are intentionally NOT matched.
OBJ_BYPASS = re.compile(r"(?i)SYSTEM\.OBJ\)?\.(Load|Import|Compile)")

# $SYSTEM.OBJ was never the only way to make a class from ObjectScript, and it was the only
# one gated (#110). Reproduced live: %Compiler.UDL.TextServices.SetTextFromStream puts an
# interop-named Business Operation in the namespace with no file on disk and no gate firing,
# because OBJ_BYPASS does not match it and src_before_iris only watches iris_doc. Observed in
# the corpus too: a run wrote ^oddDEF directly, with zero conformance denials in its transcript.
#
# CALIBRATED TO WRITES ONLY. The read forms are the normal introspection path and the plugin
# teaches them — %ExistsId, %Dictionary.CompiledClass queries, $order/$data over ^oddDEF,
# TextServices GetText*. Gating those would make this rule noise, and a noisy gate gets
# disabled. Each pattern below matches a mutation and nothing else.
CLASS_WRITE_BYPASS = [
    (re.compile(r"(?i)TextServices\)?\.SetText"),
     "%Compiler.UDL.TextServices.SetText* writes class source straight into the namespace"),
    (re.compile(r"(?i)%Dictionary\.(Class|Method|Property|Parameter|XData)Definition\)?\.%(New|Save)"),
     "the %Dictionary.*Definition object API creates/saves a class definition in place"),
    (re.compile(r"(?i)(?:^|[\s:])(?:set|kill|merge)\s+\^odd(DEF|COM)"),
     "writing ^oddDEF/^oddCOM edits the class dictionary directly"),
]

# ^oddDEF / ^oddCOM at all — read included. This started as a write-only rule, on the
# reasoning that $order over the dictionary global was legitimate introspection. It is not.
# ^oddDEF is the undocumented internal representation; reading it is the guessing that
# `introspect-dont-guess` exists to prevent, and it is version-fragile in a way the
# supported APIs are not.
#
# Nothing is lost by forbidding it. Verified on IRIS 2026.1: 58 persistent, SQL-queryable
# %Dictionary.* classes and 129 predefined queries. The two real corpus uses map directly —
# `$Order(^oddDEF(name))` is `SELECT Name FROM %Dictionary.ClassDefinition`, and walking
# `^oddDEF(cls,"p",param)` is %Dictionary.CompiledProperty / ParameterDefinition, or the
# Summary query.
DICT_GLOBAL = re.compile(r"(?i)\^odd(DEF|COM)")

# ──────────────────────────────────────────────────────────────── [IIS-CG-NAME] scope (#221)
# Packages that are InterSystems' own or reserved. Their names are not ours to rename, and
# reading them is the documented introspection path — the plugin's own skills send the model to
# EnsLib.RecordMap.Service.FileService BY NAME (business-services), and 14 distinct such class
# names appear across skills/. Denying a READ of those is a pure false positive: 4 of 4 in one
# measured cohort, on iris_doc(mode=get) of EnsLib.HL7.Service.FileService.
#
# Note the old rule discriminated by POSITION in the name, not by ownership: EnsLib.JavaGateway.Service
# passed only because `Service` is the LAST segment there and falls outside segs[1:-1].
#
# Same calibration as CLASS_WRITE_BYPASS above: gate what the model AUTHORS, never what it reads.
SYSTEM_ROOTS = {
    "Ens", "EnsLib", "EnsPortal", "HS", "CSP", "SYS", "Config", "Security",
    "SQLUser", "INFORMATION_SCHEMA", "SchemaMap", "Backup",
}


def is_system_class(base):
    """True for %Library.*, %Dictionary.*, Ens.*, EnsLib.*, HS.* and friends."""
    return base.startswith("%") or base.split(".", 1)[0] in SYSTEM_ROOTS


# ───────────────────────────────────────────────────────── [IIS-CG-UNDERSCORE] (#219)
# Class and member names are letters and digits only (RCOS Appendix A, §§A.7/A.9); `_` is the
# concatenation operator. The compiler reports it as #5559 "non-matching {} or () characters",
# which sends the model brace-hunting while the braces are balanced — 14 failed puts in one day,
# an instructor bisect correlating 14/14 failures and 4/4 successes. Delimited member names
# (Property "My Property") ARE legal (GOBJ §2.6.3) and are exempt.
MEMBER_KW = (r"Class|Property|Relationship|Method|ClassMethod|Parameter"
             r"|Query|Index|Trigger|ForeignKey|Projection|XData")
UNDERSCORE_MEMBER = re.compile(
    r"(?im)^[ \t]*(?:" + MEMBER_KW + r")[ \t]+"
    r"(?P<q>\"?)(?P<name>[A-Za-z%][A-Za-z0-9.]*_[A-Za-z0-9._]*)"
)


def strip_comments(code):
    r"""`code` with ObjectScript comments masked out, for matching the iris_execute rules against.

    WHY THIS EXISTS (#336). The rules below matched the forbidden API names anywhere in the
    submitted string, comments included -- so a comment that merely NAMED an API was refused.
    Reproduced with a positive control: the same trivial `write` statement was allowed on its
    own and denied with `// This comment mentions $SYSTEM.OBJ.Compile` above it.

    That is the wrong incentive in a specific way: the workaround is to write a LESS accurate
    comment. A gate whose purpose is code quality was pushing toward code that explains itself
    worse, and it refused the legitimate case of documenting why the sanctioned path is used.
    It cost a real round trip -- a probe that explained in a comment that it avoided
    $SYSTEM.OBJ.Compile because of this gate was denied for saying so.

    MASKS WITH SPACES, not by deleting, and keeps every newline. CLASS_WRITE_BYPASS's third
    pattern anchors on `(?:^|[\s:])` and none of these use re.M, so deleting text could join two
    tokens across a removed comment and change what the anchors see. Equal-length masking cannot.

    QUOTE-AWARE, which is the whole reason this is a scanner and not a regex. The obvious
    implementation cuts each line at the first `//`, and that corrupts `"http://example.org"` --
    truncating a line at a URL inside a string would hide any real call AFTER it on that line,
    turning this false positive into a false negative in a DENY gate, which is the worse trade.
    Being quote-aware means trailing comments can be stripped too, with no such hazard.

    Handles the three ObjectScript comment forms: `//` and `;` to end of line (`#;` leaves its
    `#`, which matches nothing), and `/* */` blocks, which may span lines. `""` inside a string
    is an escaped quote, not the end of it.

    NOT the same function as conformance_prescan.code_only, deliberately. That one answers "what
    is executable CLASS-MEMBER text" and is line-based because `///` doc comments dominate class
    source; this one answers "what does this ObjectScript STATEMENT execute". Different inputs,
    different right answers -- recorded here so the difference reads as a decision rather than as
    two strippers that drifted apart.
    """
    out, i, n = [], 0, len(code)
    instr = False
    while i < n:
        ch = code[i]
        if instr:
            out.append(ch)
            if ch == '"':
                if i + 1 < n and code[i + 1] == '"':
                    out.append('"')        # "" is an escaped quote, still inside the string
                    i += 2
                    continue
                instr = False
            i += 1
            continue
        if ch == '"':
            instr = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n and code[i + 1] == "*":
            end = code.find("*/", i + 2)
            end = n if end < 0 else end + 2        # unterminated block masks to the end
            for c in code[i:end]:
                out.append("\n" if c == "\n" else " ")
            i = end
            continue
        if (ch == "/" and i + 1 < n and code[i + 1] == "/") or ch == ";":
            end = code.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def mask_xdata(src):
    """Blank out XData bodies, keeping the line count.

    An HL7 schema or a <Setting Name="Foo_Bar"> legitimately carries underscores — that is DATA,
    not an identifier. Line numbering is preserved so the content rules below are unaffected.
    """
    lines = src.splitlines()
    out, i, n = [], 0, len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        i += 1
        if not re.match(r"(?i)^[ \t]*XData[ \t]+", line):
            continue
        depth, opened = line.count("{") - line.count("}"), "{" in line
        while i < n and (not opened or depth > 0):
            depth += lines[i].count("{") - lines[i].count("}")
            opened = opened or "{" in lines[i]
            out.append("")
            i += 1
    return "\n".join(out)


# ─────────────────────────────────────────── [IIS-CG-INTROSPECT] (ADVISORY — never deny) (#212)
# Measured over one cohort day: 248 iris_execute calls, 64 failures, dominated by ObjectScript
# that asks what a typed tool answers in one round trip — with an invented signature, so the
# answer is <METHOD DOES NOT EXIST> and the recovery is another invented signature.
#
# This must NOT deny. The same class names carry the legitimate lifecycle API: a deny on
# Ens.Director would block ##class(Ens.Director).CleanProduction(), the documented remedy for a
# stuck production (production-lifecycle). "Deny mutations only" does not discriminate either —
# the guessed call is itself written `Set tSC=##class(Ens.Director).GetProductionStatus(.n,.s)`.
#
# Scope is deliberately narrow: only what the MCP server does NOT already hint on. Its
# execute_redirect_hint covers $SYSTEM.OBJ.Load/Import, anything containing %Dictionary., the
# Ens_Config catalog guesses and a bare SELECT. Two advisories for one call is worse than one,
# and %Dictionary SQL is what this file's own DICTR deny recommends.
INTROSPECT_REDIRECT = [
    (re.compile(r"(?i)Ens\.Director\)?\.GetProductionStatus"),
     'iris_production(action="status", namespace="<NS>")'),
    (re.compile(r"(?i)Ens\.Director\)?\.GetHostInstance"),
     'iris_production_item(action="get_settings", item="<Item>", namespace="<NS>")'),
    (re.compile(r"(?i)Ens\.Director:EnumerateProductionItems"),
     'iris_production(action="status", namespace="<NS>") for the item list, then '
     'iris_production_item(action="get_settings", item="<Item>", namespace="<NS>")'),
    (re.compile(r"(?i)EnsPortal\.[A-Za-z0-9_]+\)?\."),
     'iris_production(action="status", namespace="<NS>") — EnsPortal.* is the Portal CSP UI, '
     'not a supported API'),
    (re.compile(r"(?i)(?:^|[\s:])(?:z?write|zw)\s+\^Ens\.(?:JobStatus|Runtime|ActivityD)"),
     'iris_production(action="status", namespace="<NS>") / '
     'iris_interop_query(what="queues", namespace="<NS>")'),
]

# Never nudge these: they are the documented lifecycle calls, and CleanProduction in particular is
# the remedy `production-lifecycle` prescribes for a registered production whose class is gone.
LIFECYCLE_OK = re.compile(
    r"(?i)Ens\.Director\)?\.(Clean|Recover|Start|Stop|Update)Production")

# Tools whose `namespace` is documented as OPTIONAL but is effectively REQUIRED: they resolve
# Ens.Director / Ens_Config.* in whatever namespace the connection defaults to, and if that one
# is not interop-enabled the call dies with an internal error that never names the cause
# (`<CLASS DOES NOT EXIST> Ens.Director`, `Table 'ENS_CONFIG.CREDENTIALS' not found`).
#
# Measured over a full workshop cohort (18 students, 15,079 tool calls): omitting `namespace`
# on these failed 37 of 39 times (95%), against 16% when it was passed.
#     iris_credential_list   14/14 failed      iris_production_item   7/7 failed
#     iris_production        15/17 failed      iris_lookup_manage      1/1 failed
#
# THAT 95% IS VERSION-BOUND, and the file must say so. It was measured against MCP <= 0.8.4,
# where all six of these tools declared an EMPTY input schema — `namespace` was on the wire but
# undeclared, so a model could not discover it from the handshake. MCP 0.11.0 declares it on all
# six. The wire key did not move and this rule still works, but the deny-rate WILL fall on
# 0.11.0+ for that reason alone. Do not read the drop as agents getting better; to separate the
# effects, measure deny-rate on 0.8.4 vs 0.11.0 with everything else held. The rule stays either
# way: passing `namespace` explicitly is never wrong, and declared-but-optional is not the same
# as reliably passed. See #125.
#
# Deliberately NOT listed, because the same capture proves they are fine without it:
# `check_config` (0/41 failures) and `iris_get_log` (0/40). A blanket rule would be wrong.
# Also not listed: iris_doc / iris_compile / iris_query / iris_execute / iris_test /
# iris_interop_query — every observed call already passed `namespace`, so there is no evidence
# either way and the gate does not guess.
NS_REQUIRED = {
    "iris_production", "iris_production_item", "iris_credential_list",
    "iris_credential_manage", "iris_lookup_manage", "iris_lookup_transfer",
}


def deny(rule, reason):
    """Emit a deny whose reason LEADS with a stable marker (#162).

    The marker names which rule fired; the prose after it is free to change. Corpus
    measurement keys on `[IIS-...]`, so improving a denial can no longer silently
    switch a detector off. See MARKERS below for why this is prepend-only.
    """
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "[IIS-CG-" + rule + "] " + reason,
    }}))
    sys.exit(0)


def collect_names(ti):
    names = []
    for k in ("name", "document"):
        v = ti.get(k)
        if isinstance(v, str) and v:
            names.append(v)
    for k in ("names", "targets", "documents"):
        v = ti.get(k)
        if isinstance(v, list):
            names += [x for x in v if isinstance(x, str)]
    return names


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return  # allow on parse failure — never block legitimate work on a hook bug
    ti = data.get("tool_input", {}) or {}
    tool_raw = str(data.get("tool_name") or "")
    names = collect_names(ti)
    content = ti.get("content") if isinstance(ti.get("content"), str) else ""

    # The gate also sits on Write|Edit, so a class written to disk is checked BEFORE the VS Code
    # sync carries it into IRIS (#219) — that route reaches iris_compile, which has no `content`
    # and so can only ever catch a bad CLASS name, never a bad member name.
    #
    # Edit supplies only `new_string`: best-effort, a fragment rather than the whole class.
    #
    # HARD CONSTRAINT: on Write/Edit the content rules apply ONLY to a .cls path. Without this the
    # gate denies edits to its own documentation — every build skill in this plugin carries
    # `Class … Extends EnsLib.…Adapter` and `ADT_A01` inside fenced examples, and a Write of a
    # SKILL.md would match them.
    if tool_raw in ("Write", "Edit", "MultiEdit"):
        fpath = ti.get("file_path")
        if not (isinstance(fpath, str) and fpath.lower().endswith(".cls")):
            return  # not a class file — nothing here applies
        if not content:
            ns = ti.get("new_string")
            content = ns if isinstance(ns, str) else ""

    # (4) interop tool called without `namespace` — 95% of these fail, and the error that comes
    # back names Ens.Director or a missing ENS_* table instead of the namespace. Cheaper to stop
    # here: adding an explicit namespace is never wrong, so a false positive costs one parameter.
    tool = str(data.get("tool_name") or "").split("__")[-1]
    if tool in NS_REQUIRED and not ti.get("namespace"):
        deny(
            "NS",
            "`" + tool + "` was called without `namespace`. The parameter is documented as optional, "
            "but it resolves Ens.Director / Ens_Config.* in the connection's default namespace — and "
            "when that one is not interop-enabled the call fails with an internal error that never "
            "names the cause (`<CLASS DOES NOT EXIST> Ens.Director`, `Table 'ENS_CONFIG.CREDENTIALS' "
            "not found`). Measured over a workshop cohort: 37 of 39 such calls failed (95 percent), "
            "against 16 percent when namespace was passed. Retry with the production's namespace, "
            "e.g. `" + tool + "(namespace=\"<NS>\", ...)`. `check_config` lists the namespaces "
            "available on this connection."
        )

    # (3) iris_execute used to load/compile/import classes — bypasses iris_doc/iris_compile + this gate.
    #
    # #336: every rule in this block matches `scan`, never the raw `code`. The issue reported it
    # for (3) and (3b); (3c) has the same defect, and in (3d) it runs the OTHER way — a comment
    # could buy an EXEMPTION from the advisory. Fixing only the two that were reported would
    # leave the siblings looking more trustworthy than they are.
    #
    # (3d)'s half is narrower than it first looks, and measured rather than assumed: LIFECYCLE_OK
    # needs the DOTTED form, so `// unlike CleanProduction, this only reads` never exempted
    # anything, while `// do NOT use ##class(Ens.Director).CleanProduction() here` did. The first
    # draft of this comment claimed the bare mention was enough; a removal test — same string
    # through the pattern with and without stripping — said otherwise.
    code = ti.get("code") if isinstance(ti.get("code"), str) else ""
    scan = strip_comments(code)
    if code:
        m = OBJ_BYPASS.search(scan)
        if m:
            deny(
                "EXEC",
                "Loading/compiling classes through iris_execute (matched '%s') bypasses the MCP's "
                "iris_doc/iris_compile path and this conformance gate. Write source with "
                "iris_doc(mode=put) and compile with iris_compile — never $SYSTEM.OBJ.Load / "
                "$SYSTEM.OBJ.Import / $SYSTEM.OBJ.Compile from iris_execute. "
                "(Deleting/exporting via iris_execute is fine.) "
                "Load Skill(iris-interop-skills:production-lifecycle) for the proper deploy path."
                % m.group(0)
            )

        # (3b) the other routes into the class dictionary — same bypass, different API (#110).
        for pattern, why in CLASS_WRITE_BYPASS:
            m = pattern.search(scan)
            if m:
                deny(
                    "DICTW",
                    "Creating class source through iris_execute (matched '%s') bypasses the MCP's "
                    "iris_doc/iris_compile path, this gate, and the source-of-truth gate — so the "
                    "class lands in the namespace with no file on disk, which is not "
                    "version-controlled, not reviewable, and does not survive the instance.\n\n"
                    "%s.\n\n"
                    "Write the class to src/<Pkg>/<Tipo>/<Name>.cls, then iris_doc(mode=put) the "
                    "same content and compile with iris_compile.\n\n"
                    "Reading the dictionary is untouched and is the right way to introspect: "
                    "%%ExistsId, %%Dictionary.CompiledClass queries, $order/$data over ^oddDEF, and "
                    "TextServices GetText* all pass."
                    % (m.group(0), why)
                )

        # (3c) reading the class dictionary global instead of the supported APIs (#110).
        m = DICT_GLOBAL.search(scan)
        if m:
            deny(
                "DICTR",
                "`%s` is the undocumented internal class dictionary. Reading it is guessing at "
                "IRIS internals, and its layout is not a contract — the supported APIs are.\n\n"
                "Use, in order of preference:\n"
                "  1. The MCP's typed tools — REAL parameter names, verified against the server:\n"
                "       iris_symbols(query='<Pkg>.*')               — find a class\n"
                "       docs_introspect(class_name='<Class>')       — members of one class\n"
                "       iris_table_info(table='<Schema>.<Table>')   — a projected table\n"
                "     One call, no catalog guessing.\n"
                "  2. %%Dictionary SQL — 58 queryable classes, e.g.\n"
                "       SELECT Name FROM %%Dictionary.ClassDefinition WHERE Name %%STARTSWITH 'Pkg.'\n"
                "       SELECT parent, Name, Type FROM %%Dictionary.CompiledProperty WHERE parent = ?\n"
                "  3. The predefined queries — %%Dictionary.ClassDefinition:Summary / :SubclassOf / "
                ":MemberSummary, %%Dictionary.PackageDefinition:SubPackage, and 125 more.\n\n"
                "If you want the helper, it is an AGENT, not a skill — Skill() on it errors:\n"
                "  Agent(subagent_type=\"iris-interop-skills:introspect-dont-guess\")"
                % m.group(0)
            )

        # (3d) hand-rolled introspection that a typed tool answers. ADVISORY — never a deny.
        if not LIFECYCLE_OK.search(scan):
            for pattern, tool_call in INTROSPECT_REDIRECT:
                m = pattern.search(scan)
                if m:
                    print(json.dumps({"hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "additionalContext":
                            "[IIS-CG-INTROSPECT] `" + m.group(0) + "` is hand-rolled "
                            "introspection through iris_execute. Signatures in this family are "
                            "routinely guessed and come back <METHOD DOES NOT EXIST>, and the "
                            "recovery is another guess. One typed call answers it: " + tool_call +
                            ". Full question->tool table: "
                            "Skill(iris-interop-skills:message-search-debug). Advisory — the call "
                            "was NOT blocked."}}))
                    sys.exit(0)   # one message per call; deny() exits the same way

    # `mode` is present on iris_doc and ABSENT on iris_compile. Do NOT write this as
    # `mode == "put"`: that would exempt iris_compile, which sits in the same matcher and carries
    # no mode — the one other path a badly named class can land on (#221).
    mode = ti.get("mode")
    authoring = not (isinstance(mode, str) and mode and mode != "put")

    for nm in names:
        base = nm[:-4] if nm.lower().endswith(".cls") else nm
        # only class docs (skip .mac/.inc/.hl7/etc. and non-dotted names)
        if "." not in base or nm.lower().rsplit(".", 1)[-1] in ("mac", "inc", "int", "hl7", "txt"):
            continue
        # not ours to rename, and a read is introspection rather than authoring (#221)
        if is_system_class(base) or not authoring:
            continue
        segs = base.split(".")
        type_segs = segs[1:-1] if len(segs) > 2 else []
        for seg in type_segs:
            if seg in NONSTD:
                deny(
                    "NAME",
                    "Naming convention: '%s' uses the non-standard package segment '.%s.' for a "
                    "class you are AUTHORING. iris-interop uses <Package>.<Tipo>.<Name> with Tipo "
                    "in BS/BP/BO/DT/RUL/MSG — rename '.%s.' to '.%s.' and retry.\n\n"
                    "If this class is NOT yours — an InterSystems class such as "
                    "EnsLib.HL7.Service.FileService, or generated code you must reference by its "
                    "shipped name — do not rename it: reference it as-is, and read it with "
                    "docs_introspect(class_name=...) or iris_doc(mode=get). This rule only covers "
                    "classes you write. If it fired on one of those, report it.\n\n"
                    "Convention: give the renamed class `/// Convention: CONV-Q4X` as its first "
                    "doc comment, so the rename is auditable.\n\n"
                    "Load Skill(iris-interop-skills:component-map) for the "
                    "task->component->type map." % (nm, seg, seg, NONSTD[seg])
                )

    if content and authoring:
        # (5) `_` in an identifier. The compiler blames the braces; the name is the problem (#219).
        for m in UNDERSCORE_MEMBER.finditer(mask_xdata(content)):
            if m.group("q") == '"':
                continue              # delimited member name — legal (GOBJ §2.6.3 / RCOS §A.9)
            bad = m.group("name")
            good = "".join(part[:1].upper() + part[1:] for part in bad.split("_") if part)
            deny(
                "UNDERSCORE",
                "'%s' is not a legal IRIS identifier: class, package and member names are letters "
                "and digits only — `_` is the concatenation operator (RCOS Appendix A, "
                "\u00a7\u00a7A.7/A.9).\n\n"
                "The compiler does NOT say this. It reports\n"
                "  ERROR #5559: ... possibly due to non-matching {} or () characters\n"
                "(or #16006 'name is invalid' for the class name), and the braces are fine. "
                "Do not count braces; fix the name.\n\n"
                "Rename to '%s' and retry. HL7 type names are the usual source: the message type "
                "is ADT_A01, so ADT_A01ToMenuReq becomes AdtA01ToMenuReq. The string 'ADT_A01' "
                "stays as-is wherever it is DATA (MessageSchemaCategory, DocType, an XData schema, "
                "a Lookup() key) — only identifiers are affected."
                % (bad, good)
            )

        # Anchored to a real class-definition line: skips /// comments and prose, and accepts both
        # `Extends Super` and the parenthesized list `Extends (A, B)` the plugin's own examples use.
        cm = re.search(r"(?im)^\s*Class\s+([A-Za-z0-9_.%]+)\s+Extends\s+(\(?[^{\n]+)", content)
        if cm:
            cls_name = cm.group(1)
            supers = [s.strip().strip("()") for s in cm.group(2).split(",")]
            adapter = next((s for s in supers if re.search(r"(?:Inbound|Outbound)Adapter$", s)), None)
            if adapter:
                # Pair against the class declared IN THIS CONTENT, not the union of `names`.
                base = cls_name[:-4] if cls_name.lower().endswith(".cls") else cls_name
                segs = base.split(".")
                type_segs = segs[1:-1] if len(segs) > 2 else []
                # Honour the docstring: a genuine custom adapter is left alone.
                is_adapter = cls_name.endswith("Adapter") or "Adapter" in type_segs
                if not is_adapter and any(s in BS_BO_SEGS for s in type_segs):
                    deny(
                        "ADAPTER",
                        "A Business Service/Operation must Extend Ens.BusinessService / Ens.BusinessOperation "
                        "and declare its adapter as `Parameter ADAPTER = \"%s\";` — not Extend the adapter "
                        "(%s) directly (that yields an empty, non-functional component). Fix the superclass + "
                        "ADAPTER parameter and retry. See Skill(iris-interop-skills:business-services) / "
                        ":business-operations." % (adapter, adapter)
                    )

    # no output -> allow


if __name__ == "__main__":
    main()
