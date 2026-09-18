/// Rule: BestPractices_Interop_IRIS.md §11.13 "Asserting Server Certificate Validation — VerifyPeer, and the config that looks configured"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled AND executed against the live Security.SSLConfigs of a running instance.
/// Severity: High (with validation off the handshake succeeds, everything is green, and the peer is unauthenticated for ever).
///
/// Pattern: an executable assertion for step 1 of §11.7 — "Server Certificate Validation = Require".
/// It is the only step in that section with no artefact, and the only one whose failure is invisible.
///
/// THE ROW THAT ASKED FOR THIS WAS DECLARED BLOCKED, AND THE BLOCK WAS WRONG. An earlier premise pass
/// recorded that `Security.SSLConfigs` "is not visible from the gate namespace" — which is true as far
/// as it goes: the class is absent from an application namespace's dictionary, and
/// `SELECT … FROM Security.SSLConfigs` gives `SQLCODE -30`. A late-bound call from there raises
/// `<CLASS DOES NOT EXIST>`. What that pass did not try is the namespace hop, and it works:
///
///     New $Namespace  Set $Namespace = "%SYS"     ->  the class exists, the table reads
///
/// `New $Namespace` is the load-bearing half. Measured both ways: WITH it, the caller's namespace is
/// restored on return (`before=[FHIRTEST] after=[FHIRTEST]`); WITHOUT it, the namespace LEAKS
/// (`afterNoNew=[%SYS]`) and every later line in that job reads and writes the wrong namespace's
/// globals. A utility that leaks `%SYS` into a business host is worse than no utility.
///
/// WHAT THE PLATFORM ALREADY ENFORCES, so it need not be checked. Measured:
///     Create(VerifyPeer=1, no CAFile)            #986 CA File is required when Peer Verification …
///     Create(VerifyPeer=1, CAFile that is absent) #5012 File '…' does not exist
///     Create(VerifyPeer=1, CAFile with junk)      #743 CA certificate file … is not valid
/// So you cannot set Require without a real, parseable CA chain on disk. That is good, and it also
/// explains the state this class looks for: **0 is the path of least resistance.** A config gets
/// created with `VerifyPeer=0` because that is the only way to create it before the chain exists, and
/// nobody comes back. Measured on a clean IRIS for Health 2026.1: BOTH shipped configs —
/// `BFC_SSL` and `ISC.FeatureTracker.SSL.Config` — are `Enabled=1` with `VerifyPeer=0`.
///
/// AND THE STATE WORTH THE WHOLE CLASS: `CAFile` SET, `VerifyPeer` 0. Nothing stops a config that has
/// a valid CA chain from being switched back to no validation — the chain stays on disk, the config
/// page still shows a CA file, and validation is off. An audit that asks "is a CA file configured?"
/// passes it. `Classify` calls that MISLEADING and reports it separately, because it is the one a
/// reviewer is most likely to wave through.
///
/// NOTHING IN THE CLASS TELLS YOU WHAT THE NUMBERS MEAN. `VerifyPeer` is a plain `%Library.Integer`
/// with `MINVAL 0`, `MAXVAL 3` and an **empty VALUELIST**; `Security.Datatype.SSLType` and
/// `Security.Datatype.BooleanYN` have empty VALUELISTs too. So every one of these settings reads back
/// as a bare number and the meaning lives only in the Portal's labels. That is why this class spells
/// the threshold out in one named constant rather than scattering `= 0` comparisons.
///
/// READING THE TABLE NEEDS PRIVILEGE: `Security.SSLConfigs` declares
/// `RESOURCEREQUIRED = %Admin_Secure`. `Audit` returns the error rather than an empty report, because
/// an audit that reports "no findings" when it was not allowed to look is the worst possible outcome.
Class Example.UTL.SslConfigAudit Extends %RegisteredObject
{

/// The lowest `VerifyPeer` that means "validate the peer". Named once: the datatype carries no
/// VALUELIST, so this number is the only place the intent is written down.
Parameter REQUIRELEVEL As INTEGER = 1;

/// The verdict for one config's settings, with no I/O and no privilege — so it can be tested
/// exhaustively, which the live table cannot be (creating a passing config needs a real CA
/// certificate on disk, see the header).
///
/// Returns one of: OK, MISLEADING, NO-VALIDATION, DISABLED.
ClassMethod Classify(pVerifyPeer As %Integer, pCAFile As %String, pEnabled As %Boolean, Output pWhy As %String) As %String
{
    Set pWhy = ""
    If 'pEnabled {
        Set pWhy = "the configuration is disabled, so it validates nothing and is used by nothing"
        Quit "DISABLED"
    }
    If +pVerifyPeer >= ..#REQUIRELEVEL {
        Set pWhy = "VerifyPeer=" _ +pVerifyPeer _ " is at or above the require level"
        Quit "OK"
    }
    If pCAFile '= "" {
        // The one a reviewer waves through: a CA chain is present, so the config LOOKS configured for
        // validation, and VerifyPeer=0 means it does none.
        Set pWhy = "VerifyPeer=0 while CAFile is set (" _ pCAFile _ "): looks configured for validation and performs none"
        Quit "MISLEADING"
    }
    Set pWhy = "VerifyPeer=0 and no CAFile: the peer is never authenticated"
    Quit "NO-VALIDATION"
}

/// Walk every SSL configuration on the instance and report the ones that do not validate.
///
/// `pReport` comes back as: pReport = number of findings, pReport("total") = configurations examined,
/// pReport(n) = $ListBuild(name, verdict, why).
ClassMethod Audit(Output pReport) As %Status
{
    Kill pReport
    Set pReport = 0, pReport("total") = 0
    Set tSC = $$$OK
    Try {
        // New $Namespace FIRST. Without it this method changes its caller's namespace permanently --
        // measured. With it, the change is undone however this method exits, including on an error.
        New $Namespace
        Set $Namespace = "%SYS"
        Set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, VerifyPeer, CAFile, Enabled, Type FROM Security.SSLConfigs ORDER BY Name")
        // A result set that failed is not a result set with no rows -- and here the difference is
        // "every config validates" versus "I was not allowed to look".
        If tRs.%SQLCODE < 0 {
            Set tWhy = "could not read Security.SSLConfigs: SQLCODE " _ tRs.%SQLCODE _ " " _ tRs.%Message
            Quit
        }
        While tRs.%Next() {
            Set pReport("total") = pReport("total") + 1
            Set tVerdict = ..Classify(tRs.%Get("VerifyPeer"), tRs.%Get("CAFile"), tRs.%Get("Enabled"), .tWhy)
            Continue:tVerdict="OK"
            Continue:tVerdict="DISABLED"
            Set pReport = pReport + 1
            Set pReport(pReport) = $ListBuild(tRs.%Get("Name"), tVerdict, tWhy)
        }
    } Catch tEx {
        Set tSC = tEx.AsStatus()
    }
    If $Data(tWhy), pReport("total") = 0, $$$ISOK(tSC) {
        Quit $$$ERROR($$$GeneralError, tWhy)
    }
    Quit tSC
}

/// The audit as one readable string, for a deploy-time check or a scheduled task.
ClassMethod Report() As %String [ SqlProc ]
{
    Set tSC = ..Audit(.tReport)
    If $$$ISERR(tSC) { Quit "AUDIT FAILED: " _ $System.Status.GetErrorText(tSC) }
    If tReport = 0 {
        Quit "OK: " _ tReport("total") _ " SSL configuration(s) examined, all validate the peer"
    }
    Set tOut = tReport _ " of " _ tReport("total") _ " SSL configuration(s) do NOT validate the peer:"
    For i = 1:1:tReport {
        Set tRow = tReport(i)
        Set tOut = tOut _ $Char(10) _ "  " _ $List(tRow, 2) _ "  " _ $List(tRow, 1) _ " -- " _ $List(tRow, 3)
    }
    Quit tOut
}

}
