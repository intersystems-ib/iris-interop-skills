/// Rule: BestPractices_Interop_IRIS.md §11.5 "OAuth 2.0 + LDAP server-side broker pattern"
/// Validity: Verified against IRIS for Health 2026.1 — compiled, and its structure measured
///           against the live class dictionary. See "WHAT IS NOT VERIFIED" at the end.
/// Severity: High (this class is the thing that decides whether a credential is accepted).
///
/// Pattern: the OAuth 2.0 server's user-validation hook, delegating the credential check to
/// LDAP / Active Directory. It is a SUBCLASS of `%OAuth2.Server.Validate`, and that one
/// decision is most of what this file has to teach.
///
/// WHAT THIS REPLACES. §11.5 used to ship `oauth2-server-validate-ldap.cls.xml`: 207 lines
/// declaring `Alt.OAuth2.Server.Validate Extends %RegisteredObject` — a COPY of the vendor class
/// with `ValidateUser` rewritten. Two things were wrong with that beyond the copying. It was an
/// XML class export, so `.cls.xml` matched no tier and the most security-sensitive file in this
/// bank was compiled by nothing. And `skills/security` step 3 asks for "two custom **subclasses**";
/// the artefact it pointed at was not a subclass. The three differences below are what the copy
/// cost, each measured on 2026.1 rather than argued.
///
/// 1. `SupportedClaims` — THE COPY SILENTLY EMPTIED IT. Read out of the live dictionary, the
///    inherited implementation is:
///        Quit $lb("preferred_username","email","email_verified","name","phone_number",
///                 "phone_number_verified")
///    The copy overrode it with `quit ""`. Measured through `$classmethod(cls,"SupportedClaims")`:
///        %OAuth2.Server.Validate   claims=6
///        a subclass (this file)    claims=6      <- inherited, nothing to write
///        the copy's override       claims=0
///    The vendor's own comment on that method is "This is the list that corresponds to the above
///    code" — it is the list of claims the server states it can supply. Overriding it with an empty
///    list is a change nobody asked for, made by copy-paste, in a file no tier read.
///
/// 2. `ValidateClient` — FIVE COPIED LINES THAT CHANGED NOTHING. The vendor body, read from
///    `%Dictionary.MethodDefinition`, is exactly:
///        Set sc=$$$OK
///        Quit 1
///    The copy reproduces it verbatim. So the copy did NOT weaken client validation — worth saying,
///    because that is the first thing you suspect on seeing `Quit 1`. What it did was take
///    ownership of five lines of vendor code that must now be re-diffed on every upgrade to learn
///    that they are still identical. Note what the default means, though: this hook accepts every
///    client, because client authentication happens against the client secret in the server
///    configuration and not here. A subclass is the right place to add a per-client check IF you
///    want one; inheriting is the right thing if you do not.
///
/// 3. THE SIGNATURE WAS STALE, AND NOTHING ANYWHERE REPORTS IT. The vendor `ValidateUser` takes
///    SIX formals; the copy declares five, having been written before `use2fa` existed:
///        vendor: username, password, scope, properties, *sc, *use2fa:%Boolean=0
///        copy:   username, password, scope, properties, *sc
///    Every stage was measured, because the interesting result is how quiet this is:
///        5-param override, compiled as a subclass ........... COMPILES CLEAN
///        called with six actual arguments, as the server does  NO error raised
///          after the call $D(use2fa) goes 0 -> 1 and reads 0
///        6-param override that sets use2fa=1 ................ caller reads 1
///    That last line is the positive control, and without it the two zeros above prove nothing:
///    it establishes that the flag CAN travel, so `use2fa=0` from the five-param form is a real
///    result and not an artefact of how it was measured. The stale signature therefore compiles,
///    runs, returns a plausible boolean, and its only symptom is that two-factor can never be
///    requested. There is no error to find. This is why the signature below was copied from the
///    running dictionary and not from the sample it derives from.
///
/// WHY `##super()` IS DELIBERATELY NOT CALLED — the one spot in this bank where that is correct.
/// The reflex in a subclass, and the one this repo's own tier-1 check C14 enforces for `OnInit` on
/// prebuilt `EnsLib.*` hosts, is to call `##super()`. Here it would be a security defect. The
/// inherited `ValidateUser` authenticates against the LOCAL IRIS user database (`Security.Users`,
/// `CheckPassword`), so `Set ok = ..##super(...)` as an LDAP-unreachable fallback means a directory
/// outage silently re-enables local accounts as an authentication source. The rule is not "always
/// call super" — it is: super when the base class does setup you are EXTENDING, never when the base
/// class is the behaviour you are REPLACING. An LDAP failure here must fail closed, which is what
/// the `Catch` below does by leaving the return at 0 and putting the reason in messages.log.
///
/// AN INHERITED DEFAULT THAT IS SAFE UPSTREAM AND UNSAFE HERE — the subtlest thing on this page.
/// The vendor `ValidateUser` contains `If password'="",'##class(Security.Users).CheckPassword(...)`:
/// an empty password means "this user is already logged into a session, do not re-check", which is
/// safe when the check is a local password comparison. Carry that convention into an LDAP bind and
/// it inverts, because an LDAP simple bind with an empty password is an ANONYMOUS bind and returns
/// success. The sequence then reads: resolve the user's DN, bind with an empty password, receive
/// `$$$LDAPSUCCESS`, return 1 — every existing username authenticates with no password at all.
/// Step 5 below rejects it explicitly, and that guard is the single line whose removal turns this
/// class into an open door.
///
/// MEASURED MACRO VALUES, because one of them is the opposite of the natural guess. `Include
/// %syLDAP` alone resolves all four (the copy included `%syLDAP,%syLDAPFunc,%sySite`; the other two
/// are not needed for these):
///     $$$LDAPSUCCESS = 0      $$$LDAPSCOPESUBTREE = 2
///     $$$LDAPPORT    = 389    $$$LDAPOPTXTLSCACERTFILE = 24578
/// `$$$LDAPSUCCESS` is **0**. So `If tErr` is the ERROR test and `If 'tErr` is the success test,
/// which is backwards from how most people read a status, and a truthiness test written the
/// comfortable way round accepts every failure. Compare against the macro, as below.
///
/// THE `Alt` OBLIGATION DISAPPEARS. `skills/interop` "Reserved package names" gives `Alt` to
/// "System classes that had to be patched", with the standing cost "re-test on every IRIS/Ensemble
/// upgrade — the patched version may need to be reapplied". A copy of a vendor class is a patch and
/// carries that for ever. A subclass is not a patch: it lives in an ordinary application package,
/// and it INHERITS vendor fixes to the methods it does not override instead of pinning them at the
/// version they were copied on.
///
/// DEPLOYMENT, and the mistake it produces. Measured from an application namespace,
/// `SELECT Name FROM %Dictionary.CompiledClass WHERE Name LIKE 'OAuth2.Server%'` returns only
/// `%SYS.OAuth2.Validation` — `OAuth2.Server.Configuration` is not visible there, because the OAuth
/// 2.0 server configuration is a `%SYS`-only object. So two different namespaces are in play: the
/// configuration is edited in `%SYS` (Portal: System Administration > Security > OAuth 2.0 >
/// Server), and THIS class must be compiled into the customisation namespace that the
/// configuration names. Compiling it where you happen to be working, then reading "my
/// ValidateUserClass is never called", is the standard form of that error.
///
/// ALL VALUES BELOW ARE PLACEHOLDERS. Replace the server, the BaseDN and the Credentials entry
/// name before deploying. The LDAP read user's DN and password live in `Ens.Config.Credentials` —
/// never in class source — so the secret is rotated from the portal (Interoperability > Configure >
/// Credentials) with no recompile and no re-export. That does require an interoperability-enabled
/// namespace, which is the normal case for this pattern and worth checking if it is not.
///
/// TWO PARAMETERS FROM THE COPY ARE GONE, both deliberately:
///   `LDAPServer2`, documented there as "Not yet used", is dead configuration — an operator sets it
///   and believes they have a secondary directory, which is worse than having no such parameter.
///   `FILTER` is renamed `UsernameAttribute`: it never held a filter, it held the attribute name
///   (AD `sAMAccountname`, OpenLDAP `uid`) that step 4 builds a filter FROM.
///
/// WHAT IS NOT VERIFIED, stated plainly so a green tier is not read as more than it is. No LDAP
/// server was contacted. What is measured is everything the compiler and the class dictionary can
/// see: the class compiles, the six-formal signature matches the vendor's, all 13 `%SYS.LDAP`
/// methods called below exist with the arities used, the four macros resolve to the values quoted,
/// and the claim list is inherited rather than emptied. The bind sequence itself — anonymous
/// connect, StartTLS, admin bind, DN lookup, user rebind — is unexecuted here and is the part to
/// smoke-test against a real directory, per §11.5's discovery-endpoint check.
Include %syLDAP

Class Example.SEC.ValidateLDAP Extends %OAuth2.Server.Validate
{

/// Name of the `Ens.Config.Credentials` entry holding the LDAP read user: `Username` = its bind DN,
/// `Password` = its password. A class Parameter cannot be overridden by System Default Settings —
/// SDS applies to production host settings only — so the supported way to change these is a
/// subclass of this class.
Parameter Credentials = "LDAP_READER";

Parameter LDAPServer = "ldap1.example.com";

Parameter BaseDN = "OU=Users,dc=example,dc=com";

/// The attribute the username is looked up by. AD: sAMAccountname. OpenLDAP: uid.
Parameter UsernameAttribute = "sAMAccountname";

/// CA certificate file for StartTLS (Unix). Empty means the bind is NOT protected — acceptable only
/// for a directory reached over a trusted link, because a simple bind sends the password in clear.
Parameter UnixCertificateFile = "";

/// Six formals, matching `%OAuth2.Server.Validate::ValidateUser` exactly — see the header for what
/// a five-formal version costs and why nothing reports it.
ClassMethod ValidateUser(username As %String, password As %String, scope As %ArrayOfDataTypes, properties As %OAuth2.Server.Properties, Output sc As %Status, Output use2fa As %Boolean = 0) As %Boolean
{
    Set sc = $$$OK
    Set use2fa = 0
    Set tValid = 0
    Set tSC = $$$OK
    // Initialised to "" so the cleanup at the end can tell "never opened" from "open".
    Set tLD = ""
    Set tSearch = ""

    Try {
        // 1. Connect. Init reports failure by returning "", NOT by returning an error code, so a
        //    `'= $$$LDAPSUCCESS` test on it would read "" '= 0 as true and look like an error even
        //    on success. Test for the empty handle, then ask GetLastError() why.
        Set tLD = ##class(%SYS.LDAP).Init(..#LDAPServer)
        If tLD = "" {
            Set tErr = ##class(%SYS.LDAP).GetLastError()
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap Init("_..#LDAPServer_") - "_##class(%SYS.LDAP).Err2String(tErr)))
        }

        // 2. StartTLS before any credential crosses the wire. Compared against $$$LDAPSUCCESS (=0)
        //    rather than tested for truth -- see the header.
        If ..#UnixCertificateFile '= "" {
            Set tErr = ##class(%SYS.LDAP).SetOption(tLD, $$$LDAPOPTXTLSCACERTFILE, ..#UnixCertificateFile)
            If tErr '= $$$LDAPSUCCESS {
                $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_setoption(CACERTFILE) - "_##class(%SYS.LDAP).Err2String(tErr)))
            }
            Set tErr = ##class(%SYS.LDAP).StartTLSs(tLD)
            If tErr '= $$$LDAPSUCCESS {
                $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_StartTLSs - "_##class(%SYS.LDAP).Err2String(tErr)))
            }
        }

        // 3. Bind as the read user. Its DN and password come from the credentials store; the only
        //    thing in this source file is the NAME of the entry.
        Set tCred = ##class(Ens.Config.Credentials).%OpenId(..#Credentials, , .tCredSC)
        If '$IsObject(tCred) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "Ens.Config.Credentials '"_..#Credentials_"' not found - "_$system.Status.GetErrorText(tCredSC)))
        }
        Set tErr = ##class(%SYS.LDAP).SimpleBinds(tLD, tCred.Username, tCred.Password)
        If tErr '= $$$LDAPSUCCESS {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_Binds("_tCred.Username_") - "_##class(%SYS.LDAP).Err2String(tErr)))
        }

        // 4. Resolve the username to a DN. SizeLimit 1 with the >1 rejection below is the point:
        //    a non-unique attribute must be an ERROR, never "take the first match", or the account
        //    that authenticates is whichever the directory happened to return first.
        Set tFilter = ..#UsernameAttribute_"="_username
        Set tAttrs = $ListBuild("displayName")
        Set tErr = ##class(%SYS.LDAP).SearchExts(tLD, ..#BaseDN, $$$LDAPSCOPESUBTREE, tFilter, tAttrs, 0, "", "", 10, 1, .tSearch)
        If tErr '= $$$LDAPSUCCESS {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_SearchExt - "_##class(%SYS.LDAP).Err2String(tErr)))
        }
        Set tCount = ##class(%SYS.LDAP).CountEntries(tLD, tSearch)
        If tCount = -1 {
            Set tErr = ##class(%SYS.LDAP).GetError(tLD)
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_Count_Entries - "_##class(%SYS.LDAP).Err2String(tErr)))
        }
        If tCount = 0 {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "user '"_username_"' not found under "_..#BaseDN))
        }
        If tCount > 1 {
            $$$ThrowStatus($$$ERROR($$$GeneralError, ..#UsernameAttribute_"='"_username_"' is not unique ("_tCount_" entries)"))
        }
        Set tEntry = ##class(%SYS.LDAP).FirstEntry(tLD, tSearch)
        If tEntry = 0 {
            Set tErr = ##class(%SYS.LDAP).GetError(tLD)
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_FirstEntry - "_##class(%SYS.LDAP).Err2String(tErr)))
        }
        Set tUserDN = ##class(%SYS.LDAP).GetDN(tLD, tEntry)

        // 5. THE GUARD. An LDAP simple bind with an empty password binds ANONYMOUSLY and returns
        //    success, so without this the next step authenticates any existing username with no
        //    password. The inherited implementation treats password="" as "already authenticated in
        //    this session, skip the check", which is safe against a local password comparison and
        //    is NOT safe against a bind. Do not port that convention down here.
        If password = "" {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "refusing an empty password for "_tUserDN_" - an empty simple bind is an anonymous bind and would succeed"))
        }

        // 6. Authenticate: re-bind as the user with the password being validated.
        Set tErr = ##class(%SYS.LDAP).SimpleBinds(tLD, tUserDN, password)
        If tErr '= $$$LDAPSUCCESS {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "ldap_Simple_Bind("_tUserDN_") - "_##class(%SYS.LDAP).Err2String(tErr)))
        }
        Set tValid = 1
    }
    Catch tEx {
        // FAIL CLOSED: tValid stays 0. The reason goes to messages.log, where an operator can find
        // it, rather than to a private global only its author knows to read.
        // Event MUST be exactly two dot-pieces: WriteToConsoleLog checks $L(Event,".")'=2 and
        // SILENTLY substitutes "Utility.Event" otherwise, so "Example.SEC.ValidateLDAP" would
        // vanish from the log it was meant to label. Severity 2 = Severe.
        Set tSC = tEx.AsStatus()
        Do ##class(%SYS.System).WriteToConsoleLog("ValidateLDAP rejected '"_username_"': "_tEx.DisplayString(), 0, 2, "OAuth2.ValidateLDAP")
    }

    // 7. Cleanup on BOTH paths -- the failure path is the one that leaks handles, and it is the
    //    path an attacker can drive repeatedly.
    If tSearch '= "" {
        Do ##class(%SYS.LDAP).MsgFree(tSearch)
    }
    If tLD '= "" {
        Do ##class(%SYS.LDAP).UnBinds(tLD)
    }

    // Hand the diagnostic back. Without this the server gets a bare 0 and the operator gets no
    // reason; `sc` is an output the caller reads.
    Set sc = tSC
    Return tValid
}

}
