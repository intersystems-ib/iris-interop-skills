/// Rule: BestPractices_Interop_IRIS.md §6.16 "The typed SOAP BO: the client class belongs in configuration, and what that costs"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN.
/// Severity: High (the guards it pins turn two `<INVALID OREF>`s into named errors).
///
/// Pattern: the oracle for `soap-bo-typed-adapter.cls` and its two message siblings.
///
/// WHAT THIS SUITE IS REALLY FOR. The fence it replaces was a complete class that tier 3 compiled and
/// then had to **excuse** — it named three classes it did not ship, so it landed in the placeholder
/// dependency bucket and stayed off `snippets_baseline.json`. `TestMessageMapResolvesToShippedClasses`
/// is the assertion that stops that recurring: every class the BO names must exist and be compiled,
/// which is precisely what a placeholder dependency means it does not.
///
/// THE PROPERTY TABLE IS ASSERTED, NOT DESCRIBED. Every adapter property the header claims is checked
/// against `%Dictionary.CompiledProperty`, including two defaults that matter:
///
///     WebServiceURL            InitialExpression = "<default>"    <-- a LITERAL STRING, not empty
///     SSLCheckServerIdentity   InitialExpression = 1
///     ResponseTimeout          InitialExpression = 30
///     WebServiceClientClass    %String                            the setting
///     %Client                  %SOAP.WebClient                    the generic base, NOT the generated class
///
/// `WebServiceURL` defaulting to the literal `"<default>"` is the one to remember: a guard written as
/// `If ..Adapter.WebServiceURL = ""` never fires, because the unset value is not empty.
///
/// AND `%Client` BEING `%SOAP.WebClient` IS THE WHOLE TRADE-OFF. Taking the client class from
/// configuration means the compiler sees only the generic base, so the generated operation must be
/// called late-bound and a misspelling is a runtime `<METHOD DOES NOT EXIST>`. That is asserted
/// directly, so the cost is visible rather than implied.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                     PASSED 7/7
///     the unset-client-class guard removed            TestUnsetClientClassIsANamedError FAILS
///     WireBooleanIsTrue does a numeric test           TestWireBooleanIsTrue +
///                                                    TestResponseKeepsTheWireValue     FAIL
///     ADAPTER points at the HTTP adapter instead      TestAdapterIsDeclaredNotExtended +
///                                                    TestUnsetClientClassIsANamedError FAIL
///     Approved typed %Boolean instead of %String      TestResponseKeepsTheWireValue     FAILS
///
/// The last one is worth noting: typing the property `%Boolean` really does lose the wire value --
/// the datatype coerces `"true"` before any test can see it, which is why §6.15's finding shows up in
/// a MESSAGE class and not only at the comparison.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SoapBoAdapterWiring", namespace="<NS>")
Class Example.Tests.SoapBoAdapterWiring Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// %New() on an Ens.BusinessOperation subclass needs a config name -- §6.14 measured that the
/// argument-less form silently returns "".
Parameter CONFIGNAME = "BO.ForecastSoap";

Method TestControl() As %Status
{
    Quit $$$OK
}

ClassMethod PropInit(pClass As %String, pProp As %String) As %String [ Private ]
{
    Set tInit = ""
    &sql(SELECT InitialExpression INTO :tInit FROM %Dictionary.CompiledProperty
         WHERE parent = :pClass AND Name = :pProp)
    Quit $Select(SQLCODE '= 0: "<no such property>", 1: $Get(tInit))
}

ClassMethod PropType(pClass As %String, pProp As %String) As %String [ Private ]
{
    Set tType = ""
    &sql(SELECT Type INTO :tType FROM %Dictionary.CompiledProperty
         WHERE parent = :pClass AND Name = :pProp)
    Quit $Select(SQLCODE '= 0: "<no such property>", 1: $Get(tType))
}

/// THE EXEMPTION FIX. Every class the BO names must actually exist -- that is what the fence could
/// not say.
Method TestMessageMapResolvesToShippedClasses()
{
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("Example.MSG.ForecastReq"), 1, "the request the MessageMap keys on must be a real compiled class")
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("Example.MSG.ForecastRsp"), 1, "and so must the response")
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("Example.BO.ForecastSoap"), 1, "and the BO itself")

    // Control: a name of the shape the fence used does NOT exist, which is what made it a placeholder.
    Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId("MyApp.SOAP.WeatherService.GetForecastRequest"), 0, "control: the fence's request class is not in the namespace -- that is a placeholder dependency")
}

/// The adapter is DECLARED, not extended.
Method TestAdapterIsDeclaredNotExtended()
{
    Do $$$AssertEquals($parameter("Example.BO.ForecastSoap", "ADAPTER"), "EnsLib.SOAP.OutboundAdapter", "the ADAPTER parameter is what makes this a SOAP BO")

    // And the BO extends Ens.BusinessOperation, never the adapter.
    Set tSuper = ""
    &sql(SELECT Super INTO :tSuper FROM %Dictionary.CompiledClass WHERE Name = 'Example.BO.ForecastSoap')
    Do $$$AssertEquals($Find(tSuper, "Ens.BusinessOperation") > 0, 1, "it extends Ens.BusinessOperation: " _ tSuper)
    Do $$$AssertEquals($Find(tSuper, "OutboundAdapter") > 0, 0, "and NOT the adapter -- that yields an empty component (CR-2)")
}

/// The property table from the header, asserted.
Method TestAdapterPropertiesAreWhatTheHeaderSays()
{
    Set tA = "EnsLib.SOAP.OutboundAdapter"

    Do $$$AssertEquals(..PropType(tA, "WebServiceClientClass"), "%Library.String", "WebServiceClientClass is a string SETTING")
    Do $$$AssertEquals(..PropType(tA, "%Client"), "%SOAP.WebClient", "and %Client is the GENERIC base -- not the generated class")

    // The default that traps people.
    Do $$$AssertEquals(..PropInit(tA, "WebServiceURL"), """<default>""", "WebServiceURL defaults to the LITERAL string <default>, not to empty")
    Do $$$AssertNotEquals(..PropInit(tA, "WebServiceURL"), """""", "so a guard written as = """" would never fire")

    Do $$$AssertEquals(..PropInit(tA, "SSLCheckServerIdentity"), 1, "SSLCheckServerIdentity defaults ON")
    Do $$$AssertEquals(..PropInit(tA, "ResponseTimeout"), 30, "ResponseTimeout defaults to 30")

    // Control: a property that does not exist is reported as such, so the assertions above are not
    // passing because the helper always returns something plausible.
    Do $$$AssertEquals(..PropType(tA, "NoSuchPropertyAnywhere"), "<no such property>", "control: a missing property is reported")
}

/// The guards turn two null-oref throws into named errors.
Method TestUnsetClientClassIsANamedError()
{
    Set tBO = ##class(Example.BO.ForecastSoap).%New(..#CONFIGNAME)
    Do $$$AssertEquals($IsObject(tBO), 1, "the BO instantiates with a config name (§6.14)")

    Set tReq = ##class(Example.MSG.ForecastReq).%New()
    Set tReq.Location = "Barcelona"

    // The adapter exists but WebServiceClientClass is unset on a bare instance.
    Set tSC = tBO.GetForecast(tReq, .tResp)
    Do $$$AssertStatusNotOK(tSC, "with no client class configured the call must fail")

    Set tText = $system.Status.GetErrorText(tSC)
    Do $$$AssertEquals($Find(tText, "WebServiceClientClass") > 0, 1, "and the error must NAME the setting rather than throw <INVALID OREF>: " _ $Extract(tText, 1, 140))
}

/// The wire-boolean helper, which exists so a caller does not re-derive §6.15's finding.
Method TestWireBooleanIsTrue()
{
    Do $$$AssertEquals(##class(Example.BO.ForecastSoap).WireBooleanIsTrue("true"), 1, "'true'")
    Do $$$AssertEquals(##class(Example.BO.ForecastSoap).WireBooleanIsTrue("TRUE"), 1, "case-insensitive")
    Do $$$AssertEquals(##class(Example.BO.ForecastSoap).WireBooleanIsTrue("false"), 0, "'false'")
    Do $$$AssertEquals(##class(Example.BO.ForecastSoap).WireBooleanIsTrue(""), 0, "empty is not true")

    // The trap it exists for, restated as an assertion so the helper's reason is visible here too.
    Set tWire = "true"
    Do $$$AssertEquals(tWire = 1, 0, "the reason: the wire value fails a numeric test")
}

/// The response keeps the wire value rather than coercing it -- a %Boolean property would lose it.
Method TestResponseKeepsTheWireValue()
{
    Do $$$AssertEquals(..PropType("Example.MSG.ForecastRsp", "Approved"), "%Library.String", "Approved is a STRING, so 'true' survives the assignment")

    Set tRsp = ##class(Example.MSG.ForecastRsp).%New()
    Set tRsp.Approved = "true"
    Do $$$AssertEquals(tRsp.Approved, "true", "the wire value is preserved verbatim")
    Do $$$AssertEquals(##class(Example.BO.ForecastSoap).WireBooleanIsTrue(tRsp.Approved), 1, "and converts correctly at the point of use")
}

}
