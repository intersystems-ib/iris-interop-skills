/// Rule: BestPractices_Interop_IRIS.md §6.15 "Reading an HTTP response: the three things that are not what the skills say"
/// Validity: Verified against IRIS for Health 2026.1 — and RUN, against a real HTTP response.
/// Severity: High (the boolean trap makes every truth test false, silently).
///
/// Pattern: the oracle for `http-manual-envelope-bo.cls`. It makes a REAL HTTP call — to this
/// instance's own Atelier endpoint on 127.0.0.1, so no external network is involved — because the two
/// claims that needed correcting could only be settled against a response the adapter produced.
///
/// WHY A REAL RESPONSE. A `%Net.HttpResponse` built with `%New()` has `Data` that is **not a stream**
/// (`%RawString`, `$IsObject = 0`), and a stream written in-process is positioned differently from one
/// the HTTP machinery filled. The first attempt at this measurement used a hand-written stream and got
/// a different answer, which is the same harness mistake as §1.17's `%IO.StringStream`: if the
/// question is about what the platform hands you, the measurement has to use what the platform hands
/// you.
///
/// THE BOOLEAN TEST IS THE ONE TO READ FIRST. Measured:
///
///     "true"  = 1   ->  0        +"true"   ->  0
///     "false" = 0   ->  0        +"false"  ->  0
///
/// Neither polarity survives a numeric comparison, so `If resp.Approved = 1` is false for an approved
/// response and `If resp.Approved = 0` is false for a declined one. A `$Select` on `+value` takes the
/// false branch either way. This is the quietest defect in the file: the code reads correctly, runs
/// without error, and is wrong for every input.
///
/// RUN AND MUTATION-CHECKED, measured:
///
///     as shipped                                   PASSED 7/7
///     IsTrue does a numeric test instead             TestBooleanStringsFailNumericComparison FAILS
///     IsTrue becomes case-sensitive                  TestBooleanStringsFailNumericComparison FAILS
///     ReadBody drops the Rewind                      TestSecondReadNeedsRewind               FAILS
///     ReadBody drops the $IsObject(Data) guard       TestDataIsNotAlwaysAStream              FAILS
///     ReadBody drops the null-response guard         TestNullResponseIsGuarded               FAILS
///
/// All six versions compile. Note which test the Rewind mutation reddens: the SECOND-read one, not
/// the first-read one -- which is the corrected understanding, made executable.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.HttpResponseReading", namespace="<NS>")
Class Example.Tests.HttpResponseReading Extends %UnitTest.TestProduction
{

Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// A real response from this instance's own Atelier endpoint. Returns "" if the call could not be
/// made, so a test can skip rather than fail on an environment issue.
ClassMethod RealResponse() As %Net.HttpResponse [ Private ]
{
    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = "127.0.0.1"
    Set tReq.Port = 52773
    Set tReq.Https = 0
    Set tReq.Username = "_SYSTEM"
    Set tReq.Password = "SYS"
    Set tSC = tReq.Get("/api/atelier/")
    If $$$ISERR(tSC) {
        Quit ""
    }
    Quit tReq.HttpResponse
}

/// THE POINT. Both boolean strings fail a numeric comparison, in both directions.
Method TestBooleanStringsFailNumericComparison()
{
    Set tTrue = "true"
    Set tFalse = "false"

    // The trap, both polarities.
    Do $$$AssertEquals(tTrue = 1, 0, """true"" = 1 is FALSE -- an approved response fails a =1 test")
    Do $$$AssertEquals(+tTrue, 0, "and +""true"" is 0, so a $Select on the numeric value takes the false branch")
    Do $$$AssertEquals(tFalse = 0, 0, """false"" = 0 is ALSO false -- you cannot test either polarity numerically")

    // The control: string comparison works, which is what makes the trap a trap rather than a
    // platform fault.
    Do $$$AssertEquals(tTrue = "true", 1, "control: comparing to the STRING works")

    // And the shipped helper gets every form right.
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue("true"), 1, "IsTrue('true')")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue("TRUE"), 1, "case-insensitive")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue(" yes "), 1, "whitespace-tolerant")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue("1"), 1, "and accepts the numeric form")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue("false"), 0, "IsTrue('false')")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue("0"), 0, "IsTrue('0')")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).IsTrue(""), 0, "and empty is not true")
}

/// A real response's Data stream is positioned at the START -- so the first read needs no Rewind.
/// This is the claim the coverage map had backwards.
Method TestFirstReadNeedsNoRewind()
{
    Set tResp = ..RealResponse()
    If '$IsObject(tResp) {
        Do $$$LogMessage("no HTTP response available in this environment -- skipping")
        Do $$$AssertEquals(1, 1, "skipped")
        Quit
    }

    Do $$$AssertEquals(tResp.StatusCode, 200, "control: the call succeeded")
    Do $$$AssertEquals($IsObject(tResp.Data), 1, "a response with a body carries a STREAM in Data")
    Do $$$AssertEquals(tResp.Data.AtEnd, 0, "and the adapter leaves it at the START -- AtEnd is 0 before any read")

    Set tFirst = tResp.Data.Read(80)
    Do $$$AssertNotEquals(tFirst, "", "so a FIRST read without Rewind returns content, not empty")
    Do $$$AssertEquals($Length(tFirst) > 0, 1, "measured 80 characters of the body")
}

/// Where Rewind DOES matter: a second read. This is the real justification.
Method TestSecondReadNeedsRewind()
{
    Set tResp = ..RealResponse()
    If '$IsObject(tResp) {
        Do $$$AssertEquals(1, 1, "skipped -- no HTTP response available")
        Quit
    }

    // Consume it once, the way a trace or a content sniff would.
    Set tFull = ##class(Example.BO.HttpManualEnvelope).ReadBody(tResp)
    Do $$$AssertNotEquals(tFull, "", "control: the body reads")
    Do $$$AssertEquals(tResp.Data.AtEnd, 1, "and the stream is now at the END")

    // A raw read without Rewind now gets nothing -- the actual failure mode.
    Set tRaw = tResp.Data.Read(80)
    Do $$$AssertEquals(tRaw, "", "a SECOND raw read returns EMPTY -- this is what Rewind prevents")

    // ReadBody rewinds, so it still works.
    Set tAgain = ##class(Example.BO.HttpManualEnvelope).ReadBody(tResp)
    Do $$$AssertEquals(tAgain, tFull, "ReadBody rewinds, so it is repeatable")
}

/// The null-response guard, and why it is needed.
Method TestNullResponseIsGuarded()
{
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).ReadBody(""), "", "ReadBody on a null response returns empty, not a throw")

    // And the reason the BO checks $IsObject instead of touching .StatusCode: it throws.
    Set tThrew = 0
    Set tNull = ""
    Try {
        Set tIgnored = tNull.StatusCode
    }
    Catch tEx {
        Set tThrew = 1
        Set tName = tEx.Name
    }
    Do $$$AssertEquals(tThrew, 1, ".StatusCode on an unset response THROWS")
    Do $$$AssertEquals($Get(tName), "<INVALID OREF>", "with <INVALID OREF>, which names neither the adapter nor the endpoint")
}

/// A fresh response's Data is NOT a stream -- which is why ReadBody checks before reading.
Method TestDataIsNotAlwaysAStream()
{
    Set tFresh = ##class(%Net.HttpResponse).%New()
    Do $$$AssertEquals($IsObject(tFresh.Data), 0, "a response with no body has Data as a plain value, not a stream")
    Do $$$AssertEquals(##class(Example.BO.HttpManualEnvelope).ReadBody(tFresh), "", "and ReadBody handles it rather than throwing <INVALID OREF>")
}

/// The signature, asserted from the dictionary -- the two skills call it with 3 and 6 arguments.
Method TestSendFormDataArrayShape()
{
    Set tSpec = ""
    &sql(SELECT FormalSpec INTO :tSpec FROM %Dictionary.CompiledMethod
         WHERE parent = 'EnsLib.HTTP.OutboundAdapter' AND Name = 'SendFormDataArray')
    Do $$$AssertEquals(SQLCODE, 0, "the method must exist")
    Do $$$AssertEquals($Find(tSpec, "pFormVarNames:%String=""""") > 0, 1, "pFormVarNames is the FOURTH parameter and defaults to empty: " _ tSpec)
    Do $$$AssertEquals($Find(tSpec, "pHttpResponse") > 0, 1, "the response is the first, by reference")
}

}
