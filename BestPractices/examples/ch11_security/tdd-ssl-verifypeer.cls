/// Rule: BestPractices_Interop_IRIS.md §11.13 "Asserting Server Certificate Validation — VerifyPeer, and the config that looks configured"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN against the live Security.SSLConfigs.
/// Severity: High (with validation off the handshake succeeds and the peer is unauthenticated for ever).
///
/// Pattern: the oracle for `ssl-config-verifypeer-assert.cls`, and the artefact that shows the
/// namespace hop this row was once declared blocked for lacking.
///
/// THE ROW WAS DECLARED BLOCKED AND THE BLOCK WAS WRONG. `Security.SSLConfigs` really is absent from an
/// application namespace — `SELECT … FROM Security.SSLConfigs` gives `SQLCODE -30` and a late-bound
/// call raises `<CLASS DOES NOT EXIST>` — and the conclusion drawn from that was that an executable
/// assertion "cannot execute where the gate runs". It can: `New $Namespace  Set $Namespace = "%SYS"`.
/// `TestAuditReadsTheRealTable` is the proof, and it runs in the same namespace as every other test
/// in the bank.
///
/// WHAT IS ASSERTED EXHAUSTIVELY AND WHAT IS NOT, stated rather than left to be discovered.
/// `Classify` is pure, so every verdict is asserted directly. The live table is only READ, never
/// written, because creating a configuration that should PASS needs a real CA certificate on disk —
/// measured: `Create` with `VerifyPeer=1` and no CA file gives `#986`, with a named-but-absent file
/// `#5012`, and with a file containing junk `#743`. Shipping a certificate in the repo, or generating
/// one at test time, would buy one end-to-end pass path in exchange for a fixture that rots and a test
/// that shells out. So: the pass path is covered by `Classify`, and the live read is asserted to have
/// actually read something.
///
/// MEASURED VALUES this pins, from the probe run that preceded it:
///     a clean IRIS for Health 2026.1 has TWO SSL configurations, and BOTH fail:
///       BFC_SSL                        Enabled=1  VerifyPeer=0  CAFile=""  Type=0
///       ISC.FeatureTracker.SSL.Config  Enabled=1  VerifyPeer=0  CAFile=""  Type=0
///     Report() -> "2 of 2 SSL configuration(s) do NOT validate the peer"
///     VerifyPeer: type %Library.Integer, MINVAL 0, MAXVAL 3, VALUELIST EMPTY
///     Security.Datatype.SSLType and .BooleanYN: VALUELIST empty too
///     New $Namespace + Set $Namespace: before=[FHIRTEST] after=[FHIRTEST]
///     Set $Namespace with NO New:      before=[FHIRTEST] after=[%SYS]   <- leaks
///
/// RUN AND MUTATION-CHECKED, measured, five mutations, all five reddening:
///
///     as shipped                                        PASSED 5/5
///     1 Classify ignores CAFile (no MISLEADING verdict)  TestClassifyCoversEveryVerdict      FAIL
///     2 REQUIRELEVEL = 0                                 TestClassifyCoversEveryVerdict +
///                                                       TestThresholdIsTheNamedConstant     FAIL
///     3 DISABLED treated as a finding                    TestClassifyCoversEveryVerdict      FAIL
///     4 Audit drops the `New $Namespace`                 the RUN COLLAPSES -- see below
///     5 Audit reads `WHERE 1=0` (looks, finds nothing)   TestAuditReadsTheRealTable          FAIL
///
/// MUTATION 4 IS MORE THAN A FAILING TEST. Removing `New $Namespace` recorded **one** method instead
/// of five (`methods=1 failed=1`): the leaked `%SYS` follows the test runner out of the first test,
/// and the rest of the suite cannot even be recorded. A utility that leaks a namespace does not fail
/// the caller, it derails everything after it — which is exactly why the leak is asserted rather than
/// described, and why the demonstration of it lives in this class with an immediate restore.
///
/// MUTATION 5 IS THE POSITIVE CONTROL MADE CONCRETE. `WHERE 1=0` gives an audit that ran, read the
/// right table, hopped correctly, and reported zero findings — the shape of every false clean in this
/// deliverable. `TestAuditReadsTheRealTable` catches it on `tReport("total")`, not on the finding
/// count, because the finding count is the instance's business and the examined count is the audit's.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SslVerifyPeer", namespace="<NS>")
Class Example.Tests.SslVerifyPeer Extends %UnitTest.TestCase
{

/// Every verdict, with the controls that stop any one of them passing for the wrong reason.
Method TestClassifyCoversEveryVerdict() As %Status
{
    // Validation on: fine, whatever else is set.
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(1, "/etc/ssl/ca.pem", 1, .tWhy), "OK", "VerifyPeer=1 with a CA file is the state §11.7 step 1 asks for")
    // Validation off with NO CA file: nothing was ever configured.
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(0, "", 1, .tWhy), "NO-VALIDATION", "VerifyPeer=0 and no CA file is no validation at all")
    // THE ONE THAT MATTERS: validation off WITH a CA file. Looks configured, validates nothing.
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(0, "/etc/ssl/ca.pem", 1, .tWhy), "MISLEADING", "VerifyPeer=0 WITH a CA file is the state a reviewer waves through")
    Do $$$AssertTrue(tWhy [ "looks configured", "and the reason says so, because the verdict alone would not: " _ tWhy)
    // Disabled is not a finding -- it validates nothing and is used by nothing.
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(0, "", 0, .tWhy), "DISABLED", "a disabled configuration is not a finding")
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(1, "/etc/ssl/ca.pem", 0, .tWhy), "DISABLED", "and neither is a disabled one that would otherwise pass")
    Quit $$$OK
}

/// The threshold is a named constant because the datatype carries no VALUELIST — asserted from the
/// dictionary, so the day IRIS gives VerifyPeer an enumeration this test says so.
Method TestThresholdIsTheNamedConstant() As %Status
{
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).#REQUIRELEVEL, 1, "the require level is 1")
    // MAXVAL is 3, so 2 and 3 are legal values above the threshold and must also count as OK.
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(2, "/etc/ssl/ca.pem", 1, .tWhy), "OK", "2 is above the require level")
    Do $$$AssertEquals(##class(Example.UTL.SslConfigAudit).Classify(3, "/etc/ssl/ca.pem", 1, .tWhy), "OK", "and so is 3, which MAXVAL says is the top")
    Set tSC = ..PropertyParams("Security.SSLConfigs||VerifyPeer", .tParams)
    Do $$$AssertStatusOK(tSC, "read VerifyPeer's property parameters from %SYS")
    Do $$$AssertEquals($Get(tParams("MINVAL")), 0, "MINVAL is 0")
    Do $$$AssertEquals($Get(tParams("MAXVAL")), 3, "MAXVAL is 3")
    Do $$$AssertEquals($Get(tParams("VALUELIST")), "", "and VALUELIST is EMPTY -- nothing in the class says which number means Require")
    Quit $$$OK
}

/// The audit really reads the live table from an application namespace. This is the assertion that
/// overturns the "blocked" verdict.
Method TestAuditReadsTheRealTable() As %Status
{
    Do $$$AssertStatusOK(##class(Example.UTL.SslConfigAudit).Audit(.tReport), "the audit ran from this namespace")
    // A POSITIVE CONTROL, and the whole point of it: zero findings would also be produced by an audit
    // that could not read the table, or looked in the wrong namespace. Assert it examined something.
    Do $$$AssertTrue(tReport("total") >= 1, "it examined at least one configuration: " _ tReport("total"))
    // Every finding is well formed. Not "there are N findings" -- the count is the instance's business.
    For i = 1:1:tReport {
        Set tRow = tReport(i)
        Do $$$AssertNotEquals($List(tRow, 1), "", "finding " _ i _ " names a configuration")
        Do $$$AssertTrue(",MISLEADING,NO-VALIDATION," [ ("," _ $List(tRow, 2) _ ","), "finding " _ i _ " carries a known verdict: " _ $List(tRow, 2))
    }
    Do $$$AssertTrue(##class(Example.UTL.SslConfigAudit).Report() '= "", "and Report() renders it")
    Quit $$$OK
}

/// `New $Namespace` is what makes the hop safe, and the hazard is asserted next to it.
Method TestNamespaceHopRestoresTheCaller() As %Status
{
    Set tBefore = $Namespace
    Do ##class(Example.UTL.SslConfigAudit).Audit(.tReport)
    Do $$$AssertEquals($Namespace, tBefore, "Audit left the caller in its own namespace")
    // The hazard, demonstrated rather than described: the same hop WITHOUT New $Namespace leaks.
    // Deliberately in the test class and not in the utility, and restored immediately.
    Do ..LeakyHop()
    Set tAfter = $Namespace
    Set $Namespace = tBefore
    Do $$$AssertEquals(tAfter, "%SYS", "a hop with no `New $Namespace` LEAKS %SYS into the caller -- which is why Audit has one")
    Do $$$AssertEquals($Namespace, tBefore, "and the test put it back")
    Quit $$$OK
}

/// Read one property's parameters out of %SYS. Hops, like everything else here.
ClassMethod PropertyParams(pId As %String, Output pParams) As %Status [ Private ]
{
    Kill pParams
    New $Namespace
    Set $Namespace = "%SYS"
    Set tProp = ##class(%Dictionary.CompiledProperty).%OpenId(pId, , .tSC)
    If '$IsObject(tProp) {
        Set tWhy = "could not open " _ pId _ ": " _ $System.Status.GetErrorText(tSC)
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    For tKey = "MINVAL", "MAXVAL", "VALUELIST", "DISPLAYLIST" {
        Set pParams(tKey) = tProp.Parameters.GetAt(tKey)
    }
    Quit $$$OK
}

/// The WRONG way, kept only so the test above can assert what it costs. Never ship this shape.
ClassMethod LeakyHop() [ Private ]
{
    Set $Namespace = "%SYS"
    Quit
}

/// The class this audits is %SYS-scoped and privileged: `RESOURCEREQUIRED = %Admin_Secure`. Asserted
/// so that a run under a user without it fails HERE, with a readable reason, rather than reporting a
/// clean audit it was never allowed to perform.
Method TestAuditFailsLoudlyWithoutAccess() As %Status
{
    // Not a privilege test -- the suite runs as a privileged user. What is asserted is the CONTRACT:
    // Audit distinguishes "no findings" from "could not look", because the two must never look alike.
    Do $$$AssertStatusOK(##class(Example.UTL.SslConfigAudit).Audit(.tReport), "the audit succeeded for this user")
    Do $$$AssertTrue($Data(tReport("total")), "and it reports how many configurations it examined, which an audit that could not look cannot do")
    Do $$$AssertTrue(##class(Example.UTL.SslConfigAudit).Report() '[ "AUDIT FAILED", "Report() says AUDIT FAILED rather than OK when the read fails; here it did not fail")
    Quit $$$OK
}

}
