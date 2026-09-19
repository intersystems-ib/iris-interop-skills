/// Rule: BestPractices_Interop_IRIS.md §12.6 "Resend and edit-and-resend: two APIs, and the shared body row that rewrites history"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed inside a started production.
/// Severity: Low on its own (it is a fixture); High for what it makes testable.
///
/// Pattern: a terminal Business Operation that records what it was handed, so a test can assert that
/// a resend actually **delivered** rather than merely returned `$$$OK`.
///
/// WHY A FIXTURE LIKE THIS IS NOT OPTIONAL HERE. Every resend API in §12.6 returns `$$$OK` for work
/// that has only been QUEUED. `ResendDuplicatedMessage` returning OK and a new header id says nothing
/// about whether anything arrived — and the two APIs differ in what arrives, which is the entire
/// point of the section. Without a target that keeps a receipt, the test could only assert that the
/// call did not error, which is exactly the assertion §12.6 says is worthless here.
///
/// It records into `^Example.MessageSink`, a global, deliberately: a persistent class would need its
/// own storage, its own purge story, and a second file, and none of that makes the receipt more
/// trustworthy. The global is named after the class so it is obvious what owns it, and `Reset()`
/// exists so a test starts from a known empty state rather than from whatever the last run left.
///
/// `Parameter INVOCATION = "Queue"` is load-bearing for the resend tests: a resend puts a header on
/// the target's queue, so the target must be a queued host. An `InProc` operation would be invoked
/// on the caller's job and the queue would never be involved.
Class Example.BO.MessageSink Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Ens.StringContainer, Output pResponse As Ens.Response) As %Status
{
    Set tN = $Increment(^Example.MessageSink)
    Set ^Example.MessageSink(tN) = $ListBuild(..%ConfigName, pRequest.StringValue)
    $$$LOGINFO("sink " _ ..%ConfigName _ " received: " _ pRequest.StringValue)
    Set pResponse = ##class(Ens.Response).%New()
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringContainer">
    <Method>OnMessage</Method>
  </MapItem>
</MapItems>
}

/// Start from empty. A test that does not call this measures the previous run.
ClassMethod Reset() As %Status
{
    Kill ^Example.MessageSink
    Quit $$$OK
}

/// How many messages have arrived, at any item.
ClassMethod Count() As %Integer
{
    Quit +$Get(^Example.MessageSink)
}

/// What arrived at pConfigName, as a comma-separated list in arrival order.
ClassMethod Received(pConfigName As %String = "") As %String
{
    Set tOut = "", tK = ""
    For {
        Set tK = $Order(^Example.MessageSink(tK), 1, tRow)
        Quit:tK=""
        // An If, not `Continue:<cond>`: a postconditional's expression ends at the first SPACE, so
        // `Continue:(a'="") && (b'=c)` is #1012 "Expected EOL or spaces" pointing at the `&&`.
        If (pConfigName '= ""), $List(tRow, 1) '= pConfigName { Continue }
        Set tOut = tOut _ $Select(tOut="":"", 1:",") _ $List(tRow, 2)
    }
    Quit tOut
}

}
