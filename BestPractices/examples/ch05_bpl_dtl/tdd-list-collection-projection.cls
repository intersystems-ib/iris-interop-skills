/// Rule: BestPractices_Interop_IRIS.md §5.22 "A collection's child table exists only if you ask — and `array` and `list` disagree on the default"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: Medium (loud, but the name that fails is the correct name, which is what makes it expensive).
///
/// Pattern: the oracle for `msg-list-collection-child-table.cls`. Every assertion reads
/// INFORMATION_SCHEMA or the dictionary, so it needs no production and cannot fail for an unrelated
/// reason.
///
/// THE ASSERTIONS ARE A PAIR, AND THAT IS THE POINT. "The child table is missing" on its own is not a
/// finding — it could mean the class never compiled. Each absence here is asserted next to a presence
/// from the same query, so a zero cannot be a broken query.
///
/// MEASURED VALUES this pins, on the shipped class:
///     Example_MSG.ObsCollections              the parent
///     Example_MSG.ObsCollections_Codes        the `list` WITH SQLPROJECTION = "table"
///     Example_MSG.ObsCollections_Attributes   the `array`, projected WITHOUT being asked
///     Example_MSG.ObsCollections_Notes        ABSENT -- the plain `list`
///     Notes                                  a varchar column ON THE PARENT, holding the $List
///     element_key   integer on the list projection · varchar on the array projection
///     SELECT from the absent table            SQLCODE -30, Table '...' not found
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                              run=330  4 methods, 0 failed
///     Notes gains SQLPROJECTION = "table"     run=331  2 failed -- TestPlainListProjectsNoChildTable
///                                                              and TestSelectingTheAbsentTableIsMinus30
///     Codes loses SQLPROJECTION               run=332  2 failed -- TestAskingProjectsTheChildTable and,
///                                                              via its POSITIVE CONTROL, the -30 test
///     Attributes becomes a `list`             run=333  1 failed -- TestArrayProjectsWithoutBeingAsked
///     reverted                                run=334  4 methods, 0 failed
///
/// Mutation 2 is the one worth reading: it fails the -30 test through that test's positive control, not
/// through its main assertion. Un-projecting `Codes` leaves the -30 still true, so without the control
/// that mutation would have passed a test whose subject it had destroyed.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.ListCollectionProjection", namespace="<NS>")
Class Example.Tests.ListCollectionProjection Extends %UnitTest.TestCase
{

Parameter SCHEMA = "Example_MSG";

/// Does INFORMATION_SCHEMA know this table?
ClassMethod TableExists(pName As %String) As %Boolean [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT COUNT(*) AS n FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?",
        ..#SCHEMA, pName)
    Quit:tRs.%SQLCODE<0 0
    Do tRs.%Next()
    Quit tRs.%Get("n") > 0
}

ClassMethod ColumnType(pTable As %String, pColumn As %String) As %String [ Private ]
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?",
        ..#SCHEMA, pTable, pColumn)
    Quit:tRs.%SQLCODE<0 "<sqlcode "_tRs.%SQLCODE_">"
    Quit $Select(tRs.%Next():tRs.%Get("DATA_TYPE"), 1:"<no such column>")
}

/// A plain `list` projects NO child table -- asserted against a presence from the same query, so the
/// absence cannot be a broken query or an uncompiled class.
Method TestPlainListProjectsNoChildTable() As %Status
{
    Do $$$AssertTrue(..TableExists("ObsCollections"), "POSITIVE CONTROL: the parent table is projected, so the class compiled and the query works")
    Do $$$AssertEquals(..TableExists("ObsCollections_Notes"), 0, "and the plain `list` property projects NO child table")
    // where it actually lives: a single column on the parent, holding the $List
    Do $$$AssertEquals(..ColumnType("ObsCollections", "Notes"), "varchar", "the list is a varchar column ON THE PARENT instead")
    Quit $$$OK
}

/// Asking for it works, and the name is SCHEMA.Class_Property.
Method TestAskingProjectsTheChildTable() As %Status
{
    Do $$$AssertTrue(..TableExists("ObsCollections_Codes"), "SQLPROJECTION = ""table"" on a `list` projects Class_Property")
    // the ordinal column, and its type -- integer for a list
    Do $$$AssertEquals(..ColumnType("ObsCollections_Codes", "element_key"), "integer", "element_key is the INTEGER ordinal for a list")
    Do $$$AssertNotEquals(..ColumnType("ObsCollections_Codes", "Codes"), "<no such column>", "and the value column carries the property's own name")
    Quit $$$OK
}

/// THE ASYMMETRY: an `array` projects a child table with no SQLPROJECTION at all, and its element_key
/// is a VARCHAR because it holds the key rather than an ordinal.
Method TestArrayProjectsWithoutBeingAsked() As %Status
{
    Do $$$AssertTrue(..TableExists("ObsCollections_Attributes"), "an `array` projects a child table WITHOUT SQLPROJECTION -- the opposite default to `list`")
    Do $$$AssertEquals(..ColumnType("ObsCollections_Attributes", "element_key"), "varchar", "and its element_key is a VARCHAR key, not an integer ordinal")
    // Stated as a contrast, because a query written for one and pointed at the other compiles and then
    // compares an integer to a string.
    Do $$$AssertNotEquals(..ColumnType("ObsCollections_Attributes", "element_key"), ..ColumnType("ObsCollections_Codes", "element_key"), "the two element_key types DIFFER between array and list")
    Quit $$$OK
}

/// The error a reader actually meets, asserted so the SQLCODE is on the record.
Method TestSelectingTheAbsentTableIsMinus30() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Example_MSG.ObsCollections_Notes")
    Do $$$AssertEquals(tRs.%SQLCODE, -30, "SELECT against the unprojected collection is SQLCODE -30, not an empty result: " _ tRs.%SQLCODE _ " " _ tRs.%Message)
    // POSITIVE CONTROL: the same statement shape against the table that IS projected must succeed, or
    // the -30 above proves only that the query was malformed.
    Set tOk = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Example_MSG.ObsCollections_Codes")
    Do $$$AssertTrue(tOk.%SQLCODE >= 0, "and the same shape against the projected table succeeds: " _ tOk.%SQLCODE)
    Quit $$$OK
}

}
