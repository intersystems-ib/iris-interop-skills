#!/usr/bin/env python3
"""PreToolUse conformance GATE for iris_doc / iris_compile / iris_execute (iris-interop-skills).

Unlike the PostToolUse advisories (which a weak model ignores), this BLOCKS the write/compile
when a class violates a hard, unambiguous iris-interop convention, forcing a fix before the
class lands. It denies only high-confidence violations (no false positives on ordinary code):

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
# Deliberately NOT listed, because the same capture proves they are fine without it:
# `check_config` (0/41 failures) and `iris_get_log` (0/40). A blanket rule would be wrong.
# Also not listed: iris_doc / iris_compile / iris_query / iris_execute / iris_test /
# iris_interop_query — every observed call already passed `namespace`, so there is no evidence
# either way and the gate does not guess.
NS_REQUIRED = {
    "iris_production", "iris_production_item", "iris_credential_list",
    "iris_credential_manage", "iris_lookup_manage", "iris_lookup_transfer",
}


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
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
    names = collect_names(ti)
    content = ti.get("content") if isinstance(ti.get("content"), str) else ""

    # (4) interop tool called without `namespace` — 95% of these fail, and the error that comes
    # back names Ens.Director or a missing ENS_* table instead of the namespace. Cheaper to stop
    # here: adding an explicit namespace is never wrong, so a false positive costs one parameter.
    tool = str(data.get("tool_name") or "").split("__")[-1]
    if tool in NS_REQUIRED and not ti.get("namespace"):
        deny(
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
    code = ti.get("code") if isinstance(ti.get("code"), str) else ""
    if code:
        m = OBJ_BYPASS.search(code)
        if m:
            deny(
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
            m = pattern.search(code)
            if m:
                deny(
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

    for nm in names:
        base = nm[:-4] if nm.lower().endswith(".cls") else nm
        # only class docs (skip .mac/.inc/.hl7/etc. and non-dotted names)
        if "." not in base or nm.lower().rsplit(".", 1)[-1] in ("mac", "inc", "int", "hl7", "txt"):
            continue
        segs = base.split(".")
        type_segs = segs[1:-1] if len(segs) > 2 else []
        for seg in type_segs:
            if seg in NONSTD:
                deny(
                    "Naming convention: '%s' uses the non-standard package segment '.%s.'. "
                    "iris-interop uses <Package>.<Tipo>.<Name> with Tipo in BS/BP/BO/DT/RUL/MSG — "
                    "rename '.%s.' to '.%s.' and retry. Load Skill(iris-interop-skills:component-map) "
                    "for the task->component->type map." % (nm, seg, seg, NONSTD[seg])
                )

    if content:
        m = re.search(r"Extends\s+([A-Za-z0-9_.%]*(?:Inbound|Outbound)Adapter)\b", content)
        if m:
            looks_bs_bo = any(s in BS_BO_SEGS for nm in names for s in nm.split("."))
            if looks_bs_bo:
                adapter = m.group(1)
                deny(
                    "A Business Service/Operation must Extend Ens.BusinessService / Ens.BusinessOperation "
                    "and declare its adapter as `Parameter ADAPTER = \"%s\";` — not Extend the adapter "
                    "(%s) directly (that yields an empty, non-functional component). Fix the superclass + "
                    "ADAPTER parameter and retry. See Skill(iris-interop-skills:business-services) / "
                    ":business-operations." % (adapter, adapter)
                )
    # no output -> allow


if __name__ == "__main__":
    main()
