/// Rule: BestPractices_Interop_IRIS.md §6.10 "File passthrough relay — Ens.StreamContainer, and the read that only works once"
/// Validity: Verified against IRIS for Health 2026.1 — the assertions below were EXECUTED.
/// Severity: High (this is the only mechanical check for the second-read defect).
///
/// Pattern: the test for the one fact in §6.10 that no compile can reach — that a stream read
/// twice returns "" the second time, and that Rewind() restores it.
///
/// EXECUTED, not merely compiled. The exact sequence these methods assert was run on 2026.1
/// against a saved-and-reopened Ens.StreamContainer:
///     save=OK  reopened=ok  read1=[line-1]  read2=[]  afterRewind=[line-1]  filename=[in.txt]
///
/// WHY read2 IS THE ASSERTION THAT MATTERS. A test that only checks `read1` passes against every
/// implementation, correct or not — the first read always works. The defect lives entirely in what
/// the SECOND consumer sees, so the empty string has to be asserted explicitly rather than treated
/// as an edge case.
///
/// NO PRODUCTION NEEDED. Ens.StreamContainer is a plain %Persistent (verified superclass:
/// %Library.Persistent, Ens.Util.MessageBodyMethods, %XML.Adaptor), so it constructs, saves and
/// reopens with no interop lifecycle at all — unlike a Business Service, which cannot even be
/// %New()d. That is why this one is cheap to run and worth running.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.StreamContainerRewind", namespace="<NS>")
Class Example.Tests.StreamContainerRewind Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.FileRelay";

/// Neutralises the production start/stop this superclass would otherwise drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Build a saved container holding one known line. Returns its id.
ClassMethod SaveOne(pText As %String, Output pId As %String) As %Status [ Private ]
{
    Set tStream = ##class(%Stream.GlobalCharacter).%New()
    Do tStream.Write(pText)
    Set tContainer = ##class(Ens.StreamContainer).%New(tStream)
    Set tContainer.OriginalFilename = "in.txt"
    Set tSC = tContainer.%Save()
    Quit:$$$ISERR(tSC) tSC
    Set pId = tContainer.%Id()
    Quit $$$OK
}

/// The point: the second read is empty, and Rewind() brings the content back.
Method TestSecondReadIsEmpty()
{
    Do $$$AssertStatusOK(..SaveOne("line-1", .tId))
    Set tContainer = ##class(Ens.StreamContainer).%OpenId(tId)
    Do $$$AssertTrue($IsObject(tContainer), "the container must reopen")
    Do $$$AssertTrue($IsObject(tContainer.Stream), "the reopened container must carry its stream")

    Do $$$AssertEquals(tContainer.Stream.Read(100), "line-1", "first read returns the content")
    Do $$$AssertEquals(tContainer.Stream.Read(100), "", "SECOND read is empty -- this is the defect")
    Do tContainer.Stream.Rewind()
    Do $$$AssertEquals(tContainer.Stream.Read(100), "line-1", "Rewind() restores the content")

    Do ##class(Ens.StreamContainer).%DeleteId(tId)
}

/// OriginalFilename is the only link back to the source file, and %f in the operation's
/// Filename setting is a read of it.
Method TestOriginalFilenameSurvives()
{
    Do $$$AssertStatusOK(..SaveOne("payload", .tId))
    Set tContainer = ##class(Ens.StreamContainer).%OpenId(tId)
    Do $$$AssertEquals(tContainer.OriginalFilename, "in.txt", "OriginalFilename must survive the round trip")
    Do ##class(Ens.StreamContainer).%DeleteId(tId)
}

/// Negative control. If %OpenId silently returned an empty container, TestSecondReadIsEmpty's
/// "second read is empty" assertion would pass for the WRONG reason. Prove the round trip
/// carries content at all before trusting an assertion about absence.
Method TestRoundTripCarriesContent()
{
    Do $$$AssertStatusOK(..SaveOne("control-payload", .tId))
    Set tContainer = ##class(Ens.StreamContainer).%OpenId(tId)
    Do $$$AssertTrue($IsObject(tContainer), "control: the container reopens")
    Do $$$AssertEquals(tContainer.Stream.Read(100), "control-payload", "control: a fresh read returns what was written")
    Do ##class(Ens.StreamContainer).%DeleteId(tId)
}

}
