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
PREFIX = "iris-interop-skills:"
MAX = 3

# (skill, trigger alternation). EN + ES: the triggers in every frontmatter are bilingual.
TOPICS = [
    # ccr-workflow is FIRST because ties keep declaration order: a CCR prompt usually names the CCR
    # once and the components several times, and the procedure is the one skill a CCR turn cannot
    # do without. Only CCR-specific vocabulary -- "check out" and "check in" are left to the skill's
    # own description, because on a git project they mean a branch or a commit.
    ("ccr-workflow", r"\bCCR\b|change\s+control|control\s+de\s+cambios|%buildccr|\bItemSet\b|\bPerforce\b|uncommitted\s+(queue|changes?)|cola\s+de\s+cambios|Bundle\s+and\s+Upload|IRIS_INTEROP_SCM|\bIn_BASE\b|mark(PREP|BASE)Complete"),
    ("hl7-schemas", r"\bZ-?segment|segmento\s+Z|\bZ[A-Z]{2}\b|custom\s+HL7\s+schema|esquema\s+HL7|DocType|MessageStructure|EnsLib\.HL7|\bADT[_^]?[A-Z]?\d*\b|\bORU[_^]?[A-Z]?\d*\b|\bMSH\b"),
    ("transformations", r"\bDTL\b|data\s*transform|transformaci|subtransform|mapear|GetValueAt|\{[A-Z0-9]{3}:"),
    ("business-services", r"RecordMap|Record\s+Map(per)?|\bCSV\b|inbound|business\s+service|servicio\s+de\s+entrada|fichero\s+de\s+entrada|MLLP|web\s+app|CSP\s+app|AutheEnabled|sin\s+credenciales"),
    ("business-operations", r"business\s+operation|outbound|\bJDBC\b|SQL\s+[Gg]ateway|pasarela\s+SQL|operaci[óo]n\s+de\s+salida"),
    ("soap-bo", r"\bSOAP\b|\bWSDL\b|SOAP\s+Wizard|web\s+service\s+client|cliente\s+SOAP|%SOAP\."),
    ("bpl", r"MessageRouter|routing\s+rule|regla\s+de\s+enrutamiento|enrutador|router|\bBPL\b|business\s+process"),
    ("messages", r"message\s+class|clase\s+de\s+mensaje|Ens\.Request|Ens\.Response"),
    ("lookup-tables", r"lookup\s+table|tabla\s+de\s+b[úu]squeda|Ens\.Util\.LookupTable"),
    ("production-lifecycle", r"producci[óo]n|\bproduction\b|arrancar|UpdateProduction|Ens\.Director|deploy"),
    ("message-search-debug", r"visual\s+trace|event\s+log|Ens\.MessageHeader|Ens_Util\.Log|ha\s+llegado|reenv[íi]|resend|queue\s+depth|verif|comprobar|comprobaci|did\s+it\s+arrive|how\s+many\s+rows|cu[áa]ntos\s+mensajes|ha\s+funcionado|message\s+viewer|message\s+search|buscar\s+mensaje|troubleshoot|depurar|traza"),
    ("tdd", r"\btests?\b|\bpruebas?\b|%UnitTest|\bTDD\b"),
    ("fhir", r"\bFHIR\b|SMART.on.FHIR"),
    ("dicom", r"\bDICOM\b|C-STORE|C-FIND|C-MOVE|\bMWL\b|\bPACS\b"),
    ("alerting", r"Ens\.Alert|alerta|alert\s+on\s+error"),
    ("security", r"\bSAML\b|OAuth|\bLDAP\b|ZAUTHENTICATE|SSL/TLS|client\s+certificate|certificado|\bPKCE\b|seguridad|autenticaci"),
]


def _loaded_skills(transcript_path):
    """The skills whose BODY is already in THIS session's context (#423).

    Evidence is a Skill tool INVOCATION, parsed as JSON -- never a substring match. This hook's
    own additionalContext contains the literal "Skill(iris-interop-skills:fhir)" and is replayed
    into the transcript, so a substring search would key on "have I advised this before" instead
    of "is the body present". That distinction is the whole of #423: the wrong one silences the
    first legitimate recommendation after a topic change and sends the model back to the blind
    API probing this router was built to stop (#218).

    MEASURED ON A REAL TRANSCRIPT, not a fixture (2026-10-20, a one-day session): the substring
    form reports 12+ skills as already-loaded -- conformance-review named 270 times, component-map
    74, interop 65, plus dicom, messages, report-issue and more -- because SessionStart, this very
    hook and ordinary prose all name skills in text. Exactly ONE of them had actually been loaded,
    and parsing tool_use returns that one. So the forbidden form does not misfire at the margin:
    in a long session it would suppress nearly every route.

    FAILS OPEN. No path, no file, unreadable, unparseable -> empty set, nothing suppressed. The
    polarity is the OPPOSITE of iis_scm.seen_document, which returns True on doubt because there
    "seen" avoids a DENY; here "seen" means "say less", so doubt has to mean "say everything".

    MAIN TRANSCRIPT ONLY, and deliberately so: iis_scm walks <transcript>/subagents/ because a
    delegated EDIT is still this session's edit, but a body loaded inside a subagent sits in the
    SUBAGENT's context. Suppressing on that would strip the very line subagents depend on.
    """
    if not transcript_path:
        return set()
    found = set()
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if PREFIX not in line:
                    continue                      # cheap reject before the JSON parse
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                content = (rec.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    if "skill" not in str(b.get("name") or "").lower():
                        continue
                    inp = b.get("input") or {}
                    if not isinstance(inp, dict):
                        continue
                    name = str(inp.get("skill") or "")
                    if name.startswith(PREFIX):
                        found.add(name[len(PREFIX):])
    except OSError:
        return set()
    return found


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    prompt = data.get("prompt") or ""
    if not isinstance(prompt, str) or not prompt:
        return
    # Rank by how much of the prompt each topic actually matched, THEN slice. Slicing by
    # declaration order alone drops a topic that matched three phrases in favour of one that
    # matched a single incidental word -- and it is why widening a late-declared pattern (
    # message-search-debug is 10th) looked inert before this change. Ties keep declaration order.
    scored = [(len(re.findall(pat, prompt, re.I)), -i, s)
              for i, (s, pat) in enumerate(TOPICS) if re.search(pat, prompt, re.I)]
    hits = [s for _, _, s in sorted(scored, reverse=True)][:MAX]
    if not hits:
        return
    # Split by what is already in context. Only the reload imperative is suppressed; the topic
    # line, the names and the delegation clause survive for every hit.
    loaded = _loaded_skills(data.get("transcript_path"))
    fresh = [s for s in hits if s not in loaded]
    already = [s for s in hits if s in loaded]

    parts = ["This turn is about: " + ", ".join(hits) + "."]
    if fresh:
        calls = ", ".join("Skill(%s%s)" % (PREFIX, s) for s in fresh)
        parts.append("Call " + calls + " NOW, in this turn, before writing or running any code -- "
                     "the API answers you are about to guess at are in them.")
    if already:
        parts.append("Already loaded earlier in this session: "
                     + ", ".join(PREFIX + s for s in already)
                     + " -- cite them from the context you already hold; do NOT re-invoke Skill() "
                     "to pull the same body in again.")
    # EVERY hit, including the already-loaded ones: a subagent inherits neither session-start
    # context nor this session's loaded bodies. The old message named only what it advised, which
    # was the same set -- now it is not, so this clause has to say so explicitly.
    parts.append("If you delegate this work to a subagent, repeat Skill(...) inside the subagent's "
                 "prompt for EVERY skill named above, including any already loaded here: "
                 "session-start context does NOT reach subagents, your own loaded bodies do not "
                 "either, and a subagent that Reads a SKILL.md gives you a summary, not a loaded "
                 "skill.")
    msg = " ".join(parts)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": MARKER + msg}}))


if __name__ == "__main__":
    main()
