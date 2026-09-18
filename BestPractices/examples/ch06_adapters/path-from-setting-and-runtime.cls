/// Rule: BestPractices_Interop_IRIS.md §6.18 "Resolving a path from a Setting: the class that compiles and the value that escapes"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed.
/// Severity: High (one half compiles clean and dies at run time; the other half silently leaves the install tree).
///
/// Pattern: turning a production Setting into a filesystem path, which CR-10 prescribes and nothing
/// in the plugin demonstrates.
///
/// CR-10 (`conformance-review/SKILL.md:144`) says: move the path to a Setting, or resolve it at run
/// time with `##class(%Library.File).ManagerDirectory()` / `.TempFilename("csv")` /
/// `$SYSTEM.Util.InstallDirectory()`, and it adds the parenthetical "(note: `InstallDirectory` is on
/// `%SYSTEM.Util`, **not** on `%Library.File`)". That note is correct — measured, `InstallDirectory`
/// is a ClassMethod on `%SYSTEM.Util` and exists on **no other class in the instance** — and it is the
/// only line in the whole plugin that says so.
///
/// WHY THAT NOTE NEEDS AN EXERCISED ARTEFACT AND NOT A PARENTHESIS. The wrong spelling COMPILES:
///
///     ##class(%Library.File).InstallDirectory()     compiles CLEAN
///                                                  -> <METHOD DOES NOT EXIST> at run time
///
/// Measured both halves. So tier 2 — and any CI that only compiles — passes a class that cannot run.
/// This is the case the coverage map flags as "must be exercised, not merely compiled", and it is why
/// the test beside this file calls the wrong form through `$classmethod` and asserts the exception,
/// rather than asserting that a compile succeeded.
///
/// AND THE PART CR-10 DOES NOT MENTION, WHICH IS THE ONE THAT LOSES DATA. Once the path is a Setting,
/// an operator owns its value, and `NormalizeFilename` treats an ABSOLUTE value as authoritative —
/// the base is discarded. Measured against `InstallDirectory()` = `/usr/irissys/`:
///
///     setting            NormalizeFilename(setting, base)   base_setting (naive concat)
///     "mgr/"             /usr/irissys/mgr                   /usr/irissys/mgr/
///     "csp/../mgr"       /usr/irissys/mgr                   /usr/irissys/csp/../mgr
///     "/abs/path"        /abs/path        <-- ESCAPES        /usr/irissys//abs/path  <-- nonsense
///
/// Three things follow. `NormalizeFilename` is the right API — it resolves `..` and trims the
/// duplicate separator that `InstallDirectory`'s trailing `/` otherwise produces. Naive concatenation
/// is wrong in every row, and wrong in a way that only shows up for some values. And **a Setting that
/// an operator can edit can point anywhere on the filesystem**, so a component that resolves a
/// relative path against the install tree must say whether that is allowed, and enforce it — which
/// this class does in `Resolve`, with the check named rather than implied.
Class Example.UTL.PathFromSetting Extends %RegisteredObject
{

/// The install directory, from the one class that has it. Ends with a separator on this platform;
/// do not rely on that — let NormalizeFilename deal with it.
ClassMethod InstallDir() As %String
{
    Quit ##class(%SYSTEM.Util).InstallDirectory()
}

/// Resolve a Setting value against a base directory.
///
/// `pAllowAbsolute` is the decision CR-10 leaves open, made explicit. With it 0 (the default) an
/// absolute Setting is REFUSED rather than quietly honoured: the point of putting the path in a
/// Setting was to keep the component inside a known tree, and `NormalizeFilename` will happily leave
/// that tree if the value says to.
ClassMethod Resolve(pSetting As %String, Output pPath As %String, pBase As %String = "", pAllowAbsolute As %Boolean = 0) As %Status
{
    Set pPath = ""
    If pSetting = "" {
        Quit $$$ERROR($$$GeneralError, "the path Setting is empty: there is nothing to resolve")
    }
    Set tBase = $Select(pBase = "": ..InstallDir(), 1: pBase)

    // NormalizeFilename, not concatenation. See the header's table: concatenation is wrong for a
    // trailing separator, wrong for "..", and wrong for an absolute value.
    Set pPath = ##class(%File).NormalizeFilename(pSetting, tBase)
    If pPath = "" {
        Set tWhy = "NormalizeFilename could not resolve " _ pSetting _ " against " _ tBase
        Quit $$$ERROR($$$GeneralError, tWhy)
    }

    // THE ESCAPE CHECK, covering BOTH ways out of the tree. Measured against base /usr/irissys/:
    //     "/abs/path"       -> /abs/path        absolute: NormalizeFilename discards the base
    //     "../etc"          -> /usr/etc         traversal: resolves above the base
    //     "csp/../mgr"       -> /usr/irissys/mgr  traversal that stays inside -- allowed
    // Comparing the NORMALISED path against the NORMALISED base catches the first two and admits the
    // third. Both sides are normalised because `InstallDirectory()` returns a trailing separator on
    // this platform and that is not guaranteed anywhere -- a prefix test between a normalised path
    // and a raw base is ill-defined. (Measured: `NormalizeDirectory("/usr/irissys/")` is unchanged
    // here, and a traversal does NOT text-prefix the base once normalised -- `../etc` becomes
    // `/usr/etc` -- so the test is a genuine containment check, not a string trick.)
    If 'pAllowAbsolute {
        Set tNormBase = ##class(%File).NormalizeDirectory(tBase)
        If $Extract(pPath, 1, $Length(tNormBase)) '= tNormBase {
            Set tWhy = "the Setting resolves to " _ pPath _ ", which is outside " _ tNormBase _
                " -- pass pAllowAbsolute=1 if that is intended"
            Set pPath = ""
            Quit $$$ERROR($$$GeneralError, tWhy)
        }
    }
    Quit $$$OK
}

/// Resolve and require the directory to exist, for a host that is about to write into it.
///
/// Separate from Resolve because the two failures want different operator actions: a bad Setting is
/// a configuration edit, a missing directory is a filesystem one. A single "path is wrong" error
/// makes the reader guess which.
ClassMethod ResolveExistingDir(pSetting As %String, Output pPath As %String, pBase As %String = "", pAllowAbsolute As %Boolean = 0) As %Status
{
    Set tSC = ..Resolve(pSetting, .pPath, pBase, pAllowAbsolute)
    If $$$ISERR(tSC) { Quit tSC }
    If '##class(%File).DirectoryExists(pPath) {
        Set tWhy = "resolved to " _ pPath _ " but no such directory exists on the IRIS server"
        Set pPath = ""
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Quit $$$OK
}

}
