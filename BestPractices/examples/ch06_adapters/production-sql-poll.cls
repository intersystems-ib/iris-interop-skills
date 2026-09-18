/// Rule: BestPractices_Interop_IRIS.md §6.9 "SQL inbound — poll a table with GenericService, and the JGService precondition"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (a missing JGService terminates the host at startup).
///
/// Pattern: polling an external table as an inbound. EnsLib.SQL.Service.GenericService is
/// CONFIGURED, not subclassed — the query, the key field and the dispatch are all settings.
///
/// JGService IS MANDATORY FOR ANY jdbc: DSN, and its absence is not a connection failure —
/// the host TERMINATES AT STARTUP. It must name an EnsLib.JavaGateway.Service item in THIS
/// production, character for character (ESQL §2.1, §3.1). That item is required and is NOT
/// deprecated; its %gatewayName is what points it at the External Language Server. Without it
/// you get
///   <INVALID OREF> 192 initAdapterJG+2^EnsLib.JavaGateway.Common.1
/// which names neither the gateway nor the item nor JGService, so it reads as a broken gateway
/// and sends you rebuilding one that was never broken.
///
/// KeyFieldName is what makes the poll incremental. Without it the same rows are re-read on
/// every CallInterval and re-sent forever — a duplicate-message source that looks like a working
/// integration. The adapter remembers the high-water mark per business host.
///
/// DeleteQuery / Query: prefer a WHERE clause on an indexed watermark column over deleting rows
/// you have consumed. Deleting is irreversible if the downstream fails, and the message is then
/// the only copy.
Class Example.Productions.SqlPoll Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Example.Productions.SqlPoll" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Poll an external table over JDBC and route each row.</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <!-- MANDATORY for a jdbc: DSN. JGService below must match this item name exactly. -->
  <Item Name="Util.JdbcGateway" Category="Example" ClassName="EnsLib.JavaGateway.Service"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="%gatewayName">%JDBC Server</Setting>
  </Item>

  <Item Name="BS.Orders" Category="Example" ClassName="EnsLib.SQL.Service.GenericService"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="TargetConfigNames">Router.Orders</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="DSN">jdbc:postgresql://db.example.org:5432/orders</Setting>
    <Setting Target="Adapter" Name="JDBCDriver">org.postgresql.Driver</Setting>
    <Setting Target="Adapter" Name="JDBCClasspath">/opt/jdbc/postgresql.jar</Setting>
    <Setting Target="Adapter" Name="Credentials">OrdersAppCredentials</Setting>
    <Setting Target="Adapter" Name="JGService">Util.JdbcGateway</Setting>
    <Setting Target="Adapter" Name="Query">SELECT id, patient_id, placed_at FROM public.orders WHERE id > ? ORDER BY id</Setting>
    <Setting Target="Adapter" Name="KeyFieldName">id</Setting>
    <Setting Target="Adapter" Name="CallInterval">30</Setting>
  </Item>

  <Item Name="Router.Orders" Category="Example" ClassName="EnsLib.MsgRouter.RoutingEngine"
        PoolSize="1" Enabled="true" Foreground="false" InactivityTimeout="0" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Example.RUL.OrderRouting</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <!-- NO Ens.Alert ITEM HERE, DELIBERATELY. This production carried one until v1.33.0, with
       AlertOnError=0 and no BusinessRuleName — and an Ens.Alert router with no rule is WORSE than
       no Ens.Alert item at all: the framework routes every Ens.AlertRequest to it and the rule that
       would forward them does not exist, so the alerts are captured and dropped in silence. Found
       by Example.UTL.PreflightValidator on its first real run (§1.15).
       The alert circuit is a production of its own — see ch07_alerting/production-alert-circuit.cls
       (§7.1), which wires Ens.Alert to a rule and a sink. The AlertOnError=1 settings on the items
       above are what FEED that circuit; they do not need a local router to be correct. -->

</Production>
}

}
