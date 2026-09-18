/// Rule: BestPractices_Interop_IRIS.md §2.12 "A search table indexes nothing until it is assigned — and its props live in the BASE extent"
/// Validity: Verified against IRIS for Health 2026.1 — compiled AND executed.
/// Severity: High (an unindexed search is indistinguishable from a patient who was never there).
///
/// Pattern: an HL7 search table, using SYMBOLIC field paths. Before this file a grep for
/// `SearchTableClass` across the whole bank returned **zero** — the mechanism `message-search-debug`
/// calls "the indexed path" for HL7 had no compiled artefact anywhere.
///
/// SYMBOLIC PATHS WORK HERE, which is worth stating because the skill's own snippet used positions.
/// Measured: this class compiles and registers its props with `[PID:PatientName().FamilyName]` and
/// `[MSH:MessageType.MessageCode]`, both with `DocType=""` and with `DocType="2.5:ADT_A01"`.
/// §2.11's name-first rule therefore applies to search tables as much as to DTLs.
///
/// AND THE CATCH THAT MAKES IT MATTER: a symbolic path resolves only when the document HAS a
/// DocType. `tdd-hl7-fixture-test.cls` already measures that `DocType` is EMPTY after
/// `ImportFromString` and must be set with `DocTypeSet()`. Combine the two and you get the failure
/// this file's companion test pins: indexing a DocType-less message through a symbolic search table
/// writes **no rows at all**, with no error. The search then returns nothing, which reads as "that
/// patient was never here".
///
/// WHERE THE PROPS ACTUALLY LIVE, and it is not where the name suggests. A subclass gets **no
/// extent of its own**: every HL7 search table in the namespace registers into the shared base
/// extent. Measured, after compiling this class:
///
///     Ens_Config.SearchTableProp
///        PropId 1..5   MSHControlID, MSHTypeName, PatientAcct, PatientID, PatientName
///                      ClassExtent = 'EnsLib.HL7.SearchTable'     <- vendor's, always present
///        PropId 61+    the props declared below
///                      ClassExtent = 'EnsLib.HL7.SearchTable'     <- NOT this class's name
///
/// So a query joining on `p.ClassExtent = 'Example.Search.Hl7Adt'` returns **zero rows** — the
/// natural mistake, because that is the class you wrote. Join on the BASE class name.
///
/// THREE MORE MEASURED CONSEQUENCES of that shared extent:
///   1. PROP NAMES ARE NAMESPACE-GLOBAL. Two search table classes declaring the same `PropName`
///      with different paths fail at COMPILE time with
///        ERROR <EnsSearchTable>PropCollision: … cannot override the definition from class '<other>'
///      This is loud and therefore fine — but it means prop names need a prefix if more than one
///      search table will ever exist. That is why the names below are not bare `PatientID`.
///   2. A NAME MATCHING A VENDOR PROP IS SILENTLY REUSED. Declaring `PropName="PatientID"` does not
///      create a row; it binds to the vendor's PropId 4 and your path is ignored. No error.
///   3. PropIds ARE ASSIGNED NAMESPACE-WIDE and are not stable across environments — 61, 62, 63 here
///      purely because of what had been compiled before. Never hard-code one; resolve it by `Name`.
///
/// BOTH HALVES OF A SYMBOLIC PATH MUST BE RIGHT, and the component half is the easier one to get
/// wrong. Measured on a DocType'd ADT^A01:
///
///     [PID:PatientIdentifierList().IDNumber]   '12345'     <- correct
///     [PID:PatientIdentifierList().ID]         INVALID     <- field right, COMPONENT wrong
///     [PID:PatientIDInternalID().ID]           INVALID     <- that is the 2.3 field name
///     [PID:PatientName().FamilyName]           'DOE'
///     [MSH:MessageType.MessageCode]            'ADT'
///
/// Inside a search table a bad path does not fail the compile. It indexes the props that do resolve,
/// returns an error from `IndexDoc` naming the bad `PropertyPath`, and simply omits that one prop --
/// so the table looks populated and one column is quietly always empty. Check `IndexDoc`'s %Status.
///
/// AND A LIMIT ON THE NAME-FIRST RULE worth knowing before applying §2.11 here.
/// `GetFieldNameFromNumber("2.5", "PID", n)` returns a name for 1, 2, 7, 8, 18 and **empty** for
/// 3, 5 and 11 -- the REPEATING fields. But empty does not mean there is no usable name:
/// `PatientName` resolves for PID-5 and `PatientIdentifierList` for PID-3, both of which the
/// function declines to report. So the lookup is a floor, not a ceiling; when it returns empty, the
/// name may still exist and a path is the way to find out.
///
/// ONE TRAP THAT COST A FALSE CONCLUSION while this was measured, recorded because the shape recurs.
/// A first attempt compiled three search tables at once to compare path styles; two "failed" and the
/// obvious reading was that positional paths and `DocType` were rejected. They were not — both had
/// simply collided with the first class's prop names. Re-tested in isolation, each compiles clean. A
/// test whose failure has two possible causes has measured neither.
Class Example.Search.Hl7Adt Extends EnsLib.HL7.SearchTable
{

/// The XML namespace is literally `EnsSearchTable` -- `EnsHL7SearchTable`, the form you would guess
/// from the class name, does not work.
///
/// Prop names are prefixed `Adt` deliberately: the extent is shared namespace-wide, so a bare
/// `PatientID` would bind silently to the vendor's prop and a bare `PatientFamilyName` would collide
/// with any other search table declaring one.
XData SearchSpec [ XMLNamespace = "http://www.intersystems.com/EnsSearchTable" ]
{
<Items>
  <Item DocType="" PropName="AdtPatientID">[PID:PatientIdentifierList().IDNumber]</Item>
  <Item DocType="" PropName="AdtPatientFamilyName">[PID:PatientName().FamilyName]</Item>
  <Item DocType="" PropName="AdtMessageCode">[MSH:MessageType.MessageCode]</Item>
  <Item DocType="" PropName="AdtEventType">[MSH:MessageType.TriggerEvent]</Item>
</Items>
}

}
