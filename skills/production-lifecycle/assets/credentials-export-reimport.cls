/// Rule: BestPractices_Interop_IRIS.md §13.7 "Credentials migration: walk Ens.Config.Credentials, export, re-import"
/// Validity: Still valid.
/// Severity: High.
///
/// Problem: Ensemble credentials store passwords in a Secondary database encrypted
/// with the instance key. Standard backup-restore preserves the credential RECORDS
/// but the passwords are unreadable on the new instance (different key).
///
/// Recipe: on the SOURCE instance, walk Ens.Config.Credentials, dump (name, username, password)
/// to a file (which lives encrypted-at-rest by your file system / OS). On the TARGET instance,
/// re-import.
///
/// Identity note: Ens.Config.Credentials has an IDKEY/PrimaryKey index on SystemName
/// (Idx SystemName, IdKey true, PrimaryKey true), so the credential's ID IS its SystemName.
/// Create a row by setting the SystemName PROPERTY — `set tCred.%Id() = tName` does not
/// compile (#1027: %Id() is a method, not an assignable property).
///
/// Operational hygiene:
///   - Hold the dump file on encrypted disk; delete after re-import.
///   - Do NOT commit the dump file to git or to source control.
///   - The dump file is a credential vault for the migration window only.
Class Example.Migration.Credentials Extends %RegisteredObject
{

/// Walk Ens.Config.Credentials on the SOURCE namespace, dump each row to pFile.
/// Format: one row per line, fields TAB-separated:
///   <name> TAB <username> TAB <password>
ClassMethod Export(pFile As %String, pNamespace As %String = "") As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM tRS as %SQL.StatementResult
    #DIM tStmt as %SQL.Statement
    #DIM tLine as %String
    #DIM errObj as %Exception.AbstractException
    new $namespace
    if pNamespace '= "" set $namespace = pNamespace

    open pFile:("WNS"):2
    if '$test {
        quit $$$ERROR($$$GeneralError, "Cannot open "_pFile_" for write")
    }
    try {
        // Select SystemName, not ID. They are the same value (SystemName is the IDKEY), but
        // naming the property says so out loud and survives any change to the projected ID
        // column. Password projects to SQL as the computed plaintext column.
        set tStmt = ##class(%SQL.Statement).%New()
        set tSC = tStmt.%Prepare("SELECT SystemName, Username, Password FROM Ens_Config.Credentials")
        $$$ThrowOnError(tSC)
        set tRS = tStmt.%Execute()
        while tRS.%Next() {
            set tLine = tRS.%Get("SystemName") _ $Char(9)
                      _ tRS.%Get("Username") _ $Char(9)
                      _ tRS.%Get("Password")
            use pFile  write tLine, !
        }
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    close pFile
    quit tSC
}

/// Read pFile (produced by Export) and re-create the credential rows on the TARGET.
/// If a row with the same name already exists, the password is updated in place.
ClassMethod Import(pFile As %String, pNamespace As %String = "") As %Status
{
    #DIM tSC as %Status = $$$OK
    #DIM tStream as %Stream.FileCharacter
    #DIM tLine as %String
    #DIM tName, tUsername, tPassword as %String
    #DIM tCred as Ens.Config.Credentials
    #DIM errObj as %Exception.AbstractException
    new $namespace
    if pNamespace '= "" set $namespace = pNamespace

    if '##class(%File).Exists(pFile) {
        quit $$$ERROR($$$GeneralError, "Cannot open "_pFile_" for read: no such file")
    }
    try {
        // Read through %Stream.FileCharacter, NOT `open pFile:("R")` + `read`. A bare READ
        // past end-of-file raises <ENDOFFILE> unless $ZEOF mode is enabled, and the catch
        // below would convert that normal end of input into a failure %Status — a successful
        // import reporting an error. AtEnd makes the terminating condition explicit.
        // (The `use pFile:(::"S")` + $ZEOF form works too; the stream needs no such care.)
        set tStream = ##class(%Stream.FileCharacter).%New()
        set tSC = tStream.LinkToFile(pFile)
        $$$ThrowOnError(tSC)
        while 'tStream.AtEnd {
            set tLine = tStream.ReadLine()
            continue:tLine=""                        // blank / trailing line
            set tName = $Piece(tLine, $Char(9), 1)
            set tUsername = $Piece(tLine, $Char(9), 2)
            set tPassword = $Piece(tLine, $Char(9), 3)
            if ##class(Ens.Config.Credentials).%ExistsId(tName) {
                set tCred = ##class(Ens.Config.Credentials).%OpenId(tName)
            } else {
                set tCred = ##class(Ens.Config.Credentials).%New()
                set tCred.SystemName = tName         // SystemName IS the ID; %Id() is not assignable
            }
            set tCred.Username = tUsername
            set tCred.Password = tPassword
            set tSC = tCred.%Save()
            $$$ThrowOnError(tSC)
        }
    } catch (errObj) {
        set tSC = errObj.AsStatus()
    }
    quit tSC
}

}
