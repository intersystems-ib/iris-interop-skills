/// Rule: BestPractices_Interop_IRIS.md §5.7 "DTL: declare the transform, don't write it imperatively"
/// Validity: Still valid.
/// Severity: High.
///
/// The canonical DTL shape: `Ens.DataTransformDTL` + an `XData DTL` block.
///
/// WHY DECLARED, NOT IMPERATIVE: an `Ens.DataTransformDTL` subclass with NO `XData DTL` still
/// compiles — and the Portal's DTL editor then opens nothing (conformance CR-4). Moving the same
/// logic into a hand-written BP `OnRequest` is CR-1, a P1 finding. If a transform genuinely
/// cannot be declared, that is a design signal worth raising, not a licence to write it by hand.
///
/// ESCAPING TRAP (the commonest DTL compile failure): the body is an XData block, so it is parsed
/// as XML FIRST and ObjectScript SECOND. `&&` must be written `&amp;&amp;`, `&` as `&amp;`,
/// `<` as `&lt;`. An unescaped `&` fails with
///   "ERROR #6301: SAX XML Parser Error: expected entity name for reference"
/// and the reported line/offset points into the XData stream, NOT into this file — the numbers
/// will not match your editor. Both forms are shown below: `<if>` uses the escaped operators,
/// `<code>` wraps the raw ObjectScript in CDATA, which survives copy-paste and later edits better.
///
/// COMPILE-ORDER TRAP: the `Transform` method is built by a method GENERATOR that resolves
/// `sourceClass` and `targetClass` at generation time, so both must ALREADY BE COMPILED. Compile
/// this class in the same batch as its message classes and it can fail with
///   ERROR #5001: Error with source class 'Example.MSG.AcceptOrderReq': <CLASS DOES NOT EXIST>
///     > ERROR #5490: Error running generator for method 'Transform:Example.DT.OrderToVendor'
/// even though the class is right there in the batch. It is an ordering artefact, not a defect:
/// recompiling once the message classes exist succeeds unchanged. Compile messages first, or
/// simply compile twice.
///
/// VERIFIED BEHAVIOUR (live IRIS 2026.1, not just compiled):
///   OrderId="ORD-1", PatientId="PAT-9"  ->  VendorRef="ORD-1"  Priority="NORMAL"
///                                           Note="ref=ORD-1 pid=PAT-9"
///   OrderId="",      PatientId=""       ->  VendorRef=""       Priority="LOW"
///                                           Note="ref="
/// The second case is what proves the escaped `&amp;&amp;` really evaluates rather than merely parsing.
Class Example.DT.OrderToVendor Extends Ens.DataTransformDTL
{

Parameter IGNOREMISSINGSOURCE = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='Example.MSG.AcceptOrderReq' targetClass='Example.MSG.VendorOrder' create='new' language='objectscript'>
<assign value='source.OrderId' property='target.VendorRef' action='set'/>
<if condition='(source.OrderId="")&amp;&amp;(source.PatientId="")'>
<true>
<assign value='"LOW"' property='target.Priority' action='set'/>
</true>
<false>
<assign value='"NORMAL"' property='target.Priority' action='set'/>
</false>
</if>
<code>
<![CDATA[ set target.Note = "ref="_source.OrderId_$select(source.PatientId'="":" pid="_source.PatientId,1:"") ]]>
</code>
</transform>
}

}
