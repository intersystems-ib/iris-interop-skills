/// Rule: BestPractices_Interop_IRIS.md §4.11 "The FHIR payload is a stream id, and every way of touching it fails quietly"
/// Validity: Verified against IRIS for Health Community 2026.1 in a Foundation namespace — and RUN.
/// Severity: High (every assertion here covers a path that returns $$$OK while the payload is lost or shared).
///
/// Pattern: the oracle for `dtl-fhir-redact-quickstream.cls` and `bp-fhir-request-quickstream.cls`.
///
/// EVERY TEST HERE ASSERTS A POSITIVE, because every defect in §4.11 presents as a clean status.
/// "The transform did not error" passes against a transform that produced an empty stream, against
/// one that handed the caller's own stream back, and against one whose payload is still sitting in
/// an unflushed buffer. So the assertions are: the outbound id is non-empty, it is DIFFERENT from
/// the inbound id, the inbound body is unchanged, and the outbound body contains the edit.
///
/// TestExistsIdIsNotAnExistenceTest IS THE ONE TO READ FIRST. It asserts a platform behaviour that
/// looks like a typo when you meet it: `%ExistsId` returns 0 for a stream that `%OpenId` opens and
/// reads in full. It is in the suite rather than only in prose because it is the assertion that
/// will start failing if InterSystems ever gives HS.SDA3.QuickStream a storage definition — at
/// which point §4.11's guidance should change, and this test is what will say so.
///
/// MEASURED VALUES this pins, from the run that preceded it:
///     properties of HS.FHIRServer.Interop.Request  HSCoreVersion, HSMinVersion, QuickStreamId, Request
///     %ExistsId on a live stream                   0   (%OpenId returns an object, body reads in full)
///     %Dictionary.CompiledStorage rows for it      0   ($D(^HS.Stream("16")) = 11 for the same stream)
///     Write("ORIGINAL") + %Save(), both $$$OK      ^HS.Stream(8) EMPTY until Flush or %OnClose
///     Clear() then Write() then Flush()            <SYNTAX>Flush+4^HS.SDA3.QuickStream.1
///     %New() with no second argument               id "T7", data in ^CacheTemp.HS.Stream
///     message %DeleteId, then the stream           still opens and reads; $D unchanged at 11
///
/// RUN AND MUTATION-CHECKED, measured, eight mutations:
///
///     as shipped                                         PASSED 7/7
///     1 DTL assigns source.QuickStreamId to the target    TestTransformDoesNotShareTheStream
///                                                        + TestOutboundCarriesTheEdit        FAIL
///     3 DTL never sets target.QuickStreamId               TestOutboundStreamIsNew
///                                                        + TestOutboundCarriesTheEdit        FAIL
///     4 %ExistsId asserted as 1 instead of 0              TestExistsIdIsNotAnExistenceTest   FAIL
///     6 DTL builds a TEMPORARY stream (%New() default)    TestOutboundStreamIsNew            FAIL
///     7 the flush assertion inverted                      TestSaveDoesNotFlushTheBuffer      FAIL
///     8 the Flush() call removed                          TestSaveDoesNotFlushTheBuffer      FAIL
///
/// TWO MUTATIONS SURVIVE, AND BOTH ARE EXPLAINED RATHER THAN LEFT AS APPARENT HOLES:
///
///   * 2 -- the DTL using `Write()`+`%Save()` instead of `CopyFromAndSave()` stays green. The
///     writing OREF goes out of scope when `Transform` returns, and `%OnClose` flushes the buffer on
///     the way out, so by the time this suite reads the id the body is there. The defect is real and
///     is only observable from INSIDE the writer's frame, which is exactly where
///     `TestSaveDoesNotFlushTheBuffer` asserts it. Catching it through the DTL instead would need a
///     test that reaches into Transform's locals; pinning the platform behaviour is the honest
///     version of the same coverage.
///   * 5 -- replacing the read loop with a single `Read()` stays green because the fixture body is
///     78 characters and `Read()` defaults to 32000. Asserting it needs a >32000-character fixture,
///     which is a 32KB literal in a file whose job is to be read. `TestReadDefaultIsNotUnbounded`
///     closes it from the other side, by asserting the DEFAULT from the dictionary, so the reason
///     the loop is there is pinned even though this fixture cannot exercise it.
///
/// THE ONE SUITE IN THE BANK THAT EXTENDS %UnitTest.TestCase AND NOT %UnitTest.TestProduction, and
/// deliberately. TestProduction's job is to start and stop a production around the tests; every
/// assertion here is about a message class, a DTL and a stream, and none of them needs a running
/// host. Naming `Example.Productions.FhirFacade` to keep the file looking like its 27 siblings would
/// start a FHIR facade -- and hand this suite a failure mode (an unreachable FHIR endpoint) that has
/// nothing to do with anything it asserts. A harness that does not represent its subject is how a
/// green becomes worthless -- `tdd-recordmap-getobject-encoding.cls` exists because the first attempt
/// at that question asked it of a %IO.StringStream instead of a file, and got the opposite answer.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.FhirQuickStreamPayload", namespace="<Foundation NS>")
Class Example.Tests.FhirQuickStreamPayload Extends %UnitTest.TestCase
{

/// A FHIR Patient with a family name the DTL is looking for. 78 characters.
ClassMethod Body() As %String [ Private ]
{
    Quit "{""resourceType"":""Patient"",""id"":""p1"",""name"":[{""family"":""DOE"",""given"":[""JOHN""]}]}"
}

/// A persisted QuickStream holding pWhat. CopyFromAndSave, not Write+%Save — the fixture has to be
/// built the way §4.11 says to build one, or the tests measure the fixture's bug instead.
ClassMethod MakeStream(pWhat As %String, Output pId As %String) As %Status [ Private ]
{
    Set pId = ""
    Set tTmp = ##class(%Stream.GlobalCharacter).%New()
    Do tTmp.Write(pWhat)
    Set tQs = ##class(HS.SDA3.QuickStream).%New("", 0)
    Set tSC = tQs.CopyFromAndSave(tTmp)
    Quit:$$$ISERR(tSC) tSC
    Set pId = tQs.Id
    Quit $$$OK
}

/// Read a whole QuickStream by id. The loop is the point — see TestReadDefaultIsNotUnbounded.
ClassMethod ReadAll(pId As %String) As %String [ Private ]
{
    Set tS = ##class(HS.SDA3.QuickStream).%OpenId(pId)
    Quit:'$IsObject(tS) ""
    Do tS.Rewind()
    Set tOut = ""
    While 'tS.AtEnd { Set tOut = tOut _ tS.Read(32000) }
    Quit tOut
}

/// An inbound FHIR interop request over a real stream.
ClassMethod MakeRequest(Output pReq As HS.FHIRServer.Interop.Request) As %Status [ Private ]
{
    Set tSC = ..MakeStream(..Body(), .tId)
    Quit:$$$ISERR(tSC) tSC
    Set pReq = ##class(HS.FHIRServer.Interop.Request).%New()
    Set pReq.QuickStreamId = tId
    Set pReq.Request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set pReq.Request.RequestMethod = "POST"
    Set pReq.Request.RequestPath = "/Patient"
    Set pReq.Request.Type = "Patient"
    Set pReq.Request.Interaction = "create"
    Quit $$$OK
}

/// The message has no payload property, so no <assign> can reach the body. Asserted from the
/// dictionary rather than from memory, and asserted as a SET so a new property fails the test
/// rather than being silently absorbed.
Method TestMessageHasNoPayloadProperty() As %Status
{
    Set tNames = ""
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty "_
        "WHERE parent = ? AND Private = 0 AND $EXTRACT(Name) <> '%' ORDER BY Name",
        "HS.FHIRServer.Interop.Request")
    While tRs.%Next() { Set tNames = tNames _ $Select(tNames="":"", 1:",") _ tRs.%Get("Name") }
    // A zero here would pass a weaker assertion for the wrong reason, so pin the whole set.
    Do $$$AssertEquals(tNames, "HSCoreVersion,HSMinVersion,QuickStreamId,Request", "the message's public properties are exactly these four; none of them is a payload")
    Quit $$$OK
}

/// %ExistsId is not an existence test for a QuickStream. The stream is created two lines earlier
/// and read back in full, so a 0 here cannot be explained by the stream being absent.
Method TestExistsIdIsNotAnExistenceTest() As %Status
{
    Do $$$AssertStatusOK(..MakeStream(..Body(), .tId), "fixture stream created")
    Do $$$AssertNotEquals(tId, "", "the fixture has an id")
    Set tOpened = ##class(HS.SDA3.QuickStream).%OpenId(tId)
    Do $$$AssertTrue($IsObject(tOpened), "%OpenId returns an object for this id")
    Do $$$AssertEquals(..ReadAll(tId), ..Body(), "and the full body reads back through it")
    // The measured behaviour, and the reason bp-fhir-request-quickstream.cls guards on $IsObject.
    Do $$$AssertEquals(##class(HS.SDA3.QuickStream).%ExistsId(tId), 0, "%ExistsId says 0 for a stream that opens and reads: it has no extent to consult")
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM %Dictionary.CompiledStorage WHERE parent = ?", "HS.SDA3.QuickStream")
    Do tRs.%Next()
    Do $$$AssertEquals(tRs.%Get("n"), 0, "and that is structural: the class has no storage definition")
    Quit $$$OK
}

/// The transform must not hand the caller's own stream back. This is the assertion the one-line
/// <assign> defect fails, and the only one that does.
Method TestTransformDoesNotShareTheStream() As %Status
{
    Do $$$AssertStatusOK(..MakeRequest(.tReq), "inbound request built")
    Do $$$AssertStatusOK(##class(Example.DT.FhirRedact).Transform(tReq, .tOut), "transform ran")
    Do $$$AssertTrue($IsObject(tOut), "and produced a target")
    Do $$$AssertNotEquals(tOut.QuickStreamId, tReq.QuickStreamId, "the target must reference a DIFFERENT stream, or this is a reference copy")
    Quit $$$OK
}

/// The outbound stream exists and is readable. Separated from the edit assertion because an empty
/// stream and a wrongly-edited one are different defects with different fixes.
Method TestOutboundStreamIsNew() As %Status
{
    Do $$$AssertStatusOK(..MakeRequest(.tReq), "inbound request built")
    Do $$$AssertStatusOK(##class(Example.DT.FhirRedact).Transform(tReq, .tOut), "transform ran")
    Do $$$AssertNotEquals(tOut.QuickStreamId, "", "the target carries a stream id")
    Do $$$AssertTrue($IsObject(##class(HS.SDA3.QuickStream).%OpenId(tOut.QuickStreamId)), "and that id opens -- an unflushed buffer would leave an id that opens EMPTY")
    Do $$$AssertNotEquals(..ReadAll(tOut.QuickStreamId), "", "and reads non-empty: %Save() alone leaves ^HS.Stream empty and still returns $$$OK")
    // %New() without the second argument yields a TEMPORARY stream, whose id begins "T" and whose
    // data is in ^CacheTemp.HS.Stream. Readable in this process, gone after a restart -- so a
    // payload id that starts with "T" is a message whose body will vanish, and nothing else in the
    // system will say so.
    Do $$$AssertNotEquals($Extract(tOut.QuickStreamId), "T", "the outbound stream is not a temporary one: " _ tOut.QuickStreamId)
    Quit $$$OK
}

/// The edit landed on the target, and the source is untouched. Both halves, because a transform
/// that edited the inbound stream in place would satisfy the first on its own.
Method TestOutboundCarriesTheEdit() As %Status
{
    Do $$$AssertStatusOK(..MakeRequest(.tReq), "inbound request built")
    Set tInboundBefore = ..ReadAll(tReq.QuickStreamId)
    Do $$$AssertStatusOK(##class(Example.DT.FhirRedact).Transform(tReq, .tOut), "transform ran")
    Do $$$AssertEquals(..ReadAll(tOut.QuickStreamId), "{""resourceType"":""Patient"",""id"":""p1"",""name"":[{""family"":""REDACTED"",""given"":[""JOHN""]}]}", "the outbound body carries the edit")
    Do $$$AssertEquals(..ReadAll(tReq.QuickStreamId), tInboundBefore, "and the inbound body is byte-identical to what it was before the transform")
    Do $$$AssertEquals(tOut.Request.RequestMethod, "POST", "metadata came across: that part <assign> really does do")
    Quit $$$OK
}

/// %Save() returns $$$OK and writes nothing. Asserted INSIDE one method on purpose: the flush that
/// hides this defect happens in %OnClose, when the writing OREF goes out of scope, so a caller that
/// reads the id after the writer's frame has exited cannot see it. That is why mutation 2 below
/// survives, and it is also the real-world shape -- anything that opens the id while the writer
/// still holds the stream (a trace, a SearchTable index, a sibling call) gets an empty body.
Method TestSaveDoesNotFlushTheBuffer() As %Status
{
    Set tQs = ##class(HS.SDA3.QuickStream).%New("", 0)
    Do $$$AssertStatusOK(tQs.Write("ORIGINAL"), "Write returns OK")
    Do $$$AssertStatusOK(tQs.%Save(), "and so does %Save")
    // Both statuses clean, and the stream is empty to everyone but the writer.
    Do $$$AssertEquals(..ReadAll(tQs.Id), "", "yet nothing is persisted: %Save() does not flush the buffer")
    Do $$$AssertStatusOK(tQs.Flush(), "Flush is what writes it")
    Do $$$AssertEquals(..ReadAll(tQs.Id), "ORIGINAL", "and now the body is there")
    Quit $$$OK
}

/// Why the read loop exists, asserted from the dictionary because this fixture is too small to
/// exercise it. Read's first argument DEFAULTS to 32000 -- it is not "read everything".
Method TestReadDefaultIsNotUnbounded() As %Status
{
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT FormalSpec FROM %Dictionary.CompiledMethod "_
        "WHERE parent = ? AND Name = 'Read'", "HS.SDA3.QuickStream")
    Do $$$AssertTrue(tRs.%Next(), "HS.SDA3.QuickStream has a Read method")
    Set tSpec = tRs.%Get("FormalSpec")
    // "&len:%Library.Integer=32000,&sc:%Status" -- the default is the whole point.
    Do $$$AssertTrue(tSpec [ "=32000", "Read's length defaults to 32000, so one Read() truncates a larger payload: " _ tSpec)
    Set tBuf = ##class(%SQL.Statement).%ExecDirect(, "SELECT ""_Default"" AS d FROM %Dictionary.CompiledParameter "_
        "WHERE parent = ? AND Name = 'BUFFERLEN'", "HS.SDA3.QuickStream")
    Do tBuf.%Next()
    Do $$$AssertEquals(tBuf.%Get("d"), 32000, "and BUFFERLEN agrees, which is why 32000 is the chunk size to loop on")
    Quit $$$OK
}

}
