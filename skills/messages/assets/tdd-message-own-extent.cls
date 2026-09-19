/// Rule: BestPractices_Interop_IRIS.md §5.10 "Message class design — `%Persistent` must be leftmost, and no compile will tell you it is not"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (this is the ONLY mechanical check for §5.10).
///
/// Pattern: the test that makes a storage decision checkable. It exercises
/// Example.MSG.OrderEvent, which ships beside it, so subject and test are gated together.
///
/// WHY THIS TEST HAS TO EXIST. §5.10's defect survives every other check in this repo: the wrong
/// superclass order compiles clean (tier 2 passes), saves and reads properties back correctly (a
/// functional test passes), and produces no error at any point (the Event Log is empty). The only
/// observable difference is which global the rows land in, so the only assertion that can fail is
/// one that reads the global name out of the class dictionary.
///
/// THE API, and it is not the obvious one. `%Dictionary.CompiledStorage` is the COMPILED view --
/// what the class actually got. `%Dictionary.StorageDefinition` is the SOURCE view, and for a
/// class with no hand-written Storage block it is empty, so a test written against it asserts
/// nothing and passes. Query CompiledStorage, keyed by `parent`:
///
///     SELECT DataLocation FROM %Dictionary.CompiledStorage WHERE parent = '<class>'
///
/// THE NEGATIVE CONTROL IS THE POINT OF TestSharedExtentIsDetectable. An assertion that
/// OrderEvent's DataLocation is `^Example.MSG.OrderEventD` proves nothing on its own -- if the
/// query silently returned "" for every class, a test asserting only "not ^Ens.MessageBodyD"
/// would pass. So the suite also asserts that a class KNOWN to use the shared extent really does
/// report `^Ens.MessageBodyD`. Ens.Request itself is that class, it ships with the platform, and
/// it needs no fixture. If that assertion ever fails, the reader is being lied to by the query,
/// not by the subject.
///
/// THIS TEST WAS MUTATION-CHECKED, not merely compiled. Its subject was recompiled in all three
/// shapes on 2026.1 and the DataLocation read back each time:
///
///   as shipped, Extends (%Persistent, Ens.Request)  ->  ^Example.MSG.OrderEventD   TestOwnExtent PASSES
///   mutated to  Extends (Ens.Request, %Persistent)  ->  ^Ens.MessageBodyD          TestOwnExtent FAILS
///   mutated to  Extends Ens.Request                 ->  ^Ens.MessageBodyD          TestOwnExtent FAILS
///
/// Both mutations compile clean, so tier 2 is green on all three. This assertion is the only
/// thing in the repo that separates them.
///
/// ONE STATEMENT PER LINE. The first draft of this file wrapped the %ExecDirect calls across
/// lines for readability and did not compile: `MPP5612 Referenced macro missing right paren:
/// 'AssertEquals'` -- an error naming a macro several lines away from the real fault. Build the
/// SQL into a variable on its own line instead (`interop` §class-authoring invariants).
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.MessageOwnExtent", namespace="<NS>")
Class Example.Tests.MessageOwnExtent Extends %UnitTest.TestProduction
{

/// Compile-time mandatory. The production is managed outside this test (see TestControl).
Parameter PRODUCTION = "Example.Productions.CensoIntake";

/// Neutralises the production start/stop this superclass would otherwise drive.
Method TestControl() As %Status
{
    Quit $$$OK
}

/// Read the compiled storage global for one class. Returns "" when the class has no compiled
/// storage at all, which the callers below treat as a failure rather than as a pass.
ClassMethod DataLocationOf(pClass As %String) As %String [ Private ]
{
    Set tLoc = ""
    Set tSQL = "SELECT DataLocation FROM %Dictionary.CompiledStorage WHERE parent = ?"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, pClass)
    While tRS.%Next() {
        Set tLoc = tRS.%Get("DataLocation")
        Quit:tLoc'=""
    }
    Quit tLoc
}

/// The subject: a message declared `(%Persistent, Ens.Request)` must get its OWN extent.
Method TestOwnExtent()
{
    Set tLoc = ..DataLocationOf("Example.MSG.OrderEvent")

    // Assert the global BY NAME. "not ^Ens.MessageBodyD" would also be satisfied by "", i.e. by
    // the query having failed -- which is how this test would quietly stop testing anything.
    Do $$$AssertNotEquals(tLoc, "", "CompiledStorage must return a DataLocation for the subject")
    Do $$$AssertEquals(tLoc, "^Example.MSG.OrderEventD", "message must own its extent")
}

/// The negative control. A class known to use the SHARED extent must report it, or the assertion
/// above is not capable of distinguishing anything. Ens.Request ships with the platform, so this
/// needs no fixture and cannot drift with the bank.
Method TestSharedExtentIsDetectable()
{
    Set tLoc = ..DataLocationOf("Ens.Request")
    Do $$$AssertEquals(tLoc, "^Ens.MessageBodyD", "control: shared extent must be observable")
}

/// Checks the index COMPILED. Stated plainly because the mutation run above measured it: the
/// index is present in all three shapes, so this method does NOT distinguish them and is not a
/// second check on §5.10. What the shared extent costs is that the index spans every message type
/// in the namespace rather than this one -- which is a property of the storage, not of the index
/// definition, and is therefore caught by TestOwnExtent alone.
Method TestPerTypeIndexExists()
{
    Set tCount = 0
    Set tSQL = "SELECT COUNT(*) AS n FROM %Dictionary.CompiledIndex WHERE parent = ? AND Name = ?"
    Set tRS = ##class(%SQL.Statement).%ExecDirect(, tSQL, "Example.MSG.OrderEvent", "OrderIdIdx")
    If tRS.%Next() { Set tCount = tRS.%Get("n") }
    Do $$$AssertEquals(tCount, 1, "the per-type index must exist on the message's own extent")
}

}
