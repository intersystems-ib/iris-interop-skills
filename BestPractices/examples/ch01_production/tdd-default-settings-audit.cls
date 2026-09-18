/// Rule: BestPractices_Interop_IRIS.md §1.16 "System Default Settings accept anything — and auditing them needs the adapter, not just the host"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (the report this guards is only useful if it is trusted, and one false positive ends that).
///
/// Pattern: the oracle for `default-settings-audit.cls` in this directory.
///
/// THE ASSERTION THAT MATTERS MOST HERE IS A NEGATIVE ONE. `TestAdapterSettingsAreNotFlagged` is
/// what keeps this report usable. `FilePath`, `FileSpec`, `ArchivePath`, `CallInterval` and
/// `Charset` are **adapter** settings — the host class's own `GetSettings()` does not know them —
/// and an audit that consults only the host reports all five as orphans. They are among the most
/// commonly set values in any file-based production, so that version of the report is not merely
/// imperfect, it is noise, and a report that cries wolf on `FilePath` gets switched off in a week.
///
/// THE PREMISE IS ALSO ASSERTED, not assumed. `TestNothingRefusesABogusRow` saves a row naming an
/// item that does not exist and a setting that does not exist, and asserts `%Save()` returns
/// `$$$OK`. If some future IRIS version starts validating these, that test fails and this whole
/// file's reason for existing has changed — which is exactly when you want to be told.
///
/// AND THE "I READ NOTHING" GUARD. `Ens_Config.Item` is populated for REGISTERED productions, so an
/// uncompiled or misspelled production name reads as zero items. An audit that treated that as
/// "nothing to report" would return a clean bill of health for a production it never looked at.
/// The report refuses instead, and `TestUnregisteredProductionRefuses` pins it.
///
/// MEASURED, from the run that preceded these tests:
///     3 seeded rows (1 good, 1 orphan item, 1 orphan setting) -> FINDINGS (2 of 3 rows)
///     IsSetting(FileService, FilePath/FileSpec/ArchivePath/CallInterval) -> all True via the adapter
///     IsSetting(FileService, NoSuchSetting)                              -> False
///     Audit('Example.Productions.NoSuchThing')                           -> CANNOT AUDIT
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                  PASSED 8/8
///     adapter half removed from IsSetting          TestAdapterSettingsAreNotFlagged  FAILS
///     the "I read nothing" guard removed           TestUnregisteredProductionRefuses FAILS
///     orphan-ITEM detection removed                TestOrphanItemIsFound             FAILS
///     orphan-SETTING detection removed             TestOrphanSettingIsFound          FAILS
///
/// Each mutation reddens exactly its own test. All five versions compile, so tier 2 is green on
/// every one of them -- including the one that reports a clean bill of health for a production it
/// never read.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DefaultSettingsAudit", namespace="<NS>")
Class Example.Tests.DefaultSettingsAudit Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// The production this suite audits. It must be REGISTERED (its class compiled) for the report to
/// have anything to read -- which is itself one of the things under test.
Parameter TARGET = "Example.Productions.Hl7Intake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Remove every SDS row for the target, so each test starts from a known state.
ClassMethod ClearRows() As %Status [ Private ]
{
    Set tP = ..#TARGET
    &sql(DELETE FROM Ens_Config.DefaultSettings WHERE ProductionName = :tP)
    Quit $$$OK
}

/// Save one SDS row. Returns the %Status so a test can assert on it.
ClassMethod AddRow(pItem As %String, pClass As %String, pSetting As %String, pValue As %String) As %Status [ Private ]
{
    Set tObj = ##class(Ens.Config.DefaultSettings).%New()
    Set tObj.ProductionName = ..#TARGET
    Set tObj.ItemName = pItem
    Set tObj.HostClassName = pClass
    Set tObj.SettingName = pSetting
    Set tObj.SettingValue = pValue
    Set tObj.Deployable = 1
    Quit tObj.%Save()
}

ClassMethod Audit() As %String [ Private ]
{
    Quit ##class(Example.UTL.DefaultSettingsAudit).Audit(..#TARGET)
}

/// THE PREMISE. Nothing validates an SDS row on the way in -- which is why the report exists.
Method TestNothingRefusesABogusRow()
{
    Do ..ClearRows()

    Do $$$AssertStatusOK(..AddRow("BS.Typo", "EnsLib.HL7.Service.FileService", "FilePath", "/x/"), "a row naming a NON-EXISTENT ITEM is accepted")
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "NoSuchSetting", "x"), "a row naming a NON-EXISTENT SETTING is accepted")

    Do ..ClearRows()
}

/// Control: with no rows at all the report says so, and says how many items it checked -- so a
/// clean result carries the evidence that it looked.
Method TestNoRowsIsReportedAsSuch()
{
    Do ..ClearRows()
    Set tOut = ..Audit()
    Do $$$AssertEquals($Find(tOut, "no System Default Settings rows") > 0, 1, "an empty set is reported as empty, not as OK")
    Do $$$AssertEquals($Find(tOut, "items checked") > 0, 1, "and it states how many items it read")
}

/// A row naming an item the production does not have.
Method TestOrphanItemIsFound()
{
    Do ..ClearRows()
    Do $$$AssertStatusOK(..AddRow("BS.Typo", "EnsLib.HL7.Service.FileService", "FilePath", "/x/"))

    Set tOut = ..Audit()
    Do $$$AssertEquals($Find(tOut, "ORPHAN ITEM") > 0, 1, "the orphaned item name must be reported")
    Do $$$AssertEquals($Find(tOut, "BS.Typo") > 0, 1, "and named")

    Do ..ClearRows()
}

/// A row naming a setting that exists on neither the host nor its adapter.
Method TestOrphanSettingIsFound()
{
    Do ..ClearRows()
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "NoSuchSetting", "x"))

    Set tOut = ..Audit()
    Do $$$AssertEquals($Find(tOut, "ORPHAN SETTING") > 0, 1, "the orphaned setting name must be reported")
    Do $$$AssertEquals($Find(tOut, "NoSuchSetting") > 0, 1, "and named")

    Do ..ClearRows()
}

/// THE FALSE-POSITIVE GUARD, and the most important test here. Every one of these is an ADAPTER
/// setting: the host class's own GetSettings() does not know any of them. An audit that consulted
/// only the host would report all four as orphans -- on the most commonly set values in a
/// file-based production, which is how a report stops being read.
Method TestAdapterSettingsAreNotFlagged()
{
    Do ..ClearRows()
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "FilePath", "/data/in/"))
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "FileSpec", "*.hl7"))
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "ArchivePath", "/data/arch/"))
    Do $$$AssertStatusOK(..AddRow("BS.Adt", "EnsLib.HL7.Service.FileService", "CallInterval", "5"))

    Set tOut = ..Audit()
    Do $$$AssertEquals($Find(tOut, "ORPHAN") > 0, 0, "no adapter setting may be reported as an orphan: " _ tOut)
    Do $$$AssertEquals($Find(tOut, "OK: 4 SDS row(s)") > 0, 1, "all four resolve, via the adapter")

    // And directly, so a failure above points at the right half.
    Do $$$AssertEquals(##class(Example.UTL.DefaultSettingsAudit).IsSetting("EnsLib.HL7.Service.FileService", "FilePath"), 1, "FilePath resolves through the adapter")
    Do $$$AssertEquals(##class(Example.UTL.DefaultSettingsAudit).IsSetting("EnsLib.HL7.Service.FileService", "NoSuchSetting"), 0, "control: a genuinely absent setting still resolves to 0")

    Do ..ClearRows()
}

/// A host setting (not an adapter one) must resolve too -- otherwise the test above could pass
/// against an IsSetting that simply always says yes.
Method TestHostSettingsResolveToo()
{
    Do $$$AssertEquals(##class(Example.UTL.DefaultSettingsAudit).IsSetting("EnsLib.HL7.Service.FileService", "MessageSchemaCategory"), 1, "a HOST setting resolves")
    Do $$$AssertEquals(##class(Example.UTL.DefaultSettingsAudit).AdapterOf("EnsLib.HL7.MsgRouter.RoutingEngine"), "", "a router declares no adapter")
    Do $$$AssertEquals(##class(Example.UTL.DefaultSettingsAudit).AdapterOf("EnsLib.HL7.Service.FileService"), "EnsLib.File.InboundAdapter", "and a file service declares one")
}

/// "I read nothing" must not be reported as "nothing is wrong".
Method TestUnregisteredProductionRefuses()
{
    Set tOut = ##class(Example.UTL.DefaultSettingsAudit).Audit("Example.Productions.NoSuchThing")
    Do $$$AssertEquals($Find(tOut, "CANNOT AUDIT") > 0, 1, "an unreadable production must refuse, not report clean")
    Do $$$AssertEquals($Find(tOut, "OK:") > 0, 0, "and must not contain an OK verdict")
}

}
