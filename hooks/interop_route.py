#!/usr/bin/env python3
"""UserPromptSubmit topic router for iris-interop-skills (#218).

SessionStart names three fixed skills -- interop, component-map, tdd -- and it is injected
once, before anyone knows what the task is. Two measured consequences: when HL7 work arrives
mid-session nothing says "load transformations" or "load hl7-schemas", and the model probes the
EnsLib.HL7.Segment API blind; and when the first prompt is "read this file and run step 1", the
reflex is to dispatch subagents, which do NOT receive SessionStart additionalContext at all --
they then Read skills/*/SKILL.md as plain files and hand back a summary the whole build rests on.

Measured: 6 of 31 sessions with >=10 MCP calls made ZERO Skill() calls, the longest session of
the day (459 MCP calls) among them.

This runs on every user turn: match the prompt against the same trigger vocabulary the skill
frontmatters publish, and name the two or three skills that actually apply. ADVISORY ONLY --
additionalContext, never a decision and never a deny. A prompt that matches nothing stays silent
and costs one regex pass.

DELIBERATELY NOT A DENY, and not a PreToolUse gate over Read/Grep of a SKILL.md. The plugin
documents reading a SKILL.md as a plain file -- conformance-review/SKILL.md ("However you arrived
here -- the Skill tool, a native-skill search, or reading the file directly"), interop/SKILL.md
("via the Skill tool where available, else read the file"). A deny would break that documented
escape hatch for environments with no Skill tool.
"""
import sys, json, re

MARKER = "[IIS-ROUTE] "
MAX = 3

# (skill, trigger alternation). EN + ES: the triggers in every frontmatter are bilingual.
TOPICS = [
    ("hl7-schemas", r"\bZ-?segment|segmento\s+Z|\bZ[A-Z]{2}\b|custom\s+HL7\s+schema|esquema\s+HL7|DocType|MessageStructure|EnsLib\.HL7|\bADT[_^]?[A-Z]?\d*\b|\bORU[_^]?[A-Z]?\d*\b|\bMSH\b"),
    ("transformations", r"\bDTL\b|data\s*transform|transformaci|subtransform|mapear|GetValueAt|\{[A-Z0-9]{3}:"),
    ("business-services", r"RecordMap|Record\s+Map(per)?|\bCSV\b|inbound|business\s+service|servicio\s+de\s+entrada|fichero\s+de\s+entrada|MLLP"),
    ("business-operations", r"business\s+operation|outbound|\bJDBC\b|SQL\s+[Gg]ateway|pasarela\s+SQL|operaci[óo]n\s+de\s+salida"),
    ("bpl", r"MessageRouter|routing\s+rule|regla\s+de\s+enrutamiento|enrutador|router|\bBPL\b|business\s+process"),
    ("messages", r"message\s+class|clase\s+de\s+mensaje|Ens\.Request|Ens\.Response"),
    ("lookup-tables", r"lookup\s+table|tabla\s+de\s+b[úu]squeda|Ens\.Util\.LookupTable"),
    ("production-lifecycle", r"producci[óo]n|\bproduction\b|arrancar|UpdateProduction|Ens\.Director|deploy"),
    ("message-search-debug", r"visual\s+trace|event\s+log|Ens\.MessageHeader|Ens_Util\.Log|ha\s+llegado|reenviar|resend|queue\s+depth"),
    ("tdd", r"\btests?\b|prueba|%UnitTest|\bTDD\b"),
    ("fhir", r"\bFHIR\b|SMART.on.FHIR"),
    ("dicom", r"\bDICOM\b|C-STORE|C-FIND|C-MOVE|\bMWL\b|\bPACS\b"),
    ("alerting", r"Ens\.Alert|alerta|alert\s+on\s+error"),
    ("security", r"\bSAML\b|OAuth|\bLDAP\b|ZAUTHENTICATE|SSL/TLS"),
]


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    prompt = data.get("prompt") or ""
    if not isinstance(prompt, str) or not prompt:
        return
    hits = [s for s, pat in TOPICS if re.search(pat, prompt, re.I)][:MAX]
    if not hits:
        return
    calls = ", ".join("Skill(iris-interop-skills:%s)" % s for s in hits)
    msg = (
        "This turn is about: " + ", ".join(hits) + ". Call " + calls + " NOW, in this turn, "
        "before writing or running any code -- the API answers you are about to guess at are in "
        "them. If you delegate this work to a subagent, repeat the same Skill(...) calls inside "
        "the subagent's prompt: session-start context does NOT reach subagents, and a subagent "
        "that Reads a SKILL.md gives you a summary, not a loaded skill."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": MARKER + msg}}))


if __name__ == "__main__":
    main()
