/// Rule: BestPractices_Interop_IRIS.md §4.11 "The FHIR payload is a stream id, and every way of touching it fails quietly"
/// Validity: Verified against IRIS for Health Community 2026.1 in a Foundation namespace — compiled AND executed.
/// Severity: High (three of the four failure paths here return $$$OK while losing or sharing the payload).
///
/// Pattern: a DTL whose source and target are both `HS.FHIRServer.Interop.Request`. This is the
/// artefact behind §4.10's closing clause — "a DTL over a FHIR payload works on the Request's
/// QuickStreamId, not on properties" — which is true, and which stops short of everything that
/// makes acting on it hard.
///
/// WHY THERE IS NO <assign> FOR THE BODY. The message's entire public surface is four properties,
/// read from the dictionary rather than remembered:
///
///     QuickStreamId    %String                              -- the payload, by reference
///     Request          HS.FHIRServer.API.Data.Request        -- serial: RequestMethod, RequestPath,
///                                                              Type, Interaction, Id, QueryString, ...
///     HSCoreVersion    %String                              -- inherited from HS.Util.EnsRequest
///     HSMinVersion     %String                              -- inherited from HS.Util.EnsRequest
///
/// So `<assign>` reaches the metadata and nothing else. There is no property for a resource, a
/// Bundle, or a body, and there is no spelling that produces one.
///
/// THE TRAP THIS EXISTS TO STOP, and it is one line:
///
///     <assign value='source.QuickStreamId' property='target.QuickStreamId'/>
///
/// `QuickStreamId` is a `%String`, so that compiles, runs, returns `$$$OK` — and copies a
/// REFERENCE. You now have two message headers over one body. Measured: two saved
/// `HS.FHIRServer.Interop.Request` rows (41 and 42) with the same id, one stream. For read-only
/// fan-out that is correct and cheap. As a transform it is a defect that cannot be seen in the
/// Visual Trace, because the trace faithfully shows the same payload on both hops.
///
/// WHAT THE <code> BLOCK BELOW IS AVOIDING. Building the outgoing stream is where payloads are
/// actually lost, and all three traps return a clean status:
///
///     %New()              pTemp defaults to 1 -- the data lands in ^CacheTemp.HS.Stream with an
///                         id like T7. Use %New("", 0) for anything another process will read.
///     %Save()             does NOT write the buffer. Measured: after Write("ORIGINAL") and
///                         %Save(), both $$$OK, ^HS.Stream(8) is EMPTY. Flush() writes it -- and so
///                         does letting the OREF go out of scope, which is %OnClose flushing on
///                         your behalf and is why this looks intermittent.
///     Clear()             empties GRef AND Id. The next Write() returns $$$OK and Flush() throws
///                         <SYNTAX>Flush+4^HS.SDA3.QuickStream.1 from deployed platform code.
///
/// `CopyFromAndSave()` is the paired method that sidesteps all three, and it writes the size node
/// `^HS.Stream(id,0)` that Write+Flush leaves out.
///
/// AND ONE THING ABOUT `<code>` BLOCKS THAT COST A COMPILE HERE — §5.20. The generated `Transform`
/// wraps the block in a `Try`, so `quit $$$ERROR(...)` is
///     #1043: QUIT argument not allowed
/// which names the `Quit` and not the `Try` that made it illegal. The generated code's own idiom,
/// read out of the .INT routine rather than guessed, is `Set tSC=<status>` followed by a BARE
/// `Quit`; `tSC` is what the method returns.
Class Example.DT.FhirRedact Extends Ens.DataTransformDTL [ DependsOn = HS.FHIRServer.Interop.Request ]
{

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='HS.FHIRServer.Interop.Request' targetClass='HS.FHIRServer.Interop.Request' create='new' language='objectscript' >
<assign value='source.Request' property='target.Request' action='set' />
<code>
<![CDATA[
 // THE BODY IS NOT REACHABLE FROM HERE BY ANY PROPERTY. Open it by id, or do not touch it.
 //
 // $IsObject on the result, NOT %ExistsId. %ExistsId returns 0 for a stream that plainly exists --
 // positive control on a stream nobody had deleted: %ExistsId=0, %OpenId returns an object, the
 // body reads back in full, $D(^HS.Stream("16"))=11. The reason is structural rather than a bug to
 // wait out: %Dictionary.CompiledStorage has ZERO rows for HS.SDA3.QuickStream and
 // HS_SDA3.QuickStream is not a table (SQLCODE -30), so there is no extent for existence to be
 // looked up in. A guard written on %ExistsId rejects every payload that has ever existed.
 set tIn = ##class(HS.SDA3.QuickStream).%OpenId(source.QuickStreamId, , .tScIn)
 if '$isobject(tIn) {
   // `set tSC` then a BARE `quit` -- see the header. `quit $$$ERROR(...)` here does not compile.
   set tSC = $$$ERROR($$$GeneralError, "FHIR payload stream "_source.QuickStreamId_" did not open")
   quit
 }

 do tIn.Rewind()
 set tBody = ""
 // Read() defaults to 32000, not "everything". A single Read() on a Bundle is a truncation waiting
 // for a big enough message, and it is the kind that only appears in production.
 while 'tIn.AtEnd { set tBody = tBody _ tIn.Read(32000) }

 // The edit itself is deliberately trivial -- a string substitution, not a FHIR parse -- so that
 // nothing in this example depends on which FHIR version or profile is installed. Real work goes
 // through %DynamicObject or HS.FHIRServer.* here; the stream handling either side is the same.
 set tEdited = $replace(tBody, """family"":""DOE""", """family"":""REDACTED""")

 // A NEW stream, so the inbound message keeps its own payload and the trace stays truthful.
 // CopyFromAndSave persists in one step; %New("", 0) because 0 means NOT temporary.
 set tTmp = ##class(%Stream.GlobalCharacter).%New()
 do tTmp.Write(tEdited)
 set tOut = ##class(HS.SDA3.QuickStream).%New("", 0)
 set tSC = tOut.CopyFromAndSave(tTmp)
 quit:$$$ISERR(tSC)

 set target.QuickStreamId = tOut.Id
]]>
</code>
</transform>
}

}
