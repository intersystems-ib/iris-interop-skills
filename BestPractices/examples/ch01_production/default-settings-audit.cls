/// Rule: BestPractices_Interop_IRIS.md §1.16 "System Default Settings accept anything — and auditing them needs the adapter, not just the host"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (an SDS row that matches nothing is silent, and the portal shows it as normal).
///
/// Pattern: the orphan report for `Ens.Config.DefaultSettings`. System Default Settings are the
/// archetypal never-read setting: nothing validates them on the way in, and nothing complains later.
///
/// NOTHING REFUSES A BOGUS ROW. Measured on 2026.1 — three rows saved against a real production:
///
///     ItemName='BS.Adt'   SettingName='FilePath'         (both real)          accepted
///     ItemName='BS.Typo'  SettingName='FilePath'         (no such item)       accepted
///     ItemName='BS.Adt'   SettingName='NoSuchSetting'    (no such setting)    accepted
///
/// Three of three. `%Save()` returns `$$$OK` for all of them. A misspelled item name or setting name
/// produces a row that will never be read by anything, for ever, with no error — and the only
/// verification the plugin previously offered was "confirm it shows blue in the portal", which is a
/// colour, in a UI, for a headless plugin.
///
/// THE TRAP THAT MAKES A NAIVE AUDIT WORSE THAN NONE, and it is why this file exists rather than a
/// one-line query. The obvious check for "is this a real setting?" is the host class's own
/// `GetSettings()`. Measured on `EnsLib.HL7.Service.FileService`:
///
///     host GetSettings has MessageSchemaCategory=1  TargetConfigNames=1  AlertOnError=1
///     host GetSettings has FilePath = 0        <-- and FilePath is set on that very item
///
/// `FilePath` is an **adapter** setting. The host declares `ADAPTER = "EnsLib.File.InboundAdapter"`,
/// and the adapter is what owns `FilePath`, `FileSpec`, `ArchivePath`, `CallInterval`, `Charset`.
/// An audit that consults only the host class reports every one of those as an orphan — false
/// positives on the most commonly-set values in the whole production, which is how a report gets
/// ignored and then deleted. The valid set is the UNION:
///
///     host GetSettings()  ∪  adapter GetSettings()   where adapter = $parameter(host, "ADAPTER")
///
/// Measured both ways: `EnsLib.File.InboundAdapter` has FilePath/FileSpec/ArchivePath/CallInterval/
/// Charset; `EnsLib.File.OutboundAdapter` has FilePath and Charset but NOT FileSpec, ArchivePath or
/// CallInterval — correctly, those are inbound-only. A router
/// (`EnsLib.HL7.MsgRouter.RoutingEngine`) has `ADAPTER = ""` and no adapter half at all.
///
/// THE API THAT LOOKS RIGHT AND CANNOT BE CALLED. `Ens.Config.DefaultSettings` has a method named
/// `findIfSettingInThisClass(pClassname, pSettingName)` — exactly the question this report asks.
/// Measured: `ClassMethod = False`, `Private = True`, `Internal = True`. Calling it gives
/// `<METHOD DOES NOT EXIST>`, not `<PRIVATE METHOD>`, because it is an instance method being
/// reached as a classmethod — an error that sends you looking for a typo in the name. Use
/// `GetSettings()`, which is a public ClassMethod on 412 host and adapter classes.
///
/// WHAT `GetSettings` FILLS, because guessing the shape costs a round trip. A TWO-level array:
///     pSettings(":", <name>)                 every setting, flat — 57 for the FileService
///     pSettings(":localizedCategory", <cat>) the category names
///     pSettings(<category>, <name>)          the same settings grouped
/// So membership is a level-2 `$Data(pSettings(cat, name))` walk, not a `$Order` over the top level
/// — the top level holds CATEGORIES, and a first attempt that walked it found nothing at all.
Class Example.UTL.DefaultSettingsAudit Extends %RegisteredObject
{

/// Report every System Default Settings row for a production that cannot apply to anything.
/// Returns one line per finding, or a line stating the counts when there is nothing to report.
/// Invoke via: SELECT Example_UTL.DefaultSettingsAudit_Audit('Example.Productions.Hl7Intake')
ClassMethod Audit(pProduction As %String) As %String [ SqlProc ]
{
    // THE PRODUCTION MUST BE REGISTERED. Ens_Config.Item is populated when the production class
    // compiles; an unregistered one reads as zero items, and every SDS row would then look like an
    // orphan. Refuse rather than report a page of false findings -- "I read nothing" is not
    // "nothing is wrong".
    Set tItems = 0
    &sql(SELECT COUNT(*) INTO :tItems FROM Ens_Config.Item WHERE Production = :pProduction)
    If (tItems = 0) {
        Return "CANNOT AUDIT: production '" _ pProduction _ "' has no items in Ens_Config.Item. " _
               "It is not registered (compile it), or the name is wrong. Not a clean report."
    }

    Set tFindings = "", tRows = 0, tBad = 0

    Set tRS = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT ItemName, HostClassName, SettingName, SettingValue "_
        "FROM Ens_Config.DefaultSettings WHERE ProductionName = ? ORDER BY ItemName, SettingName",
        pProduction)
    While tRS.%Next() {
        Set tRows = tRows + 1
        Set tItem = tRS.%Get("ItemName")
        Set tHost = tRS.%Get("HostClassName")
        Set tSet  = tRS.%Get("SettingName")

        // A wildcard row deliberately applies to many items; it is not an orphan.
        If (tItem = "*") || (tItem = "") {
            Continue
        }

        // 1. Does the item exist in this production?
        Set tActualClass = ""
        &sql(SELECT ClassName INTO :tActualClass FROM Ens_Config.Item
             WHERE Production = :pProduction AND Name = :tItem)
        If (SQLCODE '= 0) {
            Set tBad = tBad + 1
            Set tFindings = tFindings _ " | ORPHAN ITEM: '" _ tItem _ "' is not an item of " _ pProduction
            Continue
        }

        // 2. Does the row's HostClassName agree with the item's actual class? A disagreement is
        //    not fatal -- the row is keyed on the item name -- but it means the row was written
        //    against a different class and its setting name was checked against the wrong thing.
        If (tHost '= "") && (tHost '= tActualClass) {
            Set tBad = tBad + 1
            Set tFindings = tFindings _ " | CLASS MISMATCH: '" _ tItem _ "' is " _ tActualClass _
                            ", the row says " _ tHost
        }

        // 3. Is the setting real on the item's class OR on its adapter? The adapter half is the
        //    one a naive audit omits -- see the header.
        If '..IsSetting(tActualClass, tSet) {
            Set tBad = tBad + 1
            Set tFindings = tFindings _ " | ORPHAN SETTING: '" _ tSet _ "' is not a setting of " _
                            tActualClass _ ..AdapterNote(tActualClass)
        }
    }

    If (tRows = 0) {
        Return "no System Default Settings rows for '" _ pProduction _ "' (" _ tItems _ " items checked)"
    }
    If (tBad = 0) {
        Return "OK: " _ tRows _ " SDS row(s) all resolve, against " _ tItems _ " items"
    }
    Return "FINDINGS (" _ tBad _ " of " _ tRows _ " rows)" _ tFindings
}

/// Is pSetting a real setting of pClass or of the adapter pClass declares?
/// Public because a reviewer performing this check by hand needs exactly this answer.
ClassMethod IsSetting(pClass As %String, pSetting As %String) As %Boolean [ SqlProc ]
{
    If ..ClassHasSetting(pClass, pSetting) {
        Return 1
    }
    Set tAdapter = ..AdapterOf(pClass)
    If (tAdapter '= "") && ..ClassHasSetting(tAdapter, pSetting) {
        Return 1
    }
    Return 0
}

/// The adapter class a host declares, or "" when it has none.
ClassMethod AdapterOf(pClass As %String) As %String [ SqlProc ]
{
    Set tAdapter = ""
    Try {
        Set tAdapter = $parameter(pClass, "ADAPTER")
    }
    Catch {
        Set tAdapter = ""
    }
    Return tAdapter
}

/// Membership in one class's own settings. Walks level 2 -- the top level holds CATEGORIES.
ClassMethod ClassHasSetting(pClass As %String, pSetting As %String) As %Boolean [ Private ]
{
    Kill tS
    Try {
        Do $classmethod(pClass, "GetSettings", .tS)
    }
    Catch {
        // A class with no GetSettings cannot be judged; say no rather than invent a pass.
        Return 0
    }
    Set tCat = ""
    For {
        Set tCat = $Order(tS(tCat))
        Quit:tCat=""
        If $Data(tS(tCat, pSetting)) {
            Return 1
        }
    }
    Return 0
}

/// Names the adapter in a finding, so the reader can see which half was consulted.
ClassMethod AdapterNote(pClass As %String) As %String [ Private ]
{
    Set tA = ..AdapterOf(pClass)
    Quit $Select(tA = "": " (no adapter)", 1: " or its adapter " _ tA)
}

}
