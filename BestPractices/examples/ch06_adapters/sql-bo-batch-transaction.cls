/// Rule: BestPractices_Interop_IRIS.md §6.13 "SQL batch in one transaction — autocommit IS the transaction, and the restore is the hard part"
/// Validity: Verified against IRIS for Health 2026.1 — every method name and origin read from %Dictionary.CompiledMethod. Compiles with no DSN configured.
/// Severity: High (a leaked open transaction is inherited by the NEXT message).
///
/// Pattern: several rows per message, all-or-nothing. One row per message needs none of this —
/// let the driver's autocommit do the work and let a failure suspend the message.
///
/// TURNING AUTOCOMMIT OFF *IS* THE TRANSACTION START. There is no `StartTransaction()`; an earlier
/// revision of these skills prescribed one and it fails at runtime with `<METHOD DOES NOT EXIST>`.
/// Measured, with origins, because the origin is what tells you how portable each call is:
///     SetAutoCommit(pAutoCommit=1)   -> %Status   origin EnsLib.SQL.Common    portable
///     Commit()                       -> %Status   origin EnsLib.SQL.Common    portable
///     Rollback()                     -> %Status   origin EnsLib.SQL.Common    portable
///     Transact(type)                 -> %Status   origin EnsLib.SQL.CommonJ   JDBC only
/// `Transact` is public and real, but it comes from the JDBC common class, so the three above are
/// the pair of hands that work on an ODBC connection too. (What `type` accepts is not asserted here
/// because it was not measured.)
///
/// THE LEAK IS THE WHOLE DIFFICULTY, AND IT IS SILENT. `SetAutoCommit(1)` at the end of the happy
/// path only runs if nothing jumped out first. A `Quit` inside the `Catch` — the natural thing to
/// write — leaves autocommit OFF on a connection that is `StayConnected`, so the transaction stays
/// open and THE NEXT MESSAGE inherits it. That message's inserts join a transaction it knows nothing
/// about, and whether they land depends on what happens to a transaction opened for someone else.
/// Nothing reports this. The message that caused it completed.
///
/// Hence the three rules this file exists to show:
///   1. Restore in ONE place that every path reaches — ObjectScript has no `finally`, so that place
///      is after the Try/Catch, not inside either arm.
///   2. Guard the restore with a flag set ONLY after `SetAutoCommit(0)` returned OK. Restoring a
///      transaction you never started is its own bug, and on a cold adapter `SetAutoCommit` can fail
///      while connecting.
///   3. Do NOT overwrite your `%Status` with the rollback's. The rollback's status answers "did the
///      undo work", which is not the answer the caller needs; if you assign it over yours, a
///      successful rollback of a failed batch reports success.
///
/// `SetAutoCommit` connects first if the adapter is cold, so calling it in OnMessage is safe.
Include EnsSQLTypes

Class Example.Adapters.BO.SqlBatchTransaction Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.SQL.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Insert every row of the request, or none of them.
Method InsertBatch(pRequest As Example.MSG.OrderEvent, Output pResponse As Ens.StringContainer) As %Status
{
    Set tSC = $$$OK
    Set tInTransaction = 0          // rule 2: set only after SetAutoCommit(0) actually succeeded
    Set tRows = 0

    Try {
        Set tSC = ..Adapter.SetAutoCommit(0)
        Quit:$$$ISERR(tSC)
        Set tInTransaction = 1

        Set tSQL = "INSERT INTO orders (order_id, patient_id, event_type) VALUES (?,?,?)"

        // One logical batch. In real code this loops the request's rows; two are enough to show
        // that the second failing must undo the first.
        For i = 1:1:2 {
            Kill parms                                        // ALWAYS, before every call
            Set parms(1) = pRequest.OrderId _ "-" _ i,  parms(1, "SqlType") = $$$SqlVarchar
            Set parms(2) = pRequest.PatientId,          parms(2, "SqlType") = $$$SqlVarchar
            Set parms(3) = pRequest.EventType,          parms(3, "SqlType") = $$$SqlVarchar
            Set parms = 3                                     // TOP LEVEL = PARAMETER COUNT

            Set tSC = ..Adapter.ExecuteUpdateParmArray(.tAffected, tSQL, .parms)
            Quit:$$$ISERR(tSC)
            Set tRows = tRows + tAffected
        }
        Quit:$$$ISERR(tSC)

        Set tSC = ..Adapter.Commit()
        Quit:$$$ISERR(tSC)
        Set tInTransaction = 0                                // committed: nothing left to undo

        Set pResponse = ##class(Ens.StringContainer).%New(tRows _ " rows committed")
    } Catch ex {
        Set tSC = ex.AsStatus()
    }

    // RULE 1: one restore point that every path reaches -- the happy path, every Quit above, and
    // the Catch. ObjectScript has no `finally`, so this is it.
    If tInTransaction {
        // RULE 3: keep the rollback's status OUT of tSC. It answers "did the undo work", not
        // "did the batch work", and assigning it over tSC makes a clean rollback look like success.
        Set tRollbackSC = ..Adapter.Rollback()
        If $$$ISERR(tRollbackSC) {
            // Worth its own log line: the batch failed AND the undo failed, which is a different
            // and worse situation than either alone.
            $$$LOGERROR("rollback failed after a failed batch: " _ $system.Status.GetErrorText(tRollbackSC))
        }
        // And restore autocommit, or the NEXT message inherits an open transaction.
        Do ..Adapter.SetAutoCommit(1)
    }

    Quit tSC
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Example.MSG.OrderEvent">
    <Method>InsertBatch</Method>
  </MapItem>
</MapItems>
}

}
