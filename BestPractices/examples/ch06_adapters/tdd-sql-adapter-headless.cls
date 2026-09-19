/// Rule: BestPractices_Interop_IRIS.md §6.21 "Driving `EnsLib.SQL.OutboundAdapter` headless: `Connect()` is the entry point, `OnInit()` is a trap"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the trap raises past your error handling).
///
/// Pattern: the oracle for `sql-adapter-headless-probe.cls`. Every assertion runs with **no DSN
/// registered and no production up**, which is the whole point: the failures being pinned are the ones a
/// developer meets before anything is configured.
///
/// NOTHING HERE ASSERTS A SUCCESSFUL CONNECTION, deliberately. There is no ODBC DSN on the gate
/// instance, and inventing one would make the suite pass or fail for reasons that have nothing to do
/// with §6.21. What IS asserted is the SHAPE of each failure — raise versus status, and which stack the
/// DSN routed to — because that shape is what the section claims and what a regression would change.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=377  6 methods, 0 failed
///     Check calls OnInit instead of Connect       run=378  1 failed -- TheProbeReportsRatherThanRaising
///     Disconnect assigned instead of Do'd         run=379  1 failed -- TheProbeReportsRatherThanRaising
///     Route always says ODBC                      run=380  1 failed -- TheDsnTextAloneChoosesOdbcOrJdbc
///     the DSN dropped from the failure message    run=381  1 failed -- TheProbeReportsRatherThanRaising
///     reverted                                    run=382  6 methods, 0 failed
///
/// Mutations 1 and 2 are the demonstrations: each swaps a correct call for the plausible wrong one and
/// the probe stops reporting and starts raising.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SqlAdapterHeadless", namespace="<NS>")
Class Example.Tests.SqlAdapterHeadless Extends %UnitTest.TestCase
{

/// An ODBC DSN name that must not exist. If someone registers this, the suite tells you by failing.
Parameter ABSENTDSN As STRING = "example-dsn-that-does-not-exist";

Parameter JDBCDSN As STRING = "jdbc:example://host/db";

/// `OnInit()` RAISES when JGService is empty -- it does not return an error status, so error handling
/// built on `$$$ISERR` never sees it.
Method TestOnInitRaisesWhenJGServiceIsEmpty() As %Status
{
    Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Do $$$AssertTrue($IsObject(tAdapter), "POSITIVE CONTROL: the adapter was constructed, so the raise below is from OnInit and not from %New")
    Set tAdapter.DSN = ..#ABSENTDSN
    Set tRaised = "", tLocation = ""
    Try {
        Set tSC = tAdapter.OnInit()
        Set tRaised = "<none -- returned a status: " _ $System.Status.GetErrorText(tSC) _ ">"
    }
    Catch tException {
        Set tRaised = tException.Name
        Set tLocation = tException.Location
    }
    Do $$$AssertEquals(tRaised, "<INVALID OREF>", "OnInit() with an empty JGService RAISES, got: " _ tRaised)
    // And the location names none of the three things the developer wrote.
    Do $$$AssertTrue(tLocation [ "JavaGateway", "and the location points into EnsLib.JavaGateway.Common, which the caller never mentioned: " _ tLocation)
    Do $$$AssertNotTrue(tLocation [ "SQL.OutboundAdapter", "it does NOT name the adapter class")
    Quit $$$OK
}

/// The differential: a NON-empty JGService turns the raise into a reportable status. Same call, one
/// property different -- so the raise cannot be blamed on "headless" in general.
Method TestANonEmptyJGServiceReturnsAStatusInstead() As %Status
{
    Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Set tAdapter.DSN = ..#ABSENTDSN
    Set tAdapter.JGService = "ExampleGatewayItemThatIsNotConfigured"
    Set tRaised = "", tText = ""
    Try {
        Set tSC = tAdapter.OnInit()
        Set tText = $System.Status.GetErrorText(tSC)
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "", "with JGService set, OnInit() returns rather than raising; got a raise: " _ tRaised)
    // POSITIVE CONTROL: it must still be an ERROR status -- if it succeeded, this test would be
    // asserting nothing about the JGService path at all.
    Do $$$AssertNotEquals(tText, "", "POSITIVE CONTROL: it is still an error status, so the JGService path really was taken")
    Do $$$AssertTrue(tText [ "No Config Item found", "and the status names the missing config item: " _ tText)
    Quit $$$OK
}

/// `Connect()` is the headless entry point: a status, never a raise, and it names the DSN.
Method TestConnectReturnsAStatusAndNamesTheDsn() As %Status
{
    Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Set tAdapter.DSN = ..#ABSENTDSN
    Set tRaised = "", tText = ""
    Try {
        Set tSC = tAdapter.Connect(5)
        Set tText = $System.Status.GetErrorText(tSC)
    }
    Catch tException {
        Set tRaised = tException.Name _ " at " _ tException.Location
    }
    Do $$$AssertEquals(tRaised, "", "Connect() reports through a %Status and does not raise; got: " _ tRaised)
    Do $$$AssertNotEquals(tText, "", "POSITIVE CONTROL: an unregistered DSN really does fail, so the text below is a real failure")
    Do $$$AssertTrue(tText [ ..#ABSENTDSN, "and the error names the DSN that failed, which OnInit's never does: " _ tText)
    Do $$$AssertTrue(tText [ "ErrOutConnectFailed", "as <Ens>ErrOutConnectFailed")
    Quit $$$OK
}

/// The DSN text alone picks the driver stack.
Method TestTheDsnTextAloneChoosesOdbcOrJdbc() As %Status
{
    Set tOdbc = ..ConnectText(..#ABSENTDSN)
    Set tJdbc = ..ConnectText(..#JDBCDSN)
    // POSITIVE CONTROL: both attempts produced text, so comparing them is meaningful.
    Do $$$AssertNotEquals(tOdbc, "", "POSITIVE CONTROL: the plain DSN produced an error to inspect")
    Do $$$AssertNotEquals(tJdbc, "", "POSITIVE CONTROL: the jdbc: DSN produced an error to inspect")
    Do $$$AssertTrue(tOdbc [ "ODBC Connect failed", "a plain DSN name routes to ODBC: " _ tOdbc)
    Do $$$AssertTrue(tJdbc [ "JDBC Connect failed", "a jdbc: prefix routes to JDBC: " _ tJdbc)
    // The sample's own classifier must agree with what the adapter actually did.
    Do $$$AssertEquals(##class(Example.UTL.SqlProbe).Route(..#ABSENTDSN), "ODBC", "and the probe classifies the plain DSN the same way")
    Do $$$AssertEquals(##class(Example.UTL.SqlProbe).Route(..#JDBCDSN), "JDBC", "and the jdbc: DSN the same way")
    Quit $$$OK
}

/// `Disconnect` is VOID. `Do` is safe even when no connection was ever made; `Set` raises <COMMAND>.
Method TestDisconnectIsVoidAndSafeToCallUnconnected() As %Status
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("EnsLib.SQL.OutboundAdapter||Disconnect", 0)
    Do $$$AssertTrue($IsObject(tDef), "POSITIVE CONTROL: Disconnect is in the dictionary")
    Do $$$AssertEquals(tDef.ReturnType, "", "Disconnect declares NO return type, so `Set tSC = ..Disconnect()` raises <COMMAND>")
    // Contrast with a sibling on the same class, or "no return type" could just mean the query is broken.
    Set tConnect = ##class(%Dictionary.CompiledMethod).%OpenId("EnsLib.SQL.OutboundAdapter||Connect", 0)
    Do $$$AssertEquals(tConnect.ReturnType, "%Library.Status", "POSITIVE CONTROL: Connect on the same class DOES return a status -- which is why the mistake is natural")
    // And behaviourally: Do on a never-connected adapter is safe.
    Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Set tRaised = ""
    Try {
        Do tAdapter.Disconnect()
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "", "Do ..Disconnect() on a never-connected adapter returns normally; got: " _ tRaised)
    Do $$$AssertEquals(tAdapter.Connected, 0, "and leaves Connected = 0")
    Quit $$$OK
}

/// The probe itself: a bad DSN comes back as a diagnosable line, never as a raise escaping to the caller.
Method TestTheProbeReportsRatherThanRaising() As %Status
{
    Set tRaised = "", tVerdict = ""
    Try {
        Set tVerdict = ##class(Example.UTL.SqlProbe).Check(..#ABSENTDSN)
    }
    Catch tException {
        Set tRaised = tException.Name
    }
    Do $$$AssertEquals(tRaised, "", "Check() swallows nothing but escapes nothing either; got a raise: " _ tRaised)
    Do $$$AssertTrue(tVerdict [ "NO: ODBC", "it reports the route and the failure: " _ tVerdict)
    Do $$$AssertTrue(tVerdict [ ..#ABSENTDSN, "and names the DSN in the message")
    Quit $$$OK
}

/// Connect once and return the error text, or "" if it somehow succeeded.
ClassMethod ConnectText(pDsn As %String) As %String [ Private ]
{
    Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
    Set tAdapter.DSN = pDsn
    Try {
        Set tSC = tAdapter.Connect(5)
        Set tText = $System.Status.GetErrorText(tSC)
    }
    Catch tException {
        Set tText = "RAISED <" _ tException.Name _ ">"
    }
    Do tAdapter.Disconnect()
    Quit tText
}

}
