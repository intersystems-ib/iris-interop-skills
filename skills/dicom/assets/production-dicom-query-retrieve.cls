/// Rule: BestPractices_Interop_IRIS.md §15.6 "DICOM query/retrieve is a quartet, not a duplex pair — and the vendored snapshot's own reply leg dangles"
/// Validity: Verified against IRIS for Health Community 2026.1 — compiled; the item graph read from the vendored snapshot.
/// Severity: High (wired as one pair, C-FIND works and the retrieved images land nowhere).
///
/// Pattern: query/retrieve wired as what it actually is. `production-dicom-onstart-associations.cls`
/// (§15.5) shows the duplex PAIR — one service, one operation, each naming the other. That shape is right
/// for store-and-forward and wrong here.
///
/// WHY QUERY/RETRIEVE IS NOT A PAIR. C-FIND and C-MOVE are separate conversations, and the images a
/// C-MOVE asks for do not come back on the C-MOVE association at all — the peer opens a NEW association
/// and does C-STORE to you. So the retrieve leg has an inbound service the query leg knows nothing about.
/// Read from the vendored workshop production's 17 items, the legs are:
///
///     QueryService          -> DICOM Query Process        C-FIND in, matched, answered
///     MoveService           -> DICOM Move Process         C-MOVE in, accepted
///     DICOM Store In        -> DICOM Store Process        the images ARRIVING, a third leg
///     DICOM TCP Out         (duplex: DICOM Query Process) the outbound association
///
/// Four legs, three of them duplex pairs and each pair naming only its own partner. A developer who wires
/// "query/retrieve" as one service/operation pair gets a working C-FIND and a C-MOVE whose instances have
/// no inbound item to land on: the peer's C-STORE association is refused, and the only symptom is that
/// nothing arrives.
///
/// AND THE VENDORED SNAPSHOT HAS A DANGLING LEG, which is what made this worth a sample. Measured on its
/// 17 items and five `DuplexTargetConfigName` values: four resolve, and
///
///     item `DICOM Store DCM TCP Out`  DuplexTargetConfigName="DICOM STOWRS Process"   NO SUCH ITEM
///
/// The item that exists is **`DICOM StowRs Handler`**. So the dangling value is a rename near-miss in BOTH
/// the casing and the final word — even a case-insensitive check would not match it. A `<Setting>` value
/// is a string, so tier 2b compiles that snapshot clean; the defect is now RECORDED in
/// `scripts/external_baseline.json` under `known_dangling`, and tier 2b fails on a NEW one.
///
/// EVERY DUPLEX NAME BELOW RESOLVES, and the oracle checks both directions. C8 checks one direction for
/// bank artefacts; a pair where A names B but B names something else passes C8 and still breaks.
Class Example.Productions.DicomQueryRetrieve Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.DicomQueryRetrieve" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>DICOM query/retrieve: the four legs, each duplex pair naming only its own partner.</Description>
  <ActorPoolSize>3</ActorPoolSize>

  <!-- LEG 1, C-FIND in. Its duplex partner is the query process, never the outbound operation. -->
  <Item Name="BS.QueryFind" Category="Example" ClassName="EnsLib.DICOM.Service.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPPort">104</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_MODALITY</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BP.QueryLeg</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BP.QueryLeg" Category="Example" ClassName="Example.BP.DicomLeg"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- LEG 2, C-MOVE in. A SEPARATE service on a separate port: the modality issues C-MOVE as its own
       conversation, and folding it into leg 1 loses the association it must be answered on. -->
  <Item Name="BS.MoveRequest" Category="Example" ClassName="EnsLib.DICOM.Service.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPPort">1104</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_MODALITY</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BP.MoveLeg</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BP.MoveLeg" Category="Example" ClassName="Example.BP.DicomLeg"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- LEG 3, THE ONE THAT GETS FORGOTTEN. The retrieved instances arrive on a NEW association the peer
       opens back to us, as C-STORE. Omit this item and the C-MOVE is accepted and nothing ever lands. -->
  <Item Name="BS.StoreIn" Category="Example" ClassName="EnsLib.DICOM.Service.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPPort">2104</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_ARCHIVE</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BP.StoreLeg</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BP.StoreLeg" Category="Example" ClassName="Example.BP.DicomLeg"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- LEG 4, the outbound association. Its duplex partner is the QUERY process, matching the vendored
       snapshot: the process that opened the conversation is the one that must see the reply. -->
  <Item Name="BO.DicomOut" Category="Example" ClassName="EnsLib.DICOM.Operation.TCP"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="IPPort">11112</Setting>
    <Setting Target="Adapter" Name="LocalAET">DEMO_IRIS</Setting>
    <Setting Target="Adapter" Name="RemoteAET">DEMO_ARCHIVE</Setting>
    <Setting Target="Host" Name="DuplexTargetConfigName">BP.QueryLeg</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
