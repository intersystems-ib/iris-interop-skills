#!/usr/bin/env python3
"""SessionStart bootstrap for iris-interop-skills.

Proactively injects the core interop conventions at session start so a weak model has them WITHOUT
having to choose to call the Skill tool (observed: a Haiku run never invoked any skill despite them
being installed + instructed). This is the "make it available up front" half; the PreToolUse gate
(interop_conformance_gate) is the "make it binding" half.
"""
import sys, json, os

# Stable marker (#162): prepended, never woven into the prose. #115 detects "did any
# hook run in this CLI at all" from this very message -- 318/318 claude runs carry it,
# 0/676 codex and 0/289 opencode do -- so its text is load-bearing for a published
# measurement and must stay greppable across rewordings.
MARKER = "[IIS-BOOTSTRAP] "

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import iis_scm
except Exception:
    iis_scm = None      # a broken sibling must leave the default (git) wording, never no wording


# RULE 7 IS THE ONE RULE THAT INVERTS UNDER CCR (#410), so it is the one the bootstrap swaps.
# Everything else in this message -- namespace= on every call, no class loading through
# iris_execute, superclasses, router plus rule, TDD, the conformance pass -- is unaffected and is
# stated identically in both modes.
RULE7_FILES = (
    "(7) THE FILESYSTEM IS THE SOURCE OF TRUTH — never let a class exist only in the IRIS "
    "namespace. Write src/<Pkg>/<Tipo>/<Name>.cls FIRST, then iris_doc(mode=put) the same "
    "content; a PreToolUse gate BLOCKS a put whose class has no file on disk. Classes generated "
    "by IRIS (RecordMap .Record, SOAP WSC.*) are the exception — export them with "
    "iris_doc(mode=get) right after generating; "
)

# Deliberately does NOT tell the model to write src/ first, because under CCR that is the defect:
# a stale local copy put back over a checked-out server version loses the server's work silently.
RULE7_CCR = (
    "(7) " + (iis_scm.MARKER if iis_scm else "") +
    "THIS PROJECT USES CCR, SO THE IRIS BASE NAMESPACE IS THE SOURCE OF TRUTH — "
    "the opposite of this plugin's default, and a local src/ is invisible to CCR. Before editing an "
    "existing document: check it out, then iris_doc(mode=get) it, THEN edit and iris_doc(mode=put). "
    "A get in this session is what the PreToolUse gate looks for, so do not skip it — putting a "
    "local copy over a version you have not read is how the server's work disappears. Undo the "
    "check-out on anything you did not actually change. NEVER Bundle, Upload, move a CCR through "
    "its workflow, peer-review your own change, %Disconnect or TakeOwnership — those are the "
    "human's, always. There is no local commit: the human bundles in the CCR UI; "
)

def _msg(root=None):
    RULE7 = RULE7_CCR if (iis_scm and iis_scm.is_ccr(root)) else RULE7_FILES
    return (
    "iris-interop-skills active. For ANY IRIS Interoperability work, BEFORE writing classes: load "
    "Skill(iris-interop-skills:interop) (router) + Skill(iris-interop-skills:component-map) + "
    "Skill(iris-interop-skills:tdd). To build or modify a whole component end-to-end, hand it to "
    "Agent(subagent_type=\"iris-interop-skills:interop-builder\") instead of assembling it yourself; "
    "to start a production and prove a message actually flowed, hand that to "
    "Agent(subagent_type=\"iris-interop-skills:deploy-smoke-test\"). Both are AGENTS, not skills: a "
    "skill name is not a valid subagent_type. "
    "On EVERY Agent(...) delegation here, pass run_in_background=false and wait for its "
    "result: measured 3 of 3 in headless `claude -p` runs, an Agent call with the flag UNSET "
    "starts in the background (Claude Code's own subagent_stats.started_in_background=1) and "
    "the turn can end with the component half-built. "
    "Non-negotiable conventions (a PreToolUse gate will BLOCK violations): "
    "(1) name classes <Package>.<Tipo>.<Name> with Tipo in BS/BP/BO/DT/RUL/MSG — never "
    "Service/Operation/Process/Transform/Message. Class AND member names are letters and digits "
    "ONLY: `_` is the concatenation operator, so Pkg.DT.ADT_A01ToMenuReq and "
    "Method TestADT_A01() abort the parser with the misleading ERROR #5559 'non-matching {} or () "
    "characters' — the braces are fine, the name is not. Write AdtA01ToMenuReq. 'ADT_A01' stays "
    "as-is wherever it is DATA (DocType, MessageSchemaCategory, an XData schema); "
    "(2) a Business Service/Operation Extends Ens.BusinessService/Ens.BusinessOperation with "
    "Parameter ADAPTER=\"...\" — never Extend the adapter directly; "
    "(3) route with a MessageRouter + business rule, not a hand BusinessProcess OnRequest; "
    "(4) reach IRIS ONLY through the MCP (iris_doc/iris_compile/iris_test) — never iris.exe / "
    "iris session / $SYSTEM.OBJ.Load / $SYSTEM.OBJ.Compile; "
    "(5) TDD: a component is done only when its %UnitTest.TestProduction actually runs GREEN via "
    "iris_test (NO_TESTS_FOUND means compile the test first and pass the exact class name); "
    "(6) NAMESPACE DISCIPLINE: resolve the target namespace from the task ONCE, verify it with "
    "check_config, and pass namespace= explicitly on EVERY MCP call — never a tool default (USER "
    "is almost never the interop namespace, and a run can finish green in the wrong one). On "
    "iris_production / iris_production_item / iris_credential_* / iris_lookup_* omitting it also "
    "fails ~95% of the time with an internal error that never names the cause (<CLASS DOES NOT "
    "EXIST> Ens.Director, or Table 'ENS_CONFIG.CREDENTIALS' not found); " +
    RULE7 +
    "(8) BEFORE DECLARING DONE, run the conformance pass — hand the finished production to "
    "Agent(subagent_type=\"iris-interop-skills:conformance-reviewer\"). Only if you cannot "
    "delegate, load Skill(iris-interop-skills:conformance-review) and check the seventeen criteria "
    "inline. A Stop "
    "hook enforces this: it blocks once if any class you put into IRIS has no file on disk "
    "(CR-12), if a hand Ens.BusinessProcess calls SendRequestAsync and overrides no OnResponse "
    "(CR-15 \u2014 measured: every reply then terminates with ERROR #5003), or if the pass never "
    "ran. "
    "WHICH SKILL FOR WHAT (call it the moment the topic appears, not at session start): "
    "DTL / field mapping -> transformations; Z-segments or a custom HL7 schema -> hl7-schemas; "
    "RecordMap / CSV / file or TCP inbound -> business-services; SQL-JDBC / HTTP / file outbound "
    "-> business-operations; MessageRouter or routing rule -> bpl; lookup tables -> lookup-tables; "
    "looking at a running production -> message-search-debug. And when you delegate to a subagent, "
    "repeat the Skill(...) calls in ITS prompt — this message does not reach subagents."
)


def _scm_warning(root):
    """Surface an unrecognised IRIS_INTEROP_SCM once, at session start.

    Falling back to `files` on a typo is right -- it keeps blocking gates exactly as they were --
    but doing it SILENTLY leaves an operator who meant `ccr` with every CCR gate inactive and no
    signal. The MCP reports the same thing as `scm_mode_warning` on check_config.
    """
    if iis_scm is None:
        return ""
    try:
        w = iis_scm.unrecognised(root)
    except Exception:
        return ""
    return ("\n\n" + iis_scm.MARKER + w) if w else ""


def _root(data):
    """The project dir, for iis_scm's .claude/iis-scm fallback.

    `cwd` is present on the SessionStart payload -- verified against real captured payloads, where
    it appears on every hook event -- and CLAUDE_PROJECT_DIR is the documented env fallback.
    """
    if isinstance(data, dict) and data.get("cwd"):
        return data["cwd"]
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def main():
    # The SessionStart payload was read and ignored so stdin would not block the wrapper. It is
    # now also the best source of the project directory: `cwd` is present on every real hook
    # payload, and iis_scm needs a root for its .claude/iis-scm fallback (#410). Still tolerant --
    # a payload that will not parse must not cost the session its conventions.
    data = {}
    try:
        parsed = json.load(sys.stdin)
        if isinstance(parsed, dict):
            data = parsed
    except Exception:
        pass
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": MARKER + _msg(_root(data)) + _scm_warning(_root(data))}}))


if __name__ == "__main__":
    main()
