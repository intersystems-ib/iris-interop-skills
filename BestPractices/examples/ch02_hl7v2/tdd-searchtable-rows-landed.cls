/// Rule: BestPractices_Interop_IRIS.md §2.12 "A search table indexes nothing until it is assigned — and its props live in the BASE extent"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, not merely compiled.
/// Severity: High (every failure here returns "no rows", which reads as "that patient was never here").
///
/// Pattern: the oracle for `searchtable-hl7-adt.cls` and its two `SearchTableClass` settings in
/// `production-hl7-intake.cls`. Every defect it covers presents as an EMPTY RESULT SET, so the whole
/// file is one exercise in separating "nothing matched" from "nothing was indexed" from "the query
/// could never have matched".
///
/// THE FOUR JOIN SHAPES, measured on ONE indexed message — identical data, four different answers:
///
///     p.PropId = st.PropId AND p.ClassExtent = 'EnsLib.HL7.SearchTable'    -> 8   correct
///     p.ID = st.PropId                                                     -> 0   silent zero
///     p.PropId = st.PropId AND p.ClassExtent = 'Example.Search.Hl7Adt'     -> 0   silent zero
///     p.PropId = st.PropId  (no ClassExtent at all)                        -> 12  OVER-counts
///
/// The first wrong form compares a composite string ID (`EnsLib.HL7.SearchTable||MSHControlID`) to
/// an integer, so it can never match. The second uses the class you actually wrote — the natural
/// mistake — and a subclass has no extent of its own, so it also never matches. The third silently
/// joins across every search table in the namespace: PropId 1 exists in six extents (ASTM, EDIFACT,
/// X12, EDI.XML, HL7, XML), so the count inflates and the `Name` column is drawn from whichever
/// extent won. Two zeros and one over-count, none of them an error.
///
/// AND THE ONE THAT LOOKS LIKE DATA LOSS. Indexing a message with NO DocType through a symbolic
/// search table writes none of that table's props, because a symbolic path cannot resolve without a
/// DocType. Measured, same message both ways:
///
///     DocType = '2.5:ADT_A01'   IndexDoc = OK       8 rows   AdtPatientID, AdtPatientFamilyName,
///                                                            AdtMessageCode, AdtEventType all present
///     DocType = (none)          IndexDoc = ERROR    4 rows   NONE of the four; only the vendor props
///
/// Four rows is the cruel part: the table is not empty, so nothing looks broken. A search on
/// `AdtPatientID` returns nothing while the message sits there with four indexed rows. `IndexDoc`
/// does return an error naming the unresolvable `PropertyPath` — read it.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                   PASSED 6/6
///     p.ID join expected to return 8                TestJoinShapes                          FAILS
///     DocType-less case expected 0 rows             TestWithoutDocTypeSymbolicPropsAreMissing FAILS
///     no-ClassExtent expected NOT to over-count     TestJoinShapes                          FAILS
///     router expected to HAVE SearchTableClass      TestOnlyHostsCarrySearchTableClass      FAILS
///     the search table's own path broken to `.ID`   TestDocTypedMessageIndexesAllProps +
///                                                   TestJoinShapes                          FAIL
///
/// The last mutation reddens two tests, correctly: both depend on all four props indexing. All six
/// versions compile, so tier 2 is green on every one of them -- including the one whose search table
/// silently indexes three props instead of four.
///
/// ONE THING THIS SUITE CANNOT SEE, stated so a green is not over-read. It calls `IndexDoc` directly.
/// It therefore proves the search table WORKS, and not that the production's `SearchTableClass`
/// settings cause it to be called -- that half is asserted structurally
/// (`TestOnlyHostsCarrySearchTableClass`) and by tier-1 C8 over the production, not by a message
/// flowing end to end. Assigning the setting and never verifying a row lands is precisely the
/// failure this rule is about, so: after deploying, search for one real message.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.SearchTableRowsLanded", namespace="<NS>")
Class Example.Tests.SearchTableRowsLanded Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.Hl7Intake";

/// The BASE extent. Every HL7 search table registers here; no subclass gets one of its own.
Parameter BASEEXTENT = "EnsLib.HL7.SearchTable";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// One ADT^A01. pWithDocType decides whether symbolic paths will be able to resolve.
ClassMethod MakeDoc(pWithDocType As %Boolean, Output pDoc) As %Status [ Private ]
{
    Set tCR = $Char(13)
    Set t = "MSH|^~\&|SEND|FAC|RECV|FAC|20260101120000||ADT^A01|MSG0001|P|2.5" _ tCR
    Set t = t _ "EVN|A01|20260101120000" _ tCR
    Set t = t _ "PID|1||12345^^^MRN||DOE^JOHN^Q||19800101|M" _ tCR
    Set pDoc = ##class(EnsLib.HL7.Message).ImportFromString(t, .tSC)
    Quit:$$$ISERR(tSC) tSC
    Set tSC = pDoc.%Save()
    Quit:$$$ISERR(tSC) tSC
    If pWithDocType {
        Set tSC = pDoc.DocTypeSet("2.5:ADT_A01")
        Quit:$$$ISERR(tSC) tSC
        Set tSC = pDoc.%Save()
    }
    Quit tSC
}

/// Rows indexed for one document.
ClassMethod RowCount(pDocId As %String) As %Integer [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM EnsLib_HL7.SearchTable WHERE DocId = :pDocId)
    Quit +$Get(tN)
}

/// Is a named prop indexed for this document? Uses the CORRECT join.
ClassMethod HasProp(pDocId As %String, pName As %String) As %Boolean [ Private ]
{
    Set tE = ..#BASEEXTENT
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM EnsLib_HL7.SearchTable st, Ens_Config.SearchTableProp p
         WHERE st.DocId = :pDocId AND p.PropId = st.PropId AND p.ClassExtent = :tE AND p.Name = :pName)
    Quit (+$Get(tN) > 0)
}

/// THE POINT. A DocType'd message indexes every prop the search table declares.
Method TestDocTypedMessageIndexesAllProps()
{
    Do $$$AssertStatusOK(..MakeDoc(1, .tDoc))
    Set tId = tDoc.%Id()

    Set tSC = ##class(Example.Search.Hl7Adt).IndexDoc(tDoc)
    Do $$$AssertStatusOK(tSC, "IndexDoc must succeed when every path resolves")

    Do $$$AssertEquals(..RowCount(tId), 8, "8 rows: 4 declared here plus 4 vendor props on the base extent")
    Do $$$AssertEquals(..HasProp(tId, "AdtPatientID"), 1, "AdtPatientID indexed, via [PID:PatientIdentifierList().IDNumber]")
    Do $$$AssertEquals(..HasProp(tId, "AdtPatientFamilyName"), 1, "AdtPatientFamilyName indexed")
    Do $$$AssertEquals(..HasProp(tId, "AdtMessageCode"), 1, "AdtMessageCode indexed")
    Do $$$AssertEquals(..HasProp(tId, "AdtEventType"), 1, "AdtEventType indexed")
}

/// WITHOUT a DocType the symbolic props are silently absent -- and the table is NOT empty, which is
/// what makes this read as missing data rather than a broken index.
Method TestWithoutDocTypeSymbolicPropsAreMissing()
{
    Do $$$AssertStatusOK(..MakeDoc(0, .tDoc))
    Set tId = tDoc.%Id()

    Set tSC = ##class(Example.Search.Hl7Adt).IndexDoc(tDoc)
    Do $$$AssertStatusNotOK(tSC, "IndexDoc reports the unresolvable PropertyPath -- read its status")

    // Not zero. That is the trap: four vendor rows land, so the message looks indexed.
    Do $$$AssertEquals(..RowCount(tId), 4, "the vendor props still index, so the table looks populated")
    Do $$$AssertEquals(..HasProp(tId, "AdtPatientID"), 0, "but none of the symbolic props are there")
    Do $$$AssertEquals(..HasProp(tId, "AdtPatientFamilyName"), 0, "none of them")
    Do $$$AssertEquals(..HasProp(tId, "AdtMessageCode"), 0, "none of them")
}

/// The four join shapes on ONE set of rows.
Method TestJoinShapes()
{
    Do $$$AssertStatusOK(..MakeDoc(1, .tDoc))
    Set tId = tDoc.%Id()
    Do $$$AssertStatusOK(##class(Example.Search.Hl7Adt).IndexDoc(tDoc))

    Set tE = ..#BASEEXTENT
    Set tSub = "Example.Search.Hl7Adt"

    Set c1 = 0
    &sql(SELECT COUNT(*) INTO :c1 FROM EnsLib_HL7.SearchTable st, Ens_Config.SearchTableProp p
         WHERE st.DocId = :tId AND p.PropId = st.PropId AND p.ClassExtent = :tE)
    Do $$$AssertEquals(+c1, 8, "correct join: PropId plus the BASE ClassExtent")

    Set c2 = 0
    &sql(SELECT COUNT(*) INTO :c2 FROM EnsLib_HL7.SearchTable st, Ens_Config.SearchTableProp p
         WHERE st.DocId = :tId AND p.ID = st.PropId)
    Do $$$AssertEquals(+c2, 0, "p.ID = st.PropId compares a composite string to an integer -- silent zero")

    Set c3 = 0
    &sql(SELECT COUNT(*) INTO :c3 FROM EnsLib_HL7.SearchTable st, Ens_Config.SearchTableProp p
         WHERE st.DocId = :tId AND p.PropId = st.PropId AND p.ClassExtent = :tSub)
    Do $$$AssertEquals(+c3, 0, "the SUBCLASS name has no extent of its own -- silent zero")

    Set c4 = 0
    &sql(SELECT COUNT(*) INTO :c4 FROM EnsLib_HL7.SearchTable st, Ens_Config.SearchTableProp p
         WHERE st.DocId = :tId AND p.PropId = st.PropId)
    Do $$$AssertEquals(+c4 > 8, 1, "omitting ClassExtent joins across extents and OVER-counts (measured 12)")
}

/// Where the props live, asserted directly -- this is what the join above depends on.
Method TestPropsRegisterIntoTheBaseExtent()
{
    Set tE = ..#BASEEXTENT
    Set tSub = "Example.Search.Hl7Adt"

    Set tMine = 0
    &sql(SELECT COUNT(*) INTO :tMine FROM Ens_Config.SearchTableProp
         WHERE ClassExtent = :tE AND Name %STARTSWITH 'Adt')
    Do $$$AssertEquals(+tMine, 4, "all four declared props are registered under the BASE extent")

    Set tUnderSub = 0
    &sql(SELECT COUNT(*) INTO :tUnderSub FROM Ens_Config.SearchTableProp WHERE ClassExtent = :tSub)
    Do $$$AssertEquals(+tUnderSub, 0, "and none under the subclass name")
}

/// The assignment target: service and operation have SearchTableClass, a router does not.
Method TestOnlyHostsCarrySearchTableClass()
{
    Do $$$AssertEquals(..HasProperty("EnsLib.HL7.Service.FileService", "SearchTableClass"), 1, "the service has it")
    Do $$$AssertEquals(..HasProperty("EnsLib.HL7.Operation.FileOperation", "SearchTableClass"), 1, "the operation has it")
    Do $$$AssertEquals(..HasProperty("EnsLib.HL7.MsgRouter.RoutingEngine", "SearchTableClass"), 0, "a ROUTER does not -- there is no third place to assign it")
}

ClassMethod HasProperty(pClass As %String, pProp As %String) As %Boolean [ Private ]
{
    Set tN = 0
    &sql(SELECT COUNT(*) INTO :tN FROM %Dictionary.CompiledProperty
         WHERE parent = :pClass AND Name = :pProp)
    Quit (+$Get(tN) > 0)
}

}
