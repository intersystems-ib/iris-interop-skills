/// Rule: BestPractices_Interop_IRIS.md §6.4 "SQL adapter: use the ParmArray forms for typed parameters"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: High (silent data corruption).
///
/// Pattern: an outbound SQL BO that binds parameters with an EXPLICIT SQL type instead of
/// letting the driver guess, using ExecuteUpdateParmArray / ExecuteQueryParmArray.
///
/// Why this matters more than it looks. ExecuteUpdate(sql, p1, p2, ...) passes values with no
/// type information, so the adapter asks the driver (ODBC SQLDescribeParam) what the columns
/// are. When the driver cannot answer -- and several JDBC drivers cannot -- InterSystems IRIS
/// falls back to SQL type 12, VARCHAR (ESQL section 8.2.2.1, scenario 3). A date, a decimal and
/// a NULL then all go to the database as strings:
///   - an empty ObjectScript value "" binds as an empty VARCHAR rather than a typed NULL, so a
///     nullable DATE or NUMERIC column either rejects the row or silently stores a zero value;
///   - a %Date integer binds as its internal day count (see business-operations, "Date / numeric
///     type marshalling pitfalls");
///   - the hand-rolled workaround for all of this is string-concatenating the SQL, which is both
///     an injection surface and the thing the ParmArray forms exist to remove.
///
/// THE TRAP THAT MAKES PARTIAL TYPING WORSE THAN NONE. The adapter decides whether to use your
/// descriptors by looking at PARAMETER 1 ONLY -- verified in EnsLib.SQL.OutboundAdapter::privPrepare,
/// which tests $D(pParms(1,"SqlType"))||$D(pParms(1,"CType")) -- either subscript counts -- and
/// stated in ESQL section 8.2.2:
/// "InterSystems IRIS checks for the CType or SqlType subscript for the first parameter." If
/// parameter 1 carries no type, every other descriptor you set is IGNORED and the whole statement
/// silently reverts to SQLDescribeParam. Type all of them or none of them.
///
/// Two more rules from ESQL section 8.2.2, both easy to miss:
///   - the TOP level of the array must be the parameter COUNT (set parms = 3), not a value;
///   - "If you execute multiple queries that use the parameter array, kill and recreate the
///     parameter array before each query." A stale subscript from a previous call is bound silently.
///
/// THE MACROS NEED AN INCLUDE, AND THERE ARE TWO SPELLINGS. Both are real; neither is
/// available to an Ens.BusinessOperation by default -- without the Include line you get
/// MPP5610 "Referenced macro not defined", which reads like a typo in the macro name.
///   Include EnsSQLTypes  -> $$$SqlVarchar 12  $$$SqlInteger 4  $$$SqlNumeric 2
///                           $$$SqlDecimal 3   $$$SqlDouble 8   $$$SqlChar 1
///   Include %occODBC     -> the same values under UPPERCASE names: $$$SQLVARCHAR, $$$SQLINTEGER
/// Use EnsSQLTypes in interop code: it is the Ensemble include and the mixed-case spelling is
/// what existing field code uses.
///
/// DATE/TIME HAS FOUR FAMILIES, and picking the wrong one is silent. Values below obtained by
/// COMPILING the macros and printing their expansions on IRIS for Health 2026.1:
///   legacy (SQLEXT.H)  $$$SqlDate 9       $$$SqlTime 10      $$$SqlTimestamp 11
///   ODBC 3.x           $$$SqlTypeDate 91  $$$SqlTypeTime 92  $$$SqlTypeTimestamp 93
///   JDBC aliases       $$$SqlJDate 91     $$$SqlJTime 92     $$$SqlJTimeStamp 93
///   C-type aliases     $$$SqlCDate 9      $$$SqlCTimeStamp 11
/// EnsLib.SQL.OutboundAdapter runs JDBC whenever JDBCDriver is set, so the SqlJ* family is the
/// semantically correct one here -- it says "JDBC date" instead of leaving the reader to work
/// out which numbering applies. This is a legibility preference, NOT a bug report: $$$SqlDate
/// (9) is field-proven, having bound Oracle DATE columns over the Oracle JDBC driver across
/// dozens of production BOs for years. Do not go rewriting working code.
///
/// Two collisions that make a wrong constant look plausible, both verified:
///   $$$SqlDate = $$$SqlDateTime = 9        $$$SqlTime = $$$SqlInterval = 10
/// A misremembered name in either pair still compiles and still binds.
///
/// "SqlType" and "CType" are BOTH honoured. EnsLib.SQL.OutboundAdapter::privPrepare contains,
/// verbatim: Set:""=tSqlType tSqlType=tCType, tCType="" ; for back compatibility we support
/// CType used as SqlType. "SqlType" is the primary name and is what ESQL documents, but a lot
/// of production code uses "CType" -- do not "fix" it, it works.
///
/// Ens.StringContainer is used as the request body only to keep the example self-contained; a
/// real integration defines its own <Pkg>.MSG.<Name>Req class.
Include EnsSQLTypes

Class Example.Adapters.BO.SqlTypedParmArray Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.SQL.OutboundAdapter";

Parameter INVOCATION = "Queue";

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringContainer">
    <Method>InsertCensusRow</Method>
  </MapItem>
</MapItems>
}

/// INSERT with every parameter explicitly typed.
/// pRequest.StringValue carries "id|name|birthdate|weight" only so the example needs no
/// project-specific message class; a real BO reads typed properties off its own request.
Method InsertCensusRow(pRequest As Ens.StringContainer, Output pResponse As Ens.StringContainer) As %Status
{
    #DIM tSC As %Status = $$$OK
    #DIM tRows As %Integer = 0
    #DIM errObj As %Exception.AbstractException
    try {
        Set tId    = $PIECE(pRequest.StringValue, "|", 1)
        Set tName  = $PIECE(pRequest.StringValue, "|", 2)
        Set tBirth = $PIECE(pRequest.StringValue, "|", 3)   // may legitimately be absent
        Set tWeight= $PIECE(pRequest.StringValue, "|", 4)   // may legitimately be absent

        Set tSQL = "INSERT INTO public.census (patient_id, full_name, birth_date, weight_kg) "
                 _ "VALUES (?,?,?,?)"

        // KILL FIRST. A subscript left over from the previous message is bound silently.
        Kill parms

        // Parameter 1 must carry a type, or NONE of the descriptors below are honoured.
        Set parms(1) = tId,     parms(1, "SqlType") = $$$SqlInteger
        Set parms(2) = tName,   parms(2, "SqlType") = $$$SqlVarchar

        // NULL, done properly. The column is typed for the driver either way, so an empty
        // ObjectScript value arrives as a typed NULL rather than as an empty VARCHAR that the
        // database must coerce into a DATE. This is the whole reason to prefer the ParmArray
        // form over concatenating "NULL" into the statement text.
        Set parms(3) = tBirth,  parms(3, "SqlType") = $$$SqlJDate   // JDBC family; see header
        Set parms(4) = tWeight, parms(4, "SqlType") = $$$SqlDouble

        // TOP LEVEL = PARAMETER COUNT. Omit this and the call binds nothing.
        Set parms = 4

        Set tSC = ..Adapter.ExecuteUpdateParmArray(.tRows, tSQL, .parms)
        Quit:$$$ISERR(tSC)

        Set pResponse = ##class(Ens.StringContainer).%New()
        Set pResponse.StringValue = "rows=" _ tRows
    }
    catch (errObj) {
        Set tSC = errObj.AsStatus()
    }
    Quit tSC
}

/// The SELECT half, which is what section 6.4 is named for. Same rules: type parameter 1,
/// set the count, kill before reuse. The result set is EnsLib.SQL.GatewayResultSet -- navigate
/// it with Next() and read columns with Get() (ESQL sections 9.3 and 9.4).
Method CountByName(pName As %String, Output pCount As %Integer) As %Status
{
    #DIM tSC As %Status = $$$OK
    #DIM tRS As EnsLib.SQL.GatewayResultSet
    Set pCount = 0
    Kill parms
    Set parms(1) = pName, parms(1, "SqlType") = $$$SqlVarchar
    Set parms = 1
    Set tSC = ..Adapter.ExecuteQueryParmArray(.tRS, "SELECT COUNT(*) AS n FROM public.census WHERE full_name = ?", .parms)
    Quit:$$$ISERR(tSC) tSC
    If tRS.Next(.tSC) { Set pCount = tRS.Get("n") }
    Do tRS.Close()
    Quit tSC
}

}
