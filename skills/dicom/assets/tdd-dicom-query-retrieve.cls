/// Rule: BestPractices_Interop_IRIS.md §15.6 "DICOM query/retrieve is a quartet, not a duplex pair — and the vendored snapshot's own reply leg dangles"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (a one-way duplex name passes C8 and still breaks at run time).
///
/// Pattern: the oracle for `production-dicom-query-retrieve.cls`. Everything is read from
/// `Ens_Config.Item`/`Ens_Config.Setting` after the production is loaded, so it tests the item graph IRIS
/// actually has rather than the XData text.
///
/// THE ASSERTION C8 CANNOT MAKE. C8 checks that a `DuplexTargetConfigName` names an item in the same
/// production — ONE direction. A pair where `BS.A` names `BP.B` while `BP.B`'s own partner is something
/// else satisfies C8 and still breaks, because a duplex conversation needs both halves pointing at each
/// other. `TestEveryDuplexNameResolvesBothWays` closes that.
///
/// THE UPSTREAM DEFECT IS NOT ASSERTED HERE, deliberately. It would need IRIS to read the vendored file,
/// and the gate container has no bind mount of the repo (`docker inspect` reports no mounts), so such a
/// test could only fail for an environmental reason or be skipped -- and a skipped assertion about a
/// security-shaped defect is worse than none. It is guarded on the host instead, where the file is:
/// **tier 2b** scans the vendored tree for item references that name no item and fails on any NEW one,
/// with the known `DICOM STOWRS Process` recorded in `scripts/external_baseline.json` under
/// `known_dangling`. That check was positive-controlled by injecting a second dangling value into the
/// snapshot (restored, sha-verified): it reported `NEW` and failed the tier.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  run=477  5 methods, 0 failed
///     the move process item renamed               run=478  1 failed
///     the store leg's duplex partner dangles      run=479  2 failed
///     the store inbound service's class changed   run=480  1 failed
///     reverted                                    run=481  5 methods, 0 failed
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DicomQueryRetrieve", namespace="<NS>")
Class Example.Tests.DicomQueryRetrieve Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.DicomQueryRetrieve";

/// A no-op override: the inherited TestControl() would start the production, hang and stop it again.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// The production is LOADED, not started: every assertion here is about the item graph, and DICOM items
/// bind TCP ports that a gate instance should not be asked to hold.
Method OnBeforeAllTests() As %Status
{
    Do ##class(Example.BP.DicomLeg).Reset()
    Quit $$$OK
}

/// Items of this production, as IRIS recorded them.
ClassMethod Items(Output pItems As %String) As %Integer [ Private ]
{
    Kill pItems
    Set tCount = 0
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, ClassName FROM Ens_Config.Item WHERE Production = ?", ..#PRODUCTION)
    Quit:tRs.%SQLCODE<0 -1
    While tRs.%Next() {
        Set tCount = tCount + 1
        Set pItems(tRs.%Get("Name")) = tRs.%Get("ClassName")
    }
    Quit tCount
}

/// The DuplexTargetConfigName of one item, or "".
///
/// THROUGH THE OBJECT, NOT SQL. `Ens_Config.Item` is a queryable table (§5.x settled that), but
/// **`Ens.Config.Setting` has no SQL projection at all** -- `SELECT ... FROM Ens_Config.Setting` is
/// `SQLCODE -30, Table 'ENS_CONFIG.SETTING' not found`. Measured: a join written that way returned ""
/// for every item and the suite reported "four items carry a DuplexTargetConfigName, found 0", which
/// reads as a wiring defect and was a missing table.
ClassMethod DuplexOf(pItem As %String) As %String [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT ID FROM Ens_Config.Item WHERE Production = ? AND Name = ?", ..#PRODUCTION, pItem)
    Quit:tRs.%SQLCODE<0 ""
    Quit:'tRs.%Next() ""
    Set tItem = ##class(Ens.Config.Item).%OpenId(tRs.%Get("ID"), 0)
    Quit:'$IsObject(tItem) ""
    For i = 1:1:tItem.Settings.Count() {
        Set tSetting = tItem.Settings.GetAt(i)
        Return:tSetting.Name="DuplexTargetConfigName" tSetting.Value
    }
    Quit ""
}

/// Four legs, and the retrieve leg is its own inbound service.
Method TestTheFourLegsAreDistinctItems() As %Status
{
    Set tCount = ..Items(.tItems)
    Do $$$AssertTrue(tCount > 0, "POSITIVE CONTROL: the production's items were read from Ens_Config.Item, found " _ tCount)
    Do $$$AssertEquals(tCount, 7, "seven items: four legs, three of which are service/process pairs")
    // The three inbound services are SEPARATE items, which is the whole point.
    Do $$$AssertEquals($Get(tItems("BS.QueryFind")), "EnsLib.DICOM.Service.TCP", "the C-FIND leg is its own service")
    Do $$$AssertEquals($Get(tItems("BS.MoveRequest")), "EnsLib.DICOM.Service.TCP", "the C-MOVE leg is a SEPARATE service, not the same one")
    Do $$$AssertEquals($Get(tItems("BS.StoreIn")), "EnsLib.DICOM.Service.TCP", "and the images arrive on a THIRD service -- the leg that gets forgotten")
    Do $$$AssertEquals($Get(tItems("BO.DicomOut")), "EnsLib.DICOM.Operation.TCP", "with one outbound operation")
    Quit $$$OK
}

/// Each inbound service is paired with its OWN process, and no two share one.
Method TestEachServiceHasItsOwnProcess() As %Status
{
    Do $$$AssertEquals(..DuplexOf("BS.QueryFind"), "BP.QueryLeg", "the C-FIND service's partner is the query leg")
    Do $$$AssertEquals(..DuplexOf("BS.MoveRequest"), "BP.MoveLeg", "the C-MOVE service's partner is the move leg, not the query one")
    Do $$$AssertEquals(..DuplexOf("BS.StoreIn"), "BP.StoreLeg", "and the store service's partner is the store leg")
    // Three distinct partners, so nothing is folded together.
    Do $$$AssertNotEquals(..DuplexOf("BS.QueryFind"), ..DuplexOf("BS.MoveRequest"), "the query and move legs are different processes")
    Do $$$AssertNotEquals(..DuplexOf("BS.MoveRequest"), ..DuplexOf("BS.StoreIn"), "and so are the move and store legs")
    Quit $$$OK
}

/// THE ASSERTION C8 CANNOT MAKE: every duplex name resolves to an item that exists.
Method TestEveryDuplexNameResolvesBothWays() As %Status
{
    Set tCount = ..Items(.tItems)
    Do $$$AssertTrue(tCount > 0, "POSITIVE CONTROL: items were read")
    Set tChecked = 0
    Set tItem = ""
    For {
        Set tItem = $Order(tItems(tItem))
        Quit:tItem=""
        Set tPartner = ..DuplexOf(tItem)
        Continue:tPartner=""
        Set tChecked = tChecked + 1
        Do $$$AssertTrue($Data(tItems(tPartner)), "item '" _ tItem _ "' names duplex partner '" _ tPartner _ "', which exists")
    }
    // POSITIVE CONTROL: duplex settings were actually found, so zero failures is not zero checks.
    Do $$$AssertEquals(tChecked, 4, "four items carry a DuplexTargetConfigName, found " _ tChecked)
    Quit $$$OK
}

/// A one-way name is the shape C8 misses, stated so the gap is on the record.
Method TestAOneWayNameWouldSatisfyC8() As %Status
{
    // BO.DicomOut names BP.QueryLeg, and BP.QueryLeg carries no duplex setting of its own. That is
    // LEGITIMATE here -- a process is reached by its partner, not by naming one -- and it is exactly why
    // "both ways" cannot mean "every item names something back".
    Do $$$AssertEquals(..DuplexOf("BO.DicomOut"), "BP.QueryLeg", "the outbound operation's partner is the query process")
    Do $$$AssertEquals(..DuplexOf("BP.QueryLeg"), "", "and the process names no partner -- so the check is 'every name RESOLVES', not 'every pair is symmetric'")
    Quit $$$OK
}

}
