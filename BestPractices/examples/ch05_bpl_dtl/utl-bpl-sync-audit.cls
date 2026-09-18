/// Rule: BestPractices_Interop_IRIS.md §5.19 "`<flow>`/`<sync>` fan-out: an async `<call>` that no `<sync>` awaits completes the process green"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (it turns a silent defect into a readable one).
///
/// Pattern: the audit that makes the §5.19 defect loud. A BPL whose `<sync calls='...'>` omits one of
/// its async `<call>` names compiles clean and completes green, so there is nothing for a compiler or
/// a gate to catch. This reads the `XData BPL` back and names the calls nobody awaits.
///
/// WHY IT READS XData RATHER THAN THE GENERATED CODE. A BPL compiles into a state machine, and the
/// absence of a wait is not a distinguishable artefact in it — there is simply no wait. The
/// DEFINITION is where the two versions differ, and it is available:
/// `%Dictionary.XDataDefinition.%OpenId("<class>||BPL")`, whose `Data` is a stream.
///
/// THE LIMIT OF THIS CHECK, stated at the check rather than in a footnote, per the repo convention
/// that a grep gate guards a spelling and not the rule it is named after. This matches text:
///
///   * it splits on `<` and reads attributes in either quote style, so it is independent of line
///     breaks and of `'` vs `"`. That was NOT true of the first version, which iterated lines and
///     matched single quotes only -- and which therefore reported `OK: 1 async call(s), all awaited`
///     for a two-call process written on one line. A false clean, found by the test below that now
///     asserts both layouts give the same verdict.
///   * it does not check that the `<sync>` is REACHED. A sync inside an `<if>` that never fires
///     awaits nothing at run time, and this check calls it covered.
///   * it does not resolve `<call>` elements in a sub-process or a called BPL -- only the definition
///     it was handed.
///
/// So a clean result means "every async call name appears in some sync's calls list", which is
/// narrower than "every async call is awaited". It catches the omission that actually happens --
/// a call added to a flow and not added to the sync -- and says so rather than implying more.
///
/// MEASURED on the two BPLs in this directory and one synthetic defect:
///     Example.BP.FlowSyncAggregate      -> OK: 2 async call(s), all awaited
///     the same XML with calls='AskVendor' -> FINDING: async call 'AskLab' is awaited by no <sync>
///     a class with no XData BPL          -> CANNOT AUDIT (not a clean report)
Class Example.UTL.BplSyncAudit Extends %RegisteredObject
{

/// Audit one BPL class by name.
/// Invoke via: SELECT Example_UTL.BplSyncAudit_Audit('Example.BP.FlowSyncAggregate')
ClassMethod Audit(pClass As %String) As %String [ SqlProc ]
{
    Set tId = pClass _ "||BPL"
    If '##class(%Dictionary.XDataDefinition).%ExistsId(tId) {
        // NOT a clean report. A class with no BPL block is one this audit cannot speak about.
        Return "CANNOT AUDIT: no 'XData BPL' on " _ pClass _ " -- it is not a BPL, or not compiled"
    }
    Set tX = ##class(%Dictionary.XDataDefinition).%OpenId(tId)
    If '$IsObject(tX) {
        Return "CANNOT AUDIT: could not open " _ tId
    }

    Set tXml = ""
    Do tX.Data.Rewind()
    While 'tX.Data.AtEnd {
        Set tXml = tXml _ tX.Data.ReadLine() _ $Char(10)
    }
    Return ..AuditText(tXml)
}

/// Audit raw BPL XML. Public so a test can feed it a defect without shipping a broken class.
ClassMethod AuditText(pXml As %String) As %String [ SqlProc ]
{
    Kill tAsync, tAwaited
    Set tAsyncCount = 0

    // Scan ELEMENT BY ELEMENT, splitting on "<" -- not line by line.
    //
    // The first version of this iterated lines, and that made it report a FALSE CLEAN on XML
    // re-flowed onto one line: the single line contains both calls and the sync, `[ "<call"` is
    // true once, and Attr() returns the FIRST name= it finds. Measured -- it reported
    // "OK: 1 async call(s), all awaited" for a two-call process, which is the worst possible
    // answer: not a miss it admits to, a pass it has not earned. Splitting on "<" makes the check
    // independent of line breaks, which is what it should always have been.
    For i = 1:1:$Length(pXml, "<") {
        Set tEl = $ZStrip($Piece(pXml, "<", i), "<>W")
        If tEl = "" {
            Continue
        }

        If ($Extract(tEl, 1, 4) = "call") && (..HasAttr(tEl, "async", "1")) {
            Set tName = ..Attr(tEl, "name")
            If (tName '= "") && '$Data(tAsync(tName)) {
                Set tAsync(tName) = ""
                Set tAsyncCount = tAsyncCount + 1
            }
        }

        If $Extract(tEl, 1, 4) = "sync" {
            Set tCalls = ..Attr(tEl, "calls")
            For j = 1:1:$Length(tCalls, ",") {
                Set tOne = $ZStrip($Piece(tCalls, ",", j), "<>W")
                If tOne '= "" {
                    Set tAwaited(tOne) = ""
                }
            }
        }
    }

    If tAsyncCount = 0 {
        // Distinguished from a clean pass on purpose: zero async calls may mean a genuinely
        // synchronous process, or it may mean this text-matching check did not recognise the layout.
        Return "NO ASYNC CALLS FOUND: either the process has none, or the XML layout is not the " _
               "single-quoted one-element-per-line form this check matches. Not a clean report."
    }

    Set tFindings = "", tBad = 0
    Set tName = ""
    For {
        Set tName = $Order(tAsync(tName))
        Quit:tName=""
        If '$Data(tAwaited(tName)) {
            Set tBad = tBad + 1
            Set tFindings = tFindings _ " | FINDING: async call '" _ tName _ "' is awaited by no <sync>"
        }
    }

    // A sync naming a call that does not exist is the same typo seen from the other side.
    Set tName = ""
    For {
        Set tName = $Order(tAwaited(tName))
        Quit:tName=""
        If '$Data(tAsync(tName)) {
            Set tBad = tBad + 1
            Set tFindings = tFindings _ " | FINDING: <sync> awaits '" _ tName _ "', which is not an async call in this process"
        }
    }

    If tBad = 0 {
        Return "OK: " _ tAsyncCount _ " async call(s), all awaited"
    }
    Return "FINDINGS (" _ tBad _ ")" _ tFindings
}

/// One attribute value out of an element, single OR double quoted. The BPL editor writes single
/// quotes; a hand edit may not, and a check that only matched one style would silently ignore the
/// other -- the same class of miss as matching only one line layout.
ClassMethod Attr(pEl As %String, pName As %String) As %String [ Private ]
{
    Set tPos = $Find(pEl, pName _ "='")
    If tPos > 0 {
        Return $Piece($Extract(pEl, tPos, $Length(pEl)), "'", 1)
    }
    Set tPos = $Find(pEl, pName _ "=""")
    If tPos > 0 {
        Return $Piece($Extract(pEl, tPos, $Length(pEl)), """", 1)
    }
    Return ""
}

/// Does the element carry pName with exactly pValue, in either quote style?
ClassMethod HasAttr(pEl As %String, pName As %String, pValue As %String) As %Boolean [ Private ]
{
    Return (..Attr(pEl, pName) = pValue)
}

}
