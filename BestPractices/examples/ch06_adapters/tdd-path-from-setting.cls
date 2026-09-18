/// Rule: BestPractices_Interop_IRIS.md §6.18 "Resolving a path from a Setting: the class that compiles and the value that escapes"
/// Validity: Verified against IRIS for Health Community 2026.1 — and RUN.
/// Severity: High (the wrong spelling compiles clean, so a compile-only gate passes a class that cannot run).
///
/// Pattern: the oracle for `path-from-setting-and-runtime.cls`, and the reason the coverage map says
/// this row "must be **exercised**, not merely compiled".
///
/// TestWrongClassCompilesAndFailsAtRuntime IS THE ONE TO READ FIRST, and it is why a compile is not
/// enough. Measured: `##class(%Library.File).InstallDirectory()` compiles **clean** and raises
/// `<METHOD DOES NOT EXIST>` when it runs. Tier 2 — and any CI that only compiles — passes it. The
/// test reaches the same call through `$classmethod` so that this suite itself still compiles, and
/// asserts the exception; asserting "it compiled" would assert the defect.
///
/// AND THE ASSERTION IS THAT `InstallDirectory` IS ON EXACTLY ONE CLASS. `%Library.File` not having
/// it is the sub-claim CR-10 makes; "exactly one class in the instance has it" is stronger and is
/// what makes the note in CR-10 safe to rely on. Both are asserted from the dictionary.
///
/// MEASURED VALUES this pins, from the run that preceded it:
///     ##class(%Library.File).InstallDirectory()   compiles CLEAN -> <METHOD DOES NOT EXIST>
///     %SYSTEM.Util.InstallDirectory()             /usr/irissys/   (trailing separator)
///     $System.Util.InstallDirectory()             identical to the above
///     InstallDirectory exists on                  %SYSTEM.Util, and on NO other class
///     NormalizeDirectory("/usr/irissys/")         /usr/irissys/   (unchanged on this platform)
///   NormalizeFilename(v, "/usr/irissys/"):
///     "mgr/"           -> /usr/irissys/mgr        naive concat gives /usr/irissys/mgr/
///     "csp/../mgr"     -> /usr/irissys/mgr        naive concat leaves the literal ".."
///     "/abs/path"      -> /abs/path               naive concat gives /usr/irissys//abs/path
///     "../etc"         -> /usr/etc                and does NOT text-prefix the base
///
/// RUN AND MUTATION-CHECKED, measured, five mutations:
///
///     as shipped                                        PASSED 6/6
///     1 the escape check removed                         TestAbsoluteSettingIsRefused +
///                                                       TestTraversalOutOfTheTreeIsRefused  FAIL
///     3 Resolve concatenates instead of normalising      TestAbsoluteSettingIsRefused +
///                                                       TestRelativeSettingResolves +
///                                                       TestTraversalOutOfTheTreeIsRefused  FAIL
///     4 ResolveExistingDir skips DirectoryExists         TestMissingDirectoryIsItsOwnError   FAIL
///     5 the empty-Setting guard removed                  TestEmptySettingIsRefused           FAIL
///     2 the base compared UNnormalised                   NO FAILURE -- see below
///
/// MUTATION 3 REDDENING THREE TESTS IS THE USEFUL RESULT. Swapping `NormalizeFilename` for
/// `tBase_pSetting` breaks the relative case, the absolute case AND the traversal case at once — which
/// is the argument for the API in one line: concatenation is not a worse-but-workable spelling, it is
/// wrong for every input shape this class accepts.
///
/// MUTATION 2 SURVIVES, AND IT IS A NON-MUTATION HERE RATHER THAN A WEAK TEST. Comparing against the
/// raw base instead of the normalised one leaves the suite green because on this platform
/// `NormalizeDirectory("/usr/irissys/")` returns its argument unchanged — the two strings are
/// identical, so nothing changed. It would bite where `InstallDirectory()` has no trailing separator.
/// Said here rather than left as an apparent hole, because a surviving mutation is either a weak test
/// or a non-mutation and only one of those needs fixing.
///
/// HOW TO RUN IT -- one compiled class per call, `pattern` does not expand a package:
///     iris_test(pattern="Example.Tests.PathFromSetting", namespace="<NS>")
Class Example.Tests.PathFromSetting Extends %UnitTest.TestCase
{

/// The wrong spelling compiles and dies at run time. Reached through $classmethod so that THIS class
/// still compiles; a literal `##class(%Library.File).InstallDirectory()` would compile here too,
/// which is exactly the point being made.
Method TestWrongClassCompilesAndFailsAtRuntime() As %Status
{
    Set tCaught = ""
    Try {
        Set tIgnored = $classmethod("%Library.File", "InstallDirectory")
    } Catch tEx {
        Set tCaught = tEx.Name
    }
    Do $$$AssertEquals(tCaught, "<METHOD DOES NOT EXIST>", "%Library.File has no InstallDirectory -- and the call form that names it COMPILES, which is why this is a run-time assertion")
    // The dictionary half: not merely "%Library.File lacks it" but "exactly one class has it".
    Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent FROM %Dictionary.CompiledMethod WHERE Name = 'InstallDirectory'")
    Set tOwners = ""
    While tRs.%Next() { Set tOwners = tOwners _ $Select(tOwners="":"", 1:",") _ tRs.%Get("parent") }
    Do $$$AssertEquals(tOwners, "%SYSTEM.Util", "InstallDirectory lives on %SYSTEM.Util and on no other class in the instance")
    Quit $$$OK
}

/// A relative Setting resolves inside the tree, and NOT by concatenation.
Method TestRelativeSettingResolves() As %Status
{
    Set tBase = ##class(Example.UTL.PathFromSetting).InstallDir()
    Do $$$AssertNotEquals(tBase, "", "the install directory is readable")
    Do $$$AssertStatusOK(##class(Example.UTL.PathFromSetting).Resolve("mgr/", .tPath), "a relative Setting resolves")
    Do $$$AssertEquals(tPath, ##class(%File).NormalizeFilename("mgr/", tBase), "and it resolves the way NormalizeFilename does")
    // The difference from concatenation, asserted rather than described: the naive form keeps the
    // trailing separator that the Setting happened to carry.
    Do $$$AssertNotEquals(tPath, tBase _ "mgr/", "which is NOT base_setting -- concatenation keeps the trailing separator")
    // A traversal that stays inside the tree is fine and must not be refused.
    Do $$$AssertStatusOK(##class(Example.UTL.PathFromSetting).Resolve("csp/../mgr", .tInside), "a traversal that stays inside the tree is allowed")
    Do $$$AssertEquals(tInside, tPath, "and lands on the same place as the direct spelling")
    Quit $$$OK
}

/// An absolute Setting escapes the tree, so the default refuses it — and says so.
Method TestAbsoluteSettingIsRefused() As %Status
{
    Set tSC = ##class(Example.UTL.PathFromSetting).Resolve("/abs/path", .tPath)
    Do $$$AssertStatusNotOK(tSC, "an absolute Setting is refused by default")
    Do $$$AssertEquals(tPath, "", "and no path is handed back")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "pAllowAbsolute", "and the error names the way to allow it deliberately")
    // Allowed on request, because some deployments really do put the drop directory elsewhere.
    Do $$$AssertStatusOK(##class(Example.UTL.PathFromSetting).Resolve("/abs/path", .tOk, , 1), "pAllowAbsolute=1 permits it")
    Do $$$AssertEquals(tOk, "/abs/path", "and NormalizeFilename discards the base entirely for an absolute value")
    Quit $$$OK
}

/// The other way out of the tree: `..` far enough to climb above the base.
Method TestTraversalOutOfTheTreeIsRefused() As %Status
{
    Set tSC = ##class(Example.UTL.PathFromSetting).Resolve("../etc", .tPath)
    Do $$$AssertStatusNotOK(tSC, "a traversal above the base is refused")
    Do $$$AssertEquals(tPath, "", "and no path is handed back")
    // The measured fact that makes the containment test real rather than a string trick: once
    // normalised, the escaped path does not text-prefix the base.
    Set tBase = ##class(Example.UTL.PathFromSetting).InstallDir()
    Set tNorm = ##class(%File).NormalizeFilename("../etc", tBase)
    Set tNormBase = ##class(%File).NormalizeDirectory(tBase)
    Do $$$AssertNotEquals($Extract(tNorm, 1, $Length(tNormBase)), tNormBase, "the escaped path (" _ tNorm _ ") does not start with the base (" _ tNormBase _ ")")
    Quit $$$OK
}

/// An empty Setting is its own error, and a missing directory is a different one.
Method TestEmptySettingIsRefused() As %Status
{
    Set tSC = ##class(Example.UTL.PathFromSetting).Resolve("", .tPath)
    Do $$$AssertStatusNotOK(tSC, "an empty Setting is refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "empty", "and the error says the Setting is empty, not that a path is malformed")
    Quit $$$OK
}

/// A resolvable path that does not exist on disk is a filesystem problem, not a configuration one,
/// and the two errors must be distinguishable or the operator fixes the wrong thing.
Method TestMissingDirectoryIsItsOwnError() As %Status
{
    // Resolves cleanly, inside the tree, and cannot exist.
    Do $$$AssertStatusOK(##class(Example.UTL.PathFromSetting).Resolve("zz-no-such-dir-8f3a/", .tPath), "it resolves")
    Set tSC = ##class(Example.UTL.PathFromSetting).ResolveExistingDir("zz-no-such-dir-8f3a/", .tChecked)
    Do $$$AssertStatusNotOK(tSC, "but ResolveExistingDir refuses it")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "no such directory", "and says the directory is missing, not that the Setting is wrong")
    // And the positive half: a directory that DOES exist passes, so the check is not refusing everything.
    Do $$$AssertStatusOK(##class(Example.UTL.PathFromSetting).ResolveExistingDir("mgr/", .tMgr), "POSITIVE CONTROL: a directory that exists passes")
    Do $$$AssertNotEquals(tMgr, "", "and hands back the path")
    Quit $$$OK
}

}
