/// Rule: BestPractices_Interop_IRIS.md §6.21 "Driving `EnsLib.SQL.OutboundAdapter` headless: `Connect()` is the entry point, `OnInit()` is a trap"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled, and every failure mode below RUN.
/// Severity: High (the natural call order raises an exception that names nothing you wrote).
///
/// Pattern: probe a SQL outbound connection from outside a production — from a `[SqlProc]`, a terminal,
/// an MCP call — so a DSN, a credential set and a driver can be checked before any interop item exists.
///
/// THE CALL ORDER IS `%New()` -> `Connect()` -> `Do ..Disconnect()`. **Do not call `OnInit()`.**
/// Measured, with no production running:
///
///     JGService untouched (the default)   OnInit() RAISES <INVALID OREF>
///                                         at initAdapterJG+2^EnsLib.JavaGateway.Common.1
///     JGService = ""                      the SAME raise -- assigning the default changes nothing
///     JGService = "SomeGatewayItem"       returns a %Status: <Ens>ErrGeneral: No Config Item found
///                                         for 'SomeGatewayItem' in Production '...' ; SQLCODE=100
///
/// Read the first two rows carefully. `OnInit()` **raises** rather than returning, so `$$$ISERR(tSC)`
/// never sees it -- the exception unwinds past your error handling. And the location names
/// `EnsLib.JavaGateway.Common`, which is neither your Business Operation, nor
/// `EnsLib.SQL.OutboundAdapter`, nor the `JGService` setting that actually caused it. The empty value is
/// the worse case *and* it is the default, so the well-behaved status is the one you have to opt into.
///
/// `Connect()` NEEDS NONE OF THAT. It returns a `%Status` and, for ODBC, never touches the Java Gateway:
///
///     DSN = "PlainName"        <Ens>ErrOutConnectFailed: ODBC Connect failed for 'PlainName' / ''
///                             ... #6022 Gateway failed: SQLConnect ... SQLState (IM002)
///                             [iODBC][Driver Manager] Data source name not found
///     DSN = "jdbc:x://h/d"    <Ens>ErrOutConnectFailed: JDBC Connect failed for 'jdbc:x://h/d' / ''
///                             ... Unable to connect with empty JDBCDriver setting value
///
/// So **the DSN text alone decides the route**: a `jdbc:` prefix goes to JDBC and then needs a
/// `JDBCDriver`; anything else is treated as an ODBC DSN name that must be registered with the host's
/// driver manager. `DSN = "FHIRTEST"` does NOT mean "the local namespace" -- it means an ODBC DSN of
/// that name, and it fails with IM002 if none is registered.
///
/// `Disconnect` IS VOID, and that is the second trap. Measured on both `EnsLib.SQL.Common` and
/// `EnsLib.SQL.OutboundAdapter`: `ReturnType` is empty, while `Connect` and `ExecuteQuery` both return
/// `%Library.Status`. So:
///
///     Do ..Disconnect()            on a never-connected adapter: returns normally, Connected = 0
///     Set tSC = ..Disconnect()     RAISES <COMMAND>
///
/// The mistake is natural precisely because every other method here returns a status. Nothing catches it
/// at compile time either -- see §6.20 on why a typed declaration is not a check.
///
/// `ExecuteQuery` WITHOUT A SUCCESSFUL CONNECT returns a status wrapping someone else's crash:
/// `<Ens>ErrException: <INVALID OREF>ExecuteQueryParmArray+4^EnsLib.SQL.Common.1`. Check the Connect
/// status before querying; the adapter will not do it for you.
///
/// ONE MORE THING THE ERROR TEXT WILL LIE ABOUT. `OnInit()`'s status names a production
/// (`in Production 'X'`) even when **no production is running** -- that is the last *configured*
/// production, read from config. Do not read it as evidence that something is up.
Class Example.UTL.SqlProbe Extends %RegisteredObject
{

/// Seconds to wait for the connection. Short on purpose: a probe should fail fast.
Parameter TIMEOUT As INTEGER = 5;

/// Probe a DSN and report in one line. Callable from SQL, so a connection can be checked with no
/// production, no Business Operation and no Terminal:
///     SELECT Example_UTL.SqlProbe_Check('MyDsn', 'MyCredentialSet')
/// Returns a human-readable verdict rather than a %Status, because the caller here is a person or a
/// tool reading one cell, not code branching on it.
ClassMethod Check(pDsn As %String, pCredentials As %String = "") As %String [ SqlProc ]
{
    #Dim tAdapter As EnsLib.SQL.OutboundAdapter
    Try {
        Set tAdapter = ##class(EnsLib.SQL.OutboundAdapter).%New()
        If '$IsObject(tAdapter) {
            Return "FAILED: %New() returned no object"
        }
        Set tAdapter.DSN = pDsn
        If pCredentials '= "" { Set tAdapter.Credentials = pCredentials }
        // Connect(), NOT OnInit(). OnInit() raises <INVALID OREF> out here -- see the class header.
        Set tSC = tAdapter.Connect(..#TIMEOUT)
        If $$$ISERR(tSC) {
            // `Do`, not `Set`: Disconnect is VOID and assigning it raises <COMMAND>.
            Do tAdapter.Disconnect()
            Return "NO: " _ ..Route(pDsn) _ " connect failed -- " _ $System.Status.GetErrorText(tSC)
        }
        Set tVerdict = "OK: " _ ..Route(pDsn) _ " connected to '" _ pDsn _ "'"
        Do tAdapter.Disconnect()
        Return tVerdict
    }
    Catch tException {
        // A raise, not a status, is the signature of calling the adapter outside the shape it expects.
        Return "RAISED <" _ tException.Name _ "> at " _ tException.Location _ " -- an exception, not a %Status"
    }
}

/// Which driver stack this DSN will use. Measured: the DSN text alone decides it.
ClassMethod Route(pDsn As %String) As %String
{
    Quit $Select($ZConvert($Extract(pDsn, 1, 5), "L") = "jdbc:":"JDBC", 1:"ODBC")
}

}
