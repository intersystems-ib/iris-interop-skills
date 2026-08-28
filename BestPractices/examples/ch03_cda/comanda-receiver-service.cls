/// Rule: BestPractices_Interop_IRIS.md §3.2 "Comanda/Resposta inheritance trick for one-of-N subtypes payloads"
/// Validity: Still valid.
/// Severity: Medium.
///
/// Business Service entrypoint for the §3.2 pattern: peek at the inbound payload and
/// materialise the concrete `Demo.MSG.Comanda` subclass it matches.
/// Companion to `comanda-resposta-inheritance.cls` (the abstract envelope).
///
/// Named `Demo.BS.ComandaReceiver`, not `Demo.BS`: the convention is
/// `<Pkg>.<Tipo>.<Nombre>` (skills/interop), so the Tipo goes in the middle and the
/// class always carries a Name.
Class Demo.BS.ComandaReceiver Extends Ens.BusinessService
{

/// Local name of the child element that marks the SC1 variant. Replace with whatever
/// discriminator your envelope actually uses (element, attribute or namespace).
Parameter SC1ELEMENT = "SC1";

/// SIGNATURE TRAP: the superclass fixes this as
/// `pInput:%RegisteredObject, *pOutput:%RegisteredObject, &pHint:%String`. Typing pOutput
/// As %String, or omitting pHint, fails to compile with "ERROR #5478: Keyword signature
/// error ... must be '%Library.RegisteredObject,%Library.RegisteredObject,%Library.String'".
/// Narrowing pInput to a %RegisteredObject subclass (%Stream.Object here) IS allowed.
Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
{
    #DIM tComanda as Demo.MSG.Comanda
    #DIM tDoc as %XML.Document
    #DIM tSC as %Status = $$$OK
    set tSC = ##class(%XML.Document).GetDocumentFromStream(pInput, .tDoc)
    quit:$$$ISERR(tSC) tSC

    // Inspect the inbound XML to decide which concrete subclass to materialise.
    if ..LooksLikeSC1(tDoc) {
        set tComanda = ##class(Demo.MSG.ComandaSC1).%New()
    } else {
        set tComanda = ##class(Demo.MSG.ComandaSC2).%New()
    }
    // ... unmarshal pInput into tComanda, then SendRequestSync to the BP production item
    //     (item name is `<Tipo>.<Nombre>`, e.g. "BP.Comanda") ...
    quit tSC
}

/// Discriminator: does the envelope carry an <SC1> child element?
/// Deliberately NOT `CodeMode = expression` returning `$$$YES` — a constant discriminator
/// makes the SC2 branch of OnProcessInput dead code, and choosing between the variants is
/// the entire point of §3.2.
ClassMethod LooksLikeSC1(pDoc As %XML.Document) As %Boolean
{
    #DIM tNode as %XML.Node
    #DIM tFound as %Boolean = 0
    if '$IsObject(pDoc) { quit 0 }
    set tNode = pDoc.GetDocumentElement()
    if '$IsObject(tNode) { quit 0 }
    if 'tNode.MoveToFirstChild(1) { quit 0 }
    for {
        if tNode.LocalName = ..#SC1ELEMENT {
            set tFound = 1
            quit
        }
        if 'tNode.MoveToNextSibling(1) { quit }
    }
    quit tFound
}

}
