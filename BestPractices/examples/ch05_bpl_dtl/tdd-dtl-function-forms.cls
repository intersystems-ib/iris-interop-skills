/// Rule: BestPractices_Interop_IRIS.md §5.13 "Calling a function from a DTL — the two forms have opposite rules and the wrong one is silent"
/// Validity: Verified against IRIS for Health 2026.1 — the assertions below were EXECUTED.
/// Severity: High (the bare call form compiles clean; only a run catches it).
///
/// Pattern: the test for §5.13. It exercises Example.DT.CensoToMenus beside it, and every
/// assertion is on a value the transform WRITES — because the defect this guards produces no
/// error at compile time and an exception only when a message flows.
///
/// WHY AN ASSERTION ON THE OUTPUT IS THE ONLY OPTION. The three wrong call forms fail in three
/// different places, and only one of them is somewhere a gate can see:
///     ..CustomFunc(x)     COMPILE FAILS (MPP5392) -- tier 2 catches this one
///     CustomFunc(x)       compiles, <UNDEFINED> at Transform time -- tier 2 is GREEN
///     Func(x) built-in    compiles, <UNDEFINED> at Transform time -- tier 2 is GREEN
/// Two of the three are invisible to every tier in this repo. Calling Transform and reading the
/// target is what separates them.
///
/// MEASURED before these assertions were written, with source OrderId = "  Órden-1001  " and
/// PatientId = "  P-42  ":
///     VendorRef = [orden-1001]                      the custom function RAN
///     Priority  = [UNKNOWN]                         the built-in ..Lookup returned its default
///     Note      = [ref=  Órden-1001   pid=  P-42  ] raw concatenation, deliberately unnormalised
///
/// VendorRef IS THE LOAD-BEARING ASSERTION. "orden-1001" can only be produced by
/// Example.UTL.FunctionSet.NormalizeKey actually executing: it is lower-cased, internally
/// stripped and accent-folded (Ó → o). If the call form were wrong the transform would raise
/// <UNDEFINED> and there would be no target at all — and if someone "fixed" that by removing the
/// call, VendorRef would come back as the raw padded string and this assertion would fail.
///
/// Note IS THE CONTROL. It is deliberately NOT normalised, so it proves the source values really
/// did arrive with padding and an accent. Without it, an assertion that VendorRef is clean could
/// be satisfied by a source that was already clean.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.DtlFunctionForms", namespace="<NS>")
Class Example.Tests.DtlFunctionForms Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test.
Parameter PRODUCTION = "Example.Productions.CensoIntake";

Method TestControl() As %Status
{
    Quit $$$OK
}

/// Source values chosen so that "did the function run" is answerable: padded, mixed case, accented.
ClassMethod Source() As Example.MSG.AcceptOrderReq [ Private ]
{
    Set tReq = ##class(Example.MSG.AcceptOrderReq).%New()
    Set tReq.OrderId = "  Órden-1001  "
    Set tReq.PatientId = "  P-42  "
    Quit tReq
}

/// The custom function, called `##class()`-qualified, must actually have run.
Method TestCustomFunctionRan()
{
    Set tSC = ##class(Example.DT.CensoToMenus).Transform(..Source(), .tOut)
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertTrue($IsObject(tOut), "the transform must produce a target")

    // Only NormalizeKey can produce this: lower-cased, whitespace stripped, accent folded.
    Do $$$AssertEquals(tOut.VendorRef, "orden-1001", "the ##class()-qualified custom function must have run")
    Do $$$AssertNotEquals(tOut.VendorRef, "  Órden-1001  ", "and must not have been passed through unchanged")
}

/// The built-in, called with `..`, must have run and returned its on-miss default.
Method TestBuiltInLookupReturnedDefault()
{
    Set tSC = ##class(Example.DT.CensoToMenus).Transform(..Source(), .tOut)
    Do $$$AssertStatusOK(tSC)

    // No such lookup table exists, so the third argument is what comes back. "" here would mean
    // the default was omitted, which is how a miss becomes indistinguishable from a real value.
    Do $$$AssertEquals(tOut.Priority, "UNKNOWN", "..Lookup must return its on-miss default")
    Do $$$AssertNotEquals(tOut.Priority, "", "an empty Priority would mean the default was dropped")
}

/// The control: the source really did carry padding and an accent, so the cleanliness asserted
/// above is the function's work and not a property of the input.
Method TestSourceWasNotAlreadyClean()
{
    Set tSC = ##class(Example.DT.CensoToMenus).Transform(..Source(), .tOut)
    Do $$$AssertStatusOK(tSC)

    Do $$$AssertEquals(tOut.Note, "ref=  Órden-1001   pid=  P-42  ", "control: the unnormalised copy keeps the padding and the accent")
}

}
