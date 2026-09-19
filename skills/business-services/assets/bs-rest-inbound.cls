/// Rule: BestPractices_Interop_IRIS.md §6.8 "REST inbound — EnsLib.REST.Service and the dispatch that is not a MessageMap"
/// Validity: Verified against IRIS for Health 2026.1.
/// Severity: Medium.
///
/// Pattern: an inbound REST endpoint as a Business Service. EnsLib.REST.Service extends
/// %CSP.REST, so dispatch is by URL through XData UrlMap — NOT by message type through an
/// XData MessageMap, which is the BO mechanism. Mixing the two is the usual first mistake:
/// a MessageMap on a REST service is simply never consulted.
///
/// THERE IS NO INBOUND ADAPTER, and Parameter ADAPTER must be "" (or absent). The web
/// application is the adapter: the CSP/web app is what accepts the socket, so the production
/// item exists to give the service a ConfigName, a pool and settings — it does not poll.
/// A consequence worth stating: the service does not appear to "start" in any visible way, and
/// a 404 on the endpoint is a WEB APPLICATION problem, not a production problem. Check the web
/// app's dispatch class and its role/permissions before touching the production.
///
/// %CSP.REST dispatches to a CLASSMETHOD. That method has no instance, so ..SendRequestAsync()
/// is not available on it — get a service instance first with
/// Ens.Director.CreateBusinessService(), which is what makes the production item load-bearing.
/// See business-services §"REST/CSP entry point".
Class Example.BS.PreauthRest Extends EnsLib.REST.Service
{

/// No inbound adapter: the web application accepts the request.
Parameter ADAPTER = "";

Parameter SETTINGS = "TargetConfigNames:Basic";

Property TargetConfigNames As %String(MAXLEN = 1000);

/// Dispatch is by URL, through UrlMap. A MessageMap here would never be consulted.
XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/preauth" Method="POST" Call="SubmitPreauth"/>
  <Route Url="/preauth/:id" Method="GET" Call="GetPreauth"/>
</Routes>
}

/// %CSP.REST calls a CLASSMETHOD, so there is no instance and no ..SendRequestAsync here.
/// Ens.Director.CreateBusinessService is how you get one — the ConfigName must match the
/// production item name exactly.
ClassMethod SubmitPreauth() As %Status
{
    #DIM tSC As %Status = $$$OK
    #DIM tService As Ens.BusinessService
    #DIM errObj As %Exception.AbstractException
    try {
        Set tSC = ##class(Ens.Director).CreateBusinessService("BS.PreauthRest", .tService)
        Quit:$$$ISERR(tSC)

        Set tBody = ##class(Ens.StringContainer).%New()
        Set tBody.StringValue = %request.Content.Read(32000)

        Set tSC = tService.SendRequestAsync(tService.TargetConfigNames, tBody)
        Quit:$$$ISERR(tSC)

        Set %response.Status = "202 Accepted"
        Write "{""accepted"":true}"
    }
    catch (errObj) {
        Set tSC = errObj.AsStatus()
        Set %response.Status = "500 Internal Server Error"
    }
    Quit tSC
}

ClassMethod GetPreauth(pId As %String) As %Status
{
    Set %response.ContentType = "application/json"
    Write "{""id"":""" _ pId _ """}"
    Quit $$$OK
}

}
