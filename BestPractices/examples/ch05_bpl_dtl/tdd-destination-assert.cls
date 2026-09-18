/// Rule: BestPractices_Interop_IRIS.md §1.15 "Pre-flight validation — and why the old validator returned OK for every production it could not read"
/// Validity: Verified against IRIS for Health 2026.1 — the settings read and both controls were EXECUTED.
/// Severity: High (CR-13 is unperformable without this, and an unperformable criterion is skipped).
///
/// Pattern: name the destination by READING it. CR-13 requires that before a green `iris_test` is
/// believed, the review writes down which external destination the tests actually wrote to — and
/// where that value came from, "read, not assumed". This is the API that makes that possible.
///
/// WHY THIS EXISTED ONLY AS A REQUIREMENT. `conformance-review` has asked for it since CR-13 was
/// written, and nothing in the bank showed how. Worse, the plugin contradicted itself about whether
/// it was possible at all: `interop` stated flatly that `Ens_Config.Item` is **not a queryable
/// table** (`SQLCODE -30`) while `bpl` queried it in three places. One of them had to be wrong and
/// neither compiled anywhere. Measured, and corrected in v1.24.0: **the table is queryable.** The
/// `-30` came from querying the CLASS name (`Ens.Config.Item` → `Table 'CONFIG.ITEM' not found`),
/// which is the dots→underscores rule, not a missing table.
///
/// BOTH ROUTES AGREE, AND THE TEST ASSERTS BOTH, because a conformance reviewer reaching for either
/// should get the same answer:
///     object API   `Ens.Config.Production.%OpenId(p)` → `.Items` → `.Settings` → `.Name/.Target/.Value`
///     SQL          `SELECT ... FROM Ens_Config.Item WHERE Production = ?`
/// Measured on the §2.10 production: `BO.AdtOut` carries `FilePath` with `Target = "Adapter"` and
/// value `/data/hl7/out/`.
///
/// TARGET IS PART OF THE ANSWER, NOT A DETAIL. A setting's `Target` is `Host` or `Adapter`, the
/// Portal shows both in one panel, and a value on the wrong target is accepted and never read. So
/// "FilePath = /data/hl7/out/" is only half a destination; "FilePath on the ADAPTER" is the whole
/// one. A reviewer who reads the name and value but not the target can report a destination the
/// component is not actually using.
///
/// THE CONTROL IS THE POINT OF TestAbsentSettingIsNotEmptyString. Reading a setting that is not
/// configured returns nothing — and nothing looks exactly like a legitimately empty value. CR-13
/// says an unnameable destination is a FINDING, not a pass, so the reader must distinguish "the
/// setting says empty" from "there is no such setting". This test pins that distinction, because a
/// reviewer who cannot make it will report the empty string as the destination.
///
/// THE PRODUCTION MUST BE REGISTERED. `%OpenId` and the table both read the REGISTERED definition,
/// not the XData in the class file. A production whose class merely compiles reads as **zero items**
/// — which is why `Ens.Director.UpdateProduction(0)` runs in setup here, and why §1.15's validator
/// returns INCONCLUSIVE rather than OK for an empty read.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DestinationAssert", namespace="<NS>")
Class Example.Tests.DestinationAssert Extends %UnitTest.TestProduction
{

/// The production whose destination is under review.
Parameter PRODUCTION = "Example.Productions.Hl7Intake";

/// Neutralises the lifecycle: this test reads configuration, it does not need the production running.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Register the compiled production definitions, so the reads below see items rather than nothing.
ClassMethod Register() As %Status [ Private ]
{
    Quit ##class(Ens.Director).UpdateProduction(0)
}

/// Read one setting of one item through the OBJECT API. Returns "" when absent, and sets
/// pFound so the caller can tell absent from empty.
ClassMethod SettingViaObject(pProduction As %String, pItem As %String, pSetting As %String, Output pTarget As %String, Output pFound As %Boolean) As %String [ Private ]
{
    Set pFound = 0, pTarget = ""
    Set tProd = ##class(Ens.Config.Production).%OpenId(pProduction)
    Quit:'$IsObject(tProd) ""
    For i = 1:1:tProd.Items.Count() {
        Set tItem = tProd.Items.GetAt(i)
        Continue:tItem.Name'=pItem
        For j = 1:1:tItem.Settings.Count() {
            Set tSet = tItem.Settings.GetAt(j)
            Continue:tSet.Name'=pSetting
            Set pFound = 1, pTarget = tSet.Target
            Quit
        }
    }
    Quit $Select(pFound: tSet.Value, 1: "")
}

/// Read the same item through SQL, so the two routes can be compared.
ClassMethod ClassNameViaSql(pProduction As %String, pItem As %String) As %String [ Private ]
{
    Set tSQL = "SELECT ClassName FROM Ens_Config.Item WHERE Production = ? AND Name = ?"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pProduction, pItem)
    Quit $Select(tRS.%Next(): tRS.%Get("ClassName"), 1: "")
}

/// PUBLIC, and deliberately so: CR-13 asks a REVIEWER to name the destination, which means the
/// read has to be reachable from outside a test run. Invoke it headlessly:
///     SELECT Example_Tests.DestinationAssert_NameDestination('<Pkg>.Production','BO.AdtOut','FilePath')
/// Returns the value, its Target, and found/not-found — the three things CR-13 needs in one line.
/// (The helpers below are [ Private ], and `$classmethod()` on a Private method raises
/// <PRIVATE METHOD> — which is why this wrapper exists rather than callers reaching in.)
ClassMethod NameDestination(pProduction As %String, pItem As %String, pSetting As %String) As %String [ SqlProc ]
{
    Do ..Register()
    Set tValue = ..SettingViaObject(pProduction, pItem, pSetting, .tTarget, .tFound)
    If 'tFound {
        Quit "NOT CONFIGURED: "_pItem_"."_pSetting_" is absent in "_pProduction_" -- a CR-13 finding, not an empty destination"
    }
    Quit pItem_"."_pSetting_" = "_tValue_"  (Target="_tTarget_", class="_..ClassNameViaSql(pProduction, pItem)_")"
}

/// The destination, named by reading it — value AND target, which is what makes it a destination.
Method TestDestinationIsReadable()
{
    Do $$$AssertStatusOK(..Register())

    Set tValue = ..SettingViaObject(..#PRODUCTION, "BO.AdtOut", "FilePath", .tTarget, .tFound)
    Do $$$AssertEquals(tFound, 1, "the FilePath setting must be found, or CR-13 cannot be performed")
    Do $$$AssertEquals(tValue, "/data/hl7/out/", "the destination is read, not assumed")
    Do $$$AssertEquals(tTarget, "Adapter", "and its TARGET is half the answer -- a Host/Adapter mix-up is silent")
}

/// The SQL route must agree with the object route. A reviewer may reach for either.
Method TestSqlAndObjectAgree()
{
    Do $$$AssertStatusOK(..Register())

    Set tClassSql = ..ClassNameViaSql(..#PRODUCTION, "BO.AdtOut")
    Do $$$AssertEquals(tClassSql, "EnsLib.HL7.Operation.FileOperation", "Ens_Config.Item IS queryable -- this is the corrected fact")

    // and the item really is in the object view too
    Do ..SettingViaObject(..#PRODUCTION, "BO.AdtOut", "FilePath", .tTarget, .tFound)
    Do $$$AssertEquals(tFound, 1, "the same item is visible through the object API")
}

/// The control. An absent setting reads as "" — identical to a setting whose value is empty. CR-13
/// calls an unnameable destination a FINDING, so the reader must be able to tell them apart.
Method TestAbsentSettingIsNotEmptyString()
{
    Do $$$AssertStatusOK(..Register())

    Set tValue = ..SettingViaObject(..#PRODUCTION, "BO.AdtOut", "NoSuchSettingAtAll", .tTarget, .tFound)
    Do $$$AssertEquals(tFound, 0, "an absent setting must report NOT FOUND")
    Do $$$AssertEquals(tValue, "", "...and its value is also empty -- which is why found/not-found is the signal")
}

/// The other control: an item that does not exist must not read as a configured destination.
Method TestAbsentItemIsNotADestination()
{
    Do $$$AssertStatusOK(..Register())

    Do $$$AssertEquals(..ClassNameViaSql(..#PRODUCTION, "BO.NoSuchItem"), "", "an absent item yields no class")
    Do ..SettingViaObject(..#PRODUCTION, "BO.NoSuchItem", "FilePath", .tTarget, .tFound)
    Do $$$AssertEquals(tFound, 0, "and no setting -- zero rows is not a destination")
}

}
