/// Rule: BestPractices_Interop_IRIS.md §6.17 "A SOAP inbound service has two deployment modes, and `EnableStandardRequests` only exists in one of them"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN.
/// Severity: High (the setting is mandatory in one mode, unsettable in the other).
///
/// Pattern: the oracle for `production-soap-inbound.cls` and its adapter-mode service.
///
/// THE QUESTION IS THE SAME AS §1.19's, so the answer is checked the same way: for every setting of
/// every item, does its `Target` match the side the property actually lives on? A wrong target is not
/// applied and nothing is logged. What SOAP adds is a second axis — whether the service kept its
/// adapter at all — because a `Target="Adapter"` setting on a service that blanked its adapter has
/// nothing to land on, and that is not a wrong target so much as a missing one.
///
/// MEASURED, on compiled classes:
///
///     EnsLib.SOAP.Service           ADAPTER _Default = "EnsLib.SOAP.InboundAdapter"
///     Example.BS.SoapAdapterMode    ADAPTER _Default = "EnsLib.SOAP.InboundAdapter"   kept
///     Example.BS.MyService          ADAPTER _Default = ""                             blanked
///     EnsLib.SOAP.InboundAdapter    EnableStandardRequests   init 0   <-- the only class with it
///     EnsLib.HTTP.Service           EnableStandardRequests   init 1   <-- different family
///
/// No SERVICE carries the property. `TestNoServiceHasTheSetting` asserts that directly, because it is
/// the fact that makes `Target="Adapter"` the only possible answer for SOAP — and it is the fact a
/// reader is most likely to assume the opposite of, since the setting reads like a service concern.
///
/// ONE COLUMN NAME WORTH KNOWING, because getting it wrong looks like a finding: the parameter default
/// is `_Default`, not `Default`. `Default` is a reserved word, so `SELECT "Default" FROM
/// %Dictionary.CompiledParameter` returns **zero rows** with `SQLCODE -12`/`-29` reported only in the
/// status. While writing this file that produced two confident wrong readings — "EnsLib.SOAP.Service
/// has no ADAPTER parameter" and "the bank's service has no EnableStandardRequests" — both from a
/// syntax error, and both caught only because the gate's query helper now prints the status.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                    PASSED 7/7
///     EnableStandardRequests on Target="Host"        TestAdapterModeItemSetsItOnTheAdapter +
///                                                  TestEverySettingTargetsTheRightSide    FAIL
///     EnableStandardRequests turned OFF              TestAdapterModeItemSetsItOnTheAdapter  FAILS
///     the setting added to the DIRECT item too       TestDirectModeItemHasNoSuchSetting     FAILS
///     the direct item renamed off its FQCN           TestDirectModeItemIsNamedByFqcn +
///                                                  TestDirectModeItemHasNoSuchSetting     FAIL
///     the adapter-mode service blanks its ADAPTER    TestBlankAdapterIsAnEmptyDefaultNotAMissingOne FAILS
///
/// All six versions compile. The first mutation is the exact mistake the platform's own error message
/// invites -- it names the setting, so the reader moves it to the Host -- and it is caught twice.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SoapInboundTargets", namespace="<NS>")
Class Example.Tests.SoapInboundTargets Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.SoapInbound";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// The ADAPTER a class effectively declares: "" when blanked, the class name when kept.
ClassMethod AdapterOf(pClass As %String) As %String [ SqlProc ]
{
    Set tDefault = ""
    &sql(SELECT _Default INTO :tDefault FROM %Dictionary.CompiledParameter
         WHERE parent = :pClass AND Name = 'ADAPTER')
    Quit $Select(SQLCODE '= 0: "<no ADAPTER parameter>", 1: $Get(tDefault))
}

ClassMethod HasProperty(pClass As %String, pProp As %String) As %Boolean [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM %Dictionary.CompiledProperty WHERE parent = :pClass AND Name = :pProp)
    Quit (+$Get(tN) > 0)
}

/// THE FACT THAT DECIDES THE TARGET. No service has the setting; only the adapter does.
Method TestNoServiceHasTheSetting()
{
    Do $$$AssertEquals(..HasProperty("EnsLib.SOAP.InboundAdapter", "EnableStandardRequests"), 1, "the ADAPTER has EnableStandardRequests")
    Do $$$AssertEquals(..HasProperty("EnsLib.SOAP.Service", "EnableStandardRequests"), 0, "the SOAP service base does NOT")
    Do $$$AssertEquals(..HasProperty("Example.BS.SoapAdapterMode", "EnableStandardRequests"), 0, "nor does a service that kept its adapter")
    Do $$$AssertEquals(..HasProperty("Example.BS.MyService", "EnableStandardRequests"), 0, "nor one that blanked it")

    // The HTTP family DOES have a Host copy -- which is why "it's a Host setting" is a plausible and
    // wrong generalisation for SOAP.
    Do $$$AssertEquals(..HasProperty("EnsLib.HTTP.Service", "EnableStandardRequests"), 1, "the HTTP service has its own HOST copy -- a different family, not an alternative target")
}

/// `Parameter ADAPTER;` records an EMPTY default; it does not remove the parameter.
Method TestBlankAdapterIsAnEmptyDefaultNotAMissingOne()
{
    Do $$$AssertEquals(..AdapterOf("EnsLib.SOAP.Service"), "EnsLib.SOAP.InboundAdapter", "the base declares the adapter")
    Do $$$AssertEquals(..AdapterOf("Example.BS.SoapAdapterMode"), "EnsLib.SOAP.InboundAdapter", "a service that omits the declaration KEEPS it")
    Do $$$AssertEquals(..AdapterOf("Example.BS.MyService"), "", "and `Parameter ADAPTER;` records an EMPTY default")
    Do $$$AssertNotEquals(..AdapterOf("Example.BS.MyService"), "<no ADAPTER parameter>", "not an absent parameter -- the row exists with an empty value")
}

/// The adapter-mode item carries the setting, on the Adapter.
Method TestAdapterModeItemSetsItOnTheAdapter()
{
    Set tTarget = ..TargetOf("BS.SoapAdapter", "EnableStandardRequests")
    Do $$$AssertEquals(tTarget, "Adapter", "EnableStandardRequests must be Target=Adapter: got '" _ tTarget _ "'")

    Set tValue = ..ValueOf("BS.SoapAdapter", "EnableStandardRequests")
    Do $$$AssertEquals(tValue, 1, "and it must be turned ON -- the adapter's own default is 0")
}

/// The direct-mode item carries NO such setting, because it has no adapter.
Method TestDirectModeItemHasNoSuchSetting()
{
    Do $$$AssertEquals(..TargetOf("Example.BS.MyService", "EnableStandardRequests"), "", "a service with no adapter must not carry the setting at all")

    // Control: that item DOES carry other settings, so "not found" is not "I could not read the item".
    Do $$$AssertEquals(..TargetOf("Example.BS.MyService", "AlertOnError"), "Host", "control: the item is readable and its other setting resolves")
}

/// The FQCN exception to the item-naming convention.
Method TestDirectModeItemIsNamedByFqcn()
{
    Set tClass = ""
    &sql(SELECT ClassName INTO :tClass FROM Ens_Config.Item
         WHERE Production = 'Example.Productions.SoapInbound' AND Name = 'Example.BS.MyService')
    Do $$$AssertEquals(SQLCODE, 0, "an item named by the FQCN must exist")
    Do $$$AssertEquals(tClass, "Example.BS.MyService", "and its Name must EQUAL its ClassName -- URL dispatch resolves the WSDL by it")

    // And the adapter-mode item follows the ordinary convention, so the exception is visibly an
    // exception rather than the rule.
    Set tOther = ""
    &sql(SELECT ClassName INTO :tOther FROM Ens_Config.Item
         WHERE Production = 'Example.Productions.SoapInbound' AND Name = 'BS.SoapAdapter')
    Do $$$AssertEquals(SQLCODE, 0, "the adapter-mode item exists")
    Do $$$AssertNotEquals(tOther, "BS.SoapAdapter", "and is named Tipo.Name, NOT by its class")
}

/// Every setting in the production targets the side its property lives on.
Method TestEverySettingTargetsTheRightSide()
{
    Set tProd = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Do $$$AssertEquals($IsObject(tProd), 1, "the production must open")

    Set tChecked = 0, tFindings = ""
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        For j = 1:1:tItem.Settings.Count() {
            Set tSet = tItem.Settings.GetAt(j)
            Set tChecked = tChecked + 1
            Set tOnHost = ..HasProperty(tItem.ClassName, tSet.Name)
            Set tAdapter = ..AdapterOf(tItem.ClassName)
            Set tOnAdapter = 0
            If (tAdapter '= "") && (tAdapter '= "<no ADAPTER parameter>") {
                Set tOnAdapter = ..HasProperty(tAdapter, tSet.Name)
            }
            If tOnHost && (tSet.Target '= "Host") {
                Set tFindings = tFindings _ " | " _ tItem.Name _ "." _ tSet.Name _ " is a Host property but Target=" _ tSet.Target
            }
            If tOnAdapter && 'tOnHost && (tSet.Target '= "Adapter") {
                Set tFindings = tFindings _ " | " _ tItem.Name _ "." _ tSet.Name _ " is an Adapter property but Target=" _ tSet.Target
            }
        }
    }
    Do $$$AssertEquals(tChecked > 0, 1, "the sweep must have examined some settings -- zero means it read nothing")
    Do $$$AssertEquals(tFindings, "", "every setting must target the side its property lives on. Findings:" _ tFindings)
}

ClassMethod TargetOf(pItem As %String, pSetting As %String) As %String [ Private ]
{
    Set tProd = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If '$IsObject(tProd) {
        Quit ""
    }
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        If tItem.Name = pItem {
            For j = 1:1:tItem.Settings.Count() {
                Set tSet = tItem.Settings.GetAt(j)
                If tSet.Name = pSetting {
                    Return tSet.Target
                }
            }
        }
    }
    Quit ""
}

ClassMethod ValueOf(pItem As %String, pSetting As %String) As %String [ Private ]
{
    Set tProd = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If '$IsObject(tProd) {
        Quit ""
    }
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        If tItem.Name = pItem {
            For j = 1:1:tItem.Settings.Count() {
                Set tSet = tItem.Settings.GetAt(j)
                If tSet.Name = pSetting {
                    Return tSet.Value
                }
            }
        }
    }
    Quit ""
}

}
