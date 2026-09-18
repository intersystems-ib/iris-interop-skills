/// Rule: BestPractices_Interop_IRIS.md §15.5 "Registering DICOM associations from OnStart — and the verify step that makes it worth doing"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled; the OnStart body executed through its helper.
/// Severity: High (a production that starts green while no association can be negotiated).
///
/// Pattern: a DICOM production that registers its AE pairs in `OnStart`, so the association contexts
/// are part of the deployable rather than a step in somebody's runbook.
///
/// WHY OnStart AND NOT A RUNBOOK STEP. An association context lives in
/// `EnsLib.DICOM.Util.AssociationContext`, which is data in the namespace — not in the production
/// definition, not in source control, and not carried by a deployment package. A production exported,
/// imported and started in a fresh namespace therefore comes up with **no** association contexts and
/// refuses every association, with nothing in the Event Log to say why. Registering from `OnStart`
/// makes the configuration reproducible and idempotent: the helper only creates what is missing.
///
/// THE SIGNATURE, from the dictionary rather than memory:
///     Ens.Production::OnStart(pTimeStarted As %String) As %Status   -- a ClassMethod
/// The base implementation is EMPTY, so `##super()` is a no-op here; it is called anyway, because
/// the day it stops being empty this class should not be the reason a production fails to start.
///
/// AND `OnStart` RETURNING AN ERROR REALLY DOES STOP THE START, which is the point of doing the
/// verification here: a misconfigured association is a reason not to come up, not a warning to
/// discover from a modality's blank screen three days later. If a given deployment would rather start
/// degraded, log the status and return `$$$OK` — but make that the deliberate choice it looks like.
///
/// AE TITLES ARE SETTINGS ON THE ADAPTER, NOT THE HOST -- `LocalAET` and `RemoteAET` are both in
/// `EnsLib.DICOM.Adapter.TCP`'s SETTINGS (`LocalAET,RemoteAET,TraceVerbosity,ARTIM,TXTIM`), while the
/// host contributes only `DuplexTargetConfigName`. Both host classes declare
/// `ADAPTER = EnsLib.DICOM.Adapter.TCP`, and both are DUPLEX -- one TCP association carries request
/// and response -- which is why each names the other with `DuplexTargetConfigName` and not
/// `TargetConfigNames`.
///
/// A DICOM SERVICE AND OPERATION ARE BOTH DUPLEX, which is why each names the other with
/// `DuplexTargetConfigName` instead of `TargetConfigNames`: one TCP association carries both the
/// request and the response, so the same item handles both directions.
Class Example.Productions.DicomOnStart Extends Ens.Production
{

/// The pairs `OnStart` registers, each `$ListBuild(calling, called)` in WIRE ORDER.
///
/// ONE list, in one place, and that is the whole point of the method existing rather than the titles
/// being literals inside `OnStart`. The AE titles are unavoidably written twice — here and as adapter
/// settings in the XData below — and a `RemoteAET` changed in the production but not here leaves a
/// production that starts green, registers the OLD pair, and refuses every association. Nothing
/// detects that at compile time and nothing logs it at run time, so the test beside this file reads
/// this list and the XData's AE titles and requires them to agree.
///
/// Inbound: the modality initiates, IRIS answers. Outbound: IRIS initiates, the archive answers. The
/// same two titles in the other order are a DIFFERENT context, not the same one read backwards.
ClassMethod AssociationPairs() As %List
{
    Quit $ListBuild($ListBuild("DEMO_MODALITY", "DEMO_IRIS"),
                    $ListBuild("DEMO_IRIS", "DEMO_ARCHIVE"))
}

/// Runs once per production start, before any item is started.
ClassMethod OnStart(pTimeStarted As %String) As %Status
{
    Set tSC = ##super(pTimeStarted)
    If $$$ISERR(tSC) { Quit tSC }

    Set tPairs = ..AssociationPairs(), tReport = ""
    For i = 1:1:$ListLength(tPairs) {
        Set tPair = $List(tPairs, i)
        Set tCalling = $List(tPair, 1), tCalled = $List(tPair, 2)
        Set tSC = ##class(Example.UTL.DicomAssociations).Register(tCalling, tCalled, .tCount)
        // Returning the error STOPS THE START, which is the right default: a misconfigured
        // association is a reason not to come up, not something to learn from a modality's blank
        // screen three days later. A deployment that would rather start degraded should log this and
        // return $$$OK -- deliberately, and visibly.
        If $$$ISERR(tSC) { Quit }
        Set tReport = tReport _ $Select(tReport="":"", 1:", ") _ tCalling _ "->" _ tCalled _ "=" _ tCount _ " contexts"
    }
    If $$$ISERR(tSC) { Quit tSC }

    // The COUNTS go in the log, not the word "OK". A line reading "237 contexts" is the difference
    // between a start you can audit and one you have to reproduce.
    $$$LOGINFO("DICOM associations verified: " _ tReport)
    Quit $$$OK
}

XData ProductionDefinition
{
<Production Name="Example.Productions.DicomOnStart" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>DICOM over TCP, with the association contexts registered and verified from OnStart.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.DicomIn" Category="Example" ClassName="EnsLib.DICOM.Service.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPPort">104</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_MODALITY</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BO.DicomOut</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.DicomOut" Category="Example" ClassName="EnsLib.DICOM.Operation.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="IPPort">11112</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_ARCHIVE</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BS.DicomIn</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
