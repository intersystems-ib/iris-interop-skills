/// Rule: BestPractices_Interop_IRIS.md §7.4 "Testing the alert circuit without an SMTP server"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed inside a started production.
/// Severity: High for what it makes testable (an alert circuit nobody has ever seen fire).
///
/// Pattern: a Business Operation that fails on demand, so an alert circuit can be exercised.
///
/// WHY THIS EXISTS. §7.1 and §7.2 describe a circuit whose only observable output is an email, and
/// the documented way to check it is a six-step manual procedure requiring an SMTP server, a real
/// mailbox and a human to look in it. That procedure is run once, at go-live, and never again — so a
/// dedup guard that suppresses EVERY alert is indistinguishable from a healthy production for as
/// long as nobody breaks anything on purpose. This class is how the circuit gets exercised in a test.
///
/// RETURNING `$$$ERROR` IS NOT THE SAME AS THROWING, and that is the thing to pin. `AlertOnError`
/// acts on the `%Status` an `OnMessage` RETURNS. A `Throw` escapes to the framework's own handler,
/// which produces a different Event Log entry and a different retry path. The two modes are both
/// here, selected by the payload, so a reader can see that the circuit is driven by the return value.
///
/// AND IT FAILS ON EVERY RETRY, not once. With `FailureTimeout` finite and `RetryInterval` short, one
/// failing message produces SEVERAL `Ens.AlertRequest` messages — which is the flood §7.2's dedup
/// exists to stop, and is why the tests can assert deduplication on a single input.
Class Example.BO.FailOnDemand Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Counts every OnMessage entry, so a test can tell "never called" from "called and suppressed".
ClassMethod Attempts() As %Integer
{
    Quit +$Get(^Example.FailOnDemand)
}

ClassMethod Reset() As %Status
{
    Kill ^Example.FailOnDemand
    Quit $$$OK
}

Method OnMessage(pRequest As Ens.StringContainer, Output pResponse As Ens.Response) As %Status
{
    Set tN = $Increment(^Example.FailOnDemand)
    Set ^Example.FailOnDemand(tN) = pRequest.StringValue
    Set pResponse = ##class(Ens.Response).%New()

    // THROW mode, for contrast. The framework catches it; AlertOnError still fires, but through the
    // system-error path, and the Event Log entry names the exception rather than your reason.
    If pRequest.StringValue [ "THROW" {
        Throw ##class(%Exception.General).%New("FailOnDemand", "5001", , "asked to throw")
    }

    // RETURN mode. This is the status AlertOnError reads.
    If pRequest.StringValue [ "FAIL" {
        Quit $$$ERROR($$$GeneralError, "FailOnDemand was asked to fail: " _ pRequest.StringValue)
    }

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

}
