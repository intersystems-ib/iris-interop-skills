/// Rule: BestPractices_Interop_IRIS.md §2.3 "Escape special characters when constructing HL7 v2 strings"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Trace:
///   DEMO>w ##class(Demo.UTL.FunctionSet).FormataTextPerHL7v2("hola | ^ ~ \ & que tal"_$C(13,10))
///   hola \F\ \S\ \R\ \E\ \T\ que tal\X0D\\X0A\
///
///   DEMO>w ##class(Demo.UTL.FunctionSet).DesformataTextDesdeHL7v2("hola \F\ \S\ \R\ \E\ \T\ que tal\X0D\\X0A\")
///   hola | ^ ~ \ & que tal
///
///   Round trip over text that ALREADY contains a backslash. This is the case a decoder built
///   from reverse-order $Replace calls gets wrong — it returns a\E|E\b, silently corrupting the
///   free text the escaping exists to protect:
///   DEMO>w ##class(Demo.UTL.FunctionSet).FormataTextPerHL7v2("a\F\b")
///   a\E\F\E\b
///   DEMO>w ##class(Demo.UTL.FunctionSet).DesformataTextDesdeHL7v2("a\E\F\E\b")
///   a\F\b
///
///   Round-trip assertions worth keeping in a unit test — Desformata(Formata(x)) = x for:
///   "a\F\b", "a|b", "hola | ^ ~ \ & que tal", "a\X0D\b".
///
/// Ensemble auto-escapes HL7 v2 special chars when it generates the message itself
/// (e.g. a system-generated NACK). When you build an HL7 message manually
/// (e.g. a custom NACK in a BP catch), you MUST escape these chars via a helper like this.
/// Without escaping, a `|` inside a free-text field collapses the segment structure
/// and the receiver gets a malformed message.
Class Demo.UTL.FunctionSet Extends Ens.Rule.FunctionSet
{

/// Escape the HL7v2 special characters in `pText` so it is safe to drop into a field.
/// Order matters: `\` must be escaped FIRST, otherwise we'd re-escape the `\` characters
/// introduced by the other rules.
ClassMethod FormataTextPerHL7v2(pText As %String) As %String
{
    set pText = $Replace(pText, "\", "\E\")    // backslash FIRST
    set pText = $Replace(pText, "|", "\F\")    // field separator
    set pText = $Replace(pText, "^", "\S\")    // component separator
    set pText = $Replace(pText, "~", "\R\")    // repetition separator
    set pText = $Replace(pText, "&", "\T\")    // sub-component separator
    set pText = $Replace(pText, $Char(13), "\X0D\")
    set pText = $Replace(pText, $Char(10), "\X0A\")
    quit pText
}

/// Inverse of FormataTextPerHL7v2: a single left-to-right scan that consumes each `\...\`
/// token exactly once.
///
/// Do NOT try to invert the encoder with $Replace calls in reverse order. $Replace is
/// position-blind, so an escape emitted by one rule is re-matched by the next ACROSS the
/// boundary between two escapes: "a\F\b" encodes to "a\E\F\E\b", and a `$Replace(…,"\F\","|")`
/// there matches the closing `\` of the first `\E\`, the `F`, and the opening `\` of the
/// second `\E\` — yielding "a\E|E\b". Scanning once cannot make that mistake, because every
/// character is consumed by at most one token.
ClassMethod DesformataTextDesdeHL7v2(pText As %String) As %String
{
    #Dim tOut As %String = ""
    #Dim tToken As %String
    #Dim tPos As %Integer = 1
    #Dim tEnd As %Integer
    #Dim tLen As %Integer = $Length(pText)

    while tPos <= tLen {
        if $Extract(pText, tPos) '= "\" {
            set tOut = tOut _ $Extract(pText, tPos), tPos = tPos + 1
            continue
        }
        // On a `\`: read forward to the closing `\`. $Find returns the position AFTER it.
        set tEnd = $Find(pText, "\", tPos + 1)
        if tEnd = 0 {
            // Unterminated escape — emit the remainder verbatim rather than dropping it.
            set tOut = tOut _ $Extract(pText, tPos, tLen), tPos = tLen + 1
            continue
        }
        set tToken = $Extract(pText, tPos + 1, tEnd - 2)   // the text BETWEEN the delimiters
        set tOut = tOut _ ..DecodeEscapeToken(tToken)
        set tPos = tEnd
    }
    quit tOut
}

/// Map one HL7 escape token — the text BETWEEN the two `\` delimiters — to its literal.
/// Anything FormataTextPerHL7v2 never emits (`\Xdddd\` other than X0D/X0A, `\Zxxx\`, `\.br\`,
/// the empty token of a literal `\\`) is passed through re-wrapped in its delimiters, so no
/// input is ever silently dropped.
ClassMethod DecodeEscapeToken(pToken As %String) As %String [ Private ]
{
    quit $Case(pToken, "F":"|", "S":"^", "R":"~", "T":"&", "E":"\", "X0D":$Char(13), "X0A":$Char(10), :"\"_pToken_"\")
}

}
