/// Rule: BestPractices_Interop_IRIS.md §1.14 "Drift between disk and namespace is silent — the check, and the two ways it lies to you"
/// Validity: Verified against IRIS for Health 2026.1 — compiles; the #1012 trap below reproduced exactly.
/// Severity: High (this is the end-of-every-build check, so a parse error in it is the worst place for one).
///
/// Pattern: compare the classes in a namespace against the class files on disk, both directions.
/// Nothing in the toolchain does this, so the two diverge with no symptom at all.
///
/// WHY THIS IS A CLASS AND NOT A SNIPPET. It lived in `production-lifecycle` as two bare
/// `ClassMethod`s — no host class, so no tier could compile it. That matters more here than
/// anywhere: it is the one piece of code the skill tells you to run at the end of every build, and
/// its earlier form DID NOT COMPILE. Reproduced on 2026.1:
///     Continue:$Extract(k, 1, n) '= (pPkg _ ".")   ->  #1012: Expected EOL or spaces : 'n) '='
///     Continue:$Extract(k,1,n)'=(pPkg_".")         ->  compiles
/// **An ObjectScript postconditional ends at the first space.** The argument must be unbroken, so
/// the readable spacing you would write anywhere else is a parse error here. Nothing about the
/// message points at spacing.
///
/// THE TWO WAYS THIS REPORT LIES, and both look like answers:
///
///   1. `%File` SEES THE IRIS HOST'S FILESYSTEM, NOT YOURS. With IRIS in a container, `pSrcDir` is
///      a path inside the container. A source tree that is not mounted there reads as entirely
///      missing and the report says every class is `ONLY IN IRIS` — alarming, and wrong. Check the
///      path resolves on the IRIS side before believing a large `ONLY IN IRIS` list.
///   2. A WRONG PACKAGE PREFIX REPORTS `in sync` HAVING COMPARED NOTHING. The namespace side is
///      `Name %STARTSWITH pPkg _ "."`, so a typo'd or over-qualified prefix matches zero classes,
///      the disk side finds nothing under it either, and the function returns the cheerful `in
///      sync`. An empty comparison and a clean comparison produce the same string. If you have not
///      seen this report name at least one class you know exists, you have not tested it.
///
/// AND THE SQL IS A STRING, SO THE COMPILER NEVER SEES IT. `%ExecDirect` takes the statement as
/// text: a wrong table name, a wrong column, a typo'd `%STARTSWITH` all compile perfectly and fail
/// at runtime. That is why the table here is `%Dictionary.ClassDefinition` — the documented
/// dictionary class — and never `^oddCOM`/`^oddDEF`, whose layout is not a contract and which the
/// conformance gate denies reading.
Class Example.UTL.DriftReport Extends %RegisteredObject
{

/// Compare namespace against disk. Invoke headlessly via:
///     SELECT Example_UTL.DriftReport_DriftReport('Example', '/opt/irisapp/src')
ClassMethod DriftReport(pPkg As %String, pSrcDir As %String) As %String [ SqlProc ]
{
    Set onlyIris = "", onlyDisk = ""

    // Namespace side: %Dictionary SQL, never ^oddCOM/^oddDEF.
    Set sql = "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH ?"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pPkg _ ".")
    While rs.%Next() {
        Set k = rs.%Get("Name")
        Set inIris(k) = ""
        If '##class(%File).Exists(pSrcDir _ "/" _ $Replace(k, ".", "/") _ ".cls") {
            Set onlyIris = onlyIris _ $Select(onlyIris="":"", 1:", ") _ k
        }
    }

    // Disk side: walk the tree, so a file that was never compiled is visible too.
    Do ..DriftDisk(pSrcDir, pSrcDir, .onDisk)
    Set k = ""
    For {
        Set k = $Order(onDisk(k))  Quit:k=""
        If '$Data(inIris(k)) {
            Set onlyDisk = onlyDisk _ $Select(onlyDisk="":"", 1:", ") _ k
        }
    }

    Set out = ""
    If onlyIris '= "" { Set out = "ONLY IN IRIS: " _ onlyIris }
    If onlyDisk '= "" { Set out = out _ $Select(out="":"", 1:" | ") _ "ONLY ON DISK: " _ onlyDisk }

    // "in sync" is also what an EMPTY comparison returns -- see note 2 in the header.
    Quit $Select(out="":"in sync", 1:out)
}

/// Recursive directory walk. `Continue` here is unconditional and inside a block, which is legal;
/// it is the POSTCONDITIONAL form that must carry no spaces.
ClassMethod DriftDisk(pRoot As %String, pDir As %String, ByRef pOut) [ Private ]
{
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(pDir, "*")
    While rs.Next() {
        Set nm = rs.Get("Name")
        If rs.Get("Type") = "D" { Do ..DriftDisk(pRoot, nm, .pOut)  Continue }
        If $ZConvert($Piece(nm, ".", *), "L") '= "cls" Continue
        Set rel = $Extract(nm, $Length(pRoot) + 2, *)
        Set pOut($Replace($Extract(rel, 1, *-4), "/", ".")) = ""
    }
}

/// The unbroken postconditional, kept as a named method so the compiler checks the form this
/// file exists to document. Spaces anywhere in the condition make it #1012.
ClassMethod InPackage(pName As %String, pPkg As %String) As %Boolean
{
    Set n = $Length(pPkg) + 1
    Set ok = 1
    Set k = pName
    For i = 1:1:1 {
        Continue:$Extract(k,1,n)'=(pPkg_".")
        Set ok = 1
    }
    Quit ok
}

}
