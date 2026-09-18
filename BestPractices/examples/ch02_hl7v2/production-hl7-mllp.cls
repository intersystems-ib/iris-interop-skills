/// Rule: BestPractices_Interop_IRIS.md §1.19 "MLLP: which timeout is a Host setting and which is an Adapter one"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, and every setting's target measured.
/// Severity: High (three of the four defaults it overrides fail silently or fail for ever).
///
/// Pattern: the MLLP (HL7-over-TCP) production. The bank had file-based HL7 intake (§2.10) and no
/// TCP one, so the Host/Adapter split that MLLP makes unavoidable had no compiled example.
///
/// THE SPLIT, measured per setting rather than assumed — `$parameter(host, "ADAPTER")` for the
/// adapter, then which class actually declares each property:
///
///   EnsLib.HL7.Service.TCPService      adapter EnsLib.HL7.Adapter.TCPInboundAdapter
///       Port             Adapter
///       LocalInterface   Adapter
///       AckMode          Host
///
///   EnsLib.HL7.Operation.TCPOperation  adapter EnsLib.HL7.Adapter.TCPOutboundAdapter
///       Port             Adapter
///       ResponseTimeout  Adapter
///       FailureTimeout   Host
///       ReplyCodeActions Host
///
/// The operation is the instructive half: it carries TWO timeouts and they live on OPPOSITE sides.
/// `ResponseTimeout` is how long the adapter waits for the ACK on the wire; `FailureTimeout` is how
/// long the host keeps retrying before giving up. Putting either on the wrong `Target` is silent —
/// §5.x's destination assert measured that a setting on the wrong target is simply not applied, with
/// no error and no log line — so the value you set has no effect and the default stays in force.
///
/// THREE DEFAULTS THIS FILE OVERRIDES, and why each matters:
///
///   FailureTimeout   default **-1**, measured (origin EnsLib.HL7.Operation.Standard). -1 means
///                    RETRY FOR EVER. A downstream that is down does not produce a failure; it
///                    produces a queue that grows until someone notices. §1.8 covers this; the only
///                    other `FailureTimeout` in the bank is the alert circuit's (§7.1), so before
///                    this file the MLLP case — the one where an unreachable TCP peer is routine —
///                    had none. Set finite.
///   ReplyCodeActions default **""**, measured (origin EnsLib.HL7.Operation.ReplyStandard). With it
///                    empty, an application NACK (AE/AR in MSA-1) leaves the message SUSPENDED rather
///                    than errored — §1.7's "looks like an error but isn't". The literal below says
///                    what to do with each reply code instead of leaving it to the default.
///   ResponseTimeout  default 30 on the adapter. Stated explicitly here because it is the one that
///                    must be SHORTER than the host's FailureTimeout — see §1.9's precedence rule.
///                    Left implicit, a reader cannot see the relationship the two values encode.
///
/// `AckMode` is on the HOST and is left at its measured default `"Immed"`: the service ACKs on
/// receipt rather than after the message has been processed. That is the right default for a
/// throughput-oriented feed and the wrong one if the sender treats the ACK as proof of persistence —
/// stated rather than silently inherited, because it is a contract with the sender.
///
/// WHAT IS NOT PROVEN HERE. This compiles and its settings are asserted by the companion test; it is
/// NOT driven. Driving MLLP needs a TCP peer on both ends, which no tier in this repo can stand up.
/// So the configuration is gated and the wire behaviour is not.
Class Example.Productions.Hl7Mllp Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.Hl7Mllp" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 over MLLP: the Host/Adapter split, with three defaults overridden deliberately.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS.MllpIn" Category="Example" ClassName="EnsLib.HL7.Service.TCPService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <!-- Port and LocalInterface are ADAPTER settings: the listener is the adapter's job. -->
    <Setting Target="Adapter" Name="Port">7001</Setting>
    <Setting Target="Adapter" Name="LocalInterface"></Setting>
    <!-- AckMode is a HOST setting. Immed means "ACK on receipt", not "ACK once processed". -->
    <Setting Target="Host" Name="AckMode">Immed</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Router.Mllp</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="Router.Mllp" Category="Example" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.MllpRouting</Setting>
    <!-- A DIFFERENT item from the rule's send target, per C11. -->
    <Setting Target="Host" Name="BadMessageHandler">BO.MllpBad</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.MllpOut" Category="Example" ClassName="EnsLib.HL7.Operation.TCPOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <!-- ADAPTER: where to connect, and how long to wait for the ACK on the wire. -->
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7002</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">30</Setting>
    <!-- HOST: how long to keep retrying, and what to do with each HL7 reply code.
         FailureTimeout defaults to -1, which retries for ever. 120 is finite and longer than
         ResponseTimeout, per the precedence rule. -->
    <Setting Target="Host" Name="FailureTimeout">120</Setting>
    <!-- ReplyCodeActions defaults to "". Empty leaves an application NACK as a SUSPENDED message.
         E=error the message, AE/AR=retry then error, everything else=error. Spelled out so the
         behaviour is in the production rather than in the base class's default. -->
    <Setting Target="Host" Name="ReplyCodeActions">:?R=RF,:?E=F,:~=S,:?A=C,:*=S,:I?=W,:T?=C</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="BO.MllpBad" Category="Example" ClassName="EnsLib.HL7.Operation.FileOperation"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/data/hl7/mllp-bad/</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
