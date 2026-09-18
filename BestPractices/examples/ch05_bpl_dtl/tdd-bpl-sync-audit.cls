/// Rule: BestPractices_Interop_IRIS.md §5.19 "`<flow>`/`<sync>` fan-out: an async `<call>` that no `<sync>` awaits completes the process green"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (the audit is only worth having if it is trusted, and it is only trustworthy if its blind spots are asserted).
///
/// Pattern: the oracle for `utl-bpl-sync-audit.cls`, and the executable half of §5.19 — the template
/// itself is compiled but cannot be driven without a started production and two live targets.
///
/// THE DEFECT IT GUARDS CANNOT BE CAUGHT BY A COMPILE. Measured on 2026.1: a BPL whose
/// `<sync calls='AskVendor'>` omits the second of two async calls **compiles clean**, and so does one
/// with no `<sync>` at all. The process reaches its end activity with a call outstanding and
/// completes. So the only way to find it is to read the definition back, which is what the audit does
/// and what this test exercises.
///
/// FEEDING DEFECTS AS TEXT, not as classes. `AuditText()` takes raw XML so the broken variants live
/// inside this test rather than as shipped artefacts. A bank that ships a deliberately-broken BPL has
/// to explain it on every future read, and tier 2 would compile it — which, since the defect compiles
/// clean, would prove nothing anyway.
///
/// ONE TEST EXISTS BECAUSE THE AUDIT WAS WRONG FIRST. `TestReflowedXmlGivesTheSameVerdict` was
/// written expecting the audit to ANNOUNCE a blind spot on re-flowed XML. It did not announce
/// anything: iterating lines, it found the first `name=` on the single line and reported
/// "OK: 1 async call(s), all awaited" for a two-call process — a clean bill of health it had not
/// earned, which is the worst of the three possible behaviours. The audit now splits on `<` instead,
/// and the test asserts that layout does not change the verdict.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                      PASSED 10/10
///     un-awaited-call finding removed                  4 tests FAIL
///     reverse-typo finding removed                     TestSyncNamingAMissingCallIsFound   FAILS
///     "no async calls" returns OK instead of refusing  TestNoAsyncCallsIsNotAPass +
///                                                      TestSyncCallsAreNotAudited          FAIL
///     CANNOT AUDIT guard removed                       TestNotABplRefuses                  FAILS
///     back to LINE-based scanning                      6 tests FAIL
///     double-quote support removed                     TestDoubleQuotedAttributesAreRead   FAILS
///
/// All seven versions compile. The line-based mutation reddening six tests is the regression the
/// element-based scan prevents, and it is the one that shipped first.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.BplSyncAudit", namespace="<NS>")
Class Example.Tests.BplSyncAudit Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Two async calls in a flow, both awaited. The shape of the shipped template, as text.
ClassMethod GoodXml() As %String [ Private ]
{
    Set tNl = $Char(10)
    Set x = "<process language='objectscript'>" _ tNl
    Set x = x _ "<sequence>" _ tNl
    Set x = x _ "<flow name='Fan out'>" _ tNl
    Set x = x _ "<call name='AskVendor' target='BO.Vendor' async='1'>" _ tNl
    Set x = x _ "</call>" _ tNl
    Set x = x _ "<call name='AskLab' target='BO.Lab' async='1'>" _ tNl
    Set x = x _ "</call>" _ tNl
    Set x = x _ "</flow>" _ tNl
    Set x = x _ "<sync name='Await both' calls='AskVendor,AskLab' type='all' timeout='60'/>" _ tNl
    Set x = x _ "</sequence>" _ tNl
    Set x = x _ "</process>" _ tNl
    Quit x
}

/// POSITIVE CONTROL. The shipped template must audit clean -- otherwise every "finding" assertion
/// below could be produced by an audit that reports a finding for everything.
Method TestTemplateIsClean()
{
    Set tOut = ##class(Example.UTL.BplSyncAudit).Audit("Example.BP.FlowSyncAggregate")
    Do $$$AssertEquals($Find(tOut, "OK:") > 0, 1, "the shipped template must audit clean: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "2 async call(s)") > 0, 1, "and it must say it found both calls")
    Do $$$AssertEquals($Find(tOut, "FINDING") > 0, 0, "with no findings")

    // And the same shape as text, so a failure above localises to the class-reading half.
    Set tText = ##class(Example.UTL.BplSyncAudit).AuditText(..GoodXml())
    Do $$$AssertEquals($Find(tText, "OK:") > 0, 1, "the equivalent XML text also audits clean: " _ tText)
}

/// THE POINT. A sync that omits one of two async calls.
Method TestUnawaitedCallIsFound()
{
    Set tBad = $Replace(..GoodXml(), "calls='AskVendor,AskLab'", "calls='AskVendor'")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tBad)

    Do $$$AssertEquals($Find(tOut, "FINDING") > 0, 1, "an un-awaited async call must be reported")
    Do $$$AssertEquals($Find(tOut, "AskLab") > 0, 1, "and named: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "OK:") > 0, 0, "and the verdict must not also say OK")
}

/// No sync at all -- the same defect, written differently.
Method TestMissingSyncIsFound()
{
    Set tBad = $Replace(..GoodXml(), "<sync name='Await both' calls='AskVendor,AskLab' type='all' timeout='60'/>", "")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tBad)

    Do $$$AssertEquals($Find(tOut, "FINDING") > 0, 1, "with no <sync> at all, BOTH calls are un-awaited")
    Do $$$AssertEquals($Find(tOut, "AskVendor") > 0, 1, "AskVendor reported")
    Do $$$AssertEquals($Find(tOut, "AskLab") > 0, 1, "AskLab reported")
}

/// The same typo from the other side: a sync awaiting a call that does not exist.
Method TestSyncNamingAMissingCallIsFound()
{
    Set tBad = $Replace(..GoodXml(), "calls='AskVendor,AskLab'", "calls='AskVendor,AskLabb'")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tBad)

    Do $$$AssertEquals($Find(tOut, "AskLabb") > 0, 1, "a sync naming a non-existent call must be reported: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "AskLab'") > 0, 1, "and the real call it left un-awaited, too")
}

/// A synchronous call is not an async one and must not be demanded of a sync.
Method TestSyncCallsAreNotAudited()
{
    Set tSyncOnly = $Replace(..GoodXml(), "async='1'", "async='0'")
    Set tSyncOnly = $Replace(tSyncOnly, "<sync name='Await both' calls='AskVendor,AskLab' type='all' timeout='60'/>", "")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tSyncOnly)

    Do $$$AssertEquals($Find(tOut, "FINDING") > 0, 0, "synchronous calls need no <sync>: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "NO ASYNC CALLS FOUND") > 0, 1, "and the audit says it found no async calls rather than OK")
}

/// "I recognised nothing" must not read as "nothing is wrong".
Method TestNoAsyncCallsIsNotAPass()
{
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText("<process><sequence></sequence></process>")
    Do $$$AssertEquals($Find(tOut, "Not a clean report") > 0, 1, "an empty process must not produce an OK verdict: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "OK:") > 0, 0, "specifically not OK")
}

/// LAYOUT INDEPENDENCE, asserted. The first version of the audit iterated LINES, and on XML re-flowed
/// onto one line it reported `OK: 1 async call(s), all awaited` for a two-call process -- a false
/// clean, which is worse than a miss it admits to. The audit now splits on `<`, and this test is what
/// keeps the two layouts agreeing.
Method TestReflowedXmlGivesTheSameVerdict()
{
    Set tMultiLine = ##class(Example.UTL.BplSyncAudit).AuditText(..GoodXml())
    Set tOneLine = ##class(Example.UTL.BplSyncAudit).AuditText($Replace(..GoodXml(), $Char(10), " "))
    Do $$$AssertEquals(tOneLine, tMultiLine, "layout must not change the verdict: multi=[" _ tMultiLine _ "] one=[" _ tOneLine _ "]")
    Do $$$AssertEquals($Find(tOneLine, "2 async call(s)") > 0, 1, "and BOTH calls must be seen on one line, not just the first")

    // The defect must also still be found on one line.
    Set tBadOneLine = $Replace($Replace(..GoodXml(), $Char(10), " "), "calls='AskVendor,AskLab'", "calls='AskVendor'")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tBadOneLine)
    Do $$$AssertEquals($Find(tOut, "AskLab") > 0, 1, "and the un-awaited call is still reported: " _ tOut)
}

/// Double-quoted attributes must work too -- a hand-edited BPL may not use the editor's single quotes.
Method TestDoubleQuotedAttributesAreRead()
{
    Set tDq = $Replace(..GoodXml(), "'", """")
    Set tOut = ##class(Example.UTL.BplSyncAudit).AuditText(tDq)
    Do $$$AssertEquals($Find(tOut, "2 async call(s)") > 0, 1, "double-quoted attributes are read: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "FINDING") > 0, 0, "and the clean case stays clean")
}

/// A class with no XData BPL is one this audit cannot speak about.
Method TestNotABplRefuses()
{
    Set tOut = ##class(Example.UTL.BplSyncAudit).Audit("Example.UTL.BplSyncAudit")
    Do $$$AssertEquals($Find(tOut, "CANNOT AUDIT") > 0, 1, "a non-BPL class must be refused: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "OK:") > 0, 0, "and must not be reported clean")
}

}
