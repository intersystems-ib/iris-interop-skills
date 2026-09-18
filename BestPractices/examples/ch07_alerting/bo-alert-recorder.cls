/// Rule: BestPractices_Interop_IRIS.md §7.4 "Testing the alert circuit without an SMTP server"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed inside a started production.
/// Severity: High for what it makes testable.
///
/// Pattern: the sink that stands in for `EnsLib.EMail.AlertOperation`, so the end of the circuit is
/// readable by a test instead of by a person with a mailbox.
///
/// IT ACCEPTS `Ens.AlertRequest`, WHICH IS THE POINT. The circuit's message class is fixed by the
/// framework, so a recorder that accepts `Ens.StringContainer` would never be reached — the routing
/// rule's `msgClass` constraint would not match and the alert would be dropped with no error. Getting
/// this wrong produces exactly the symptom the whole chapter is about: a silent alert stream.
///
/// `AlertOnError` IS 0 ON THIS ITEM IN THE PRODUCTION, and must be. A sink that alerts on its own
/// failures feeds its failures back into the circuit that just failed.
Class Example.BO.AlertRecorder Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

ClassMethod Reset() As %Status
{
    Kill ^Example.AlertRecorder
    Quit $$$OK
}

/// How many alerts reached the end of the circuit.
ClassMethod Count() As %Integer
{
    Quit +$Get(^Example.AlertRecorder)
}

/// The AlertText of each alert that arrived, in order, comma-separated.
ClassMethod Texts() As %String
{
    Set tOut = "", tK = ""
    For {
        Set tK = $Order(^Example.AlertRecorder(tK), 1, tRow)
        Quit:tK=""
        Set tOut = tOut _ $Select(tOut="":"", 1:" | ") _ tRow
    }
    Quit tOut
}

Method OnMessage(pRequest As Ens.AlertRequest, Output pResponse As Ens.Response) As %Status
{
    Set tN = $Increment(^Example.AlertRecorder)
    Set ^Example.AlertRecorder(tN) = $Extract(pRequest.AlertText, 1, 200)
    Set pResponse = ##class(Ens.Response).%New()
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.AlertRequest">
    <Method>OnMessage</Method>
  </MapItem>
</MapItems>
}

}
