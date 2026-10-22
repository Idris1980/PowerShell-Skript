<#
.SYNOPSIS
    Importerar användare från CSV och bygger OU + grupper per avdelning automatiskt.

.DESCRIPTION
    För varje rad i CSV-filen:
      - Skapar (vid behov) en under-OU per avdelning under en huvud-OU.
      - Skapar en global grupp (GL_<avdelning>) och en domänlokal grupp
        (DL_<avdelning>) och lägger GL-gruppen i DL-gruppen (AGDLP).
      - Skapar användaren med SamAccountName förnamn.efternamn
        (gemener, å/ä -> a, ö -> o, max 20 tecken) och UPN mot domänen.
      - Lägger användaren i avdelningens GL-grupp.
    Befintliga användare hoppas över.

    CSV-format (semikolonseparerad), se Exempeldata\anvandare-avdelning.csv:
        FirstName;LastName;FullName;Department;Office

.PARAMETER CsvPath
    Sökväg till CSV-filen.

.PARAMETER BaseOUName
    Namn på huvud-OU:n i domänens rot som avdelnings-OU:erna skapas under.

.EXAMPLE
    .\Importera-AnvandareMedAvdelningar.ps1 -CsvPath C:\Temp\users.csv -BaseOUName Foretaget

.NOTES
    Kräver: ActiveDirectory-modulen. Startlösenordet frågas efter vid körning.
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$BaseOUName
)

Import-Module ActiveDirectory

Write-Host "=== Automatisk AD-import till OU: $BaseOUName ===" -ForegroundColor Cyan

# ---- KONFIGURATION ----
if (-not (Test-Path $CsvPath)) {
    Write-Host "Filen hittades inte!" -ForegroundColor Red
    exit 1
}

$domain     = Get-ADDomain
$domainDN   = $domain.DistinguishedName
$domainFQDN = $domain.DNSRoot
$baseOUPath = "OU=$BaseOUName,$domainDN"

$users    = Import-Csv $CsvPath -Delimiter ";" -Encoding UTF8
$password = Read-Host "Ange startlösenord för de nya användarna" -AsSecureString

# ---- Funktioner ----
function Create-OU {
    param($BasePath, $Name)
    $fullPath = "OU=$Name,$BasePath"
    $check = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $BasePath -SearchScope OneLevel -ErrorAction SilentlyContinue
    if (-not $check) {
        New-ADOrganizationalUnit -Name $Name -Path $BasePath
        Write-Host "  > Skapade OU: $Name" -ForegroundColor Gray
    }
    return $fullPath
}

function Create-ADGroup {
    param($GroupName, $GroupScope, $Path)
    $check = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
    if (-not $check) {
        # Category är alltid Security, Scope är Global eller DomainLocal
        New-ADGroup -Name $GroupName -GroupCategory Security -GroupScope $GroupScope -Path $Path
        Write-Host "  > Skapade grupp: $GroupName ($GroupScope)" -ForegroundColor Gray
    }
}

# 1. Kontrollera/skapa huvud-OU
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$BaseOUName'" -SearchBase $domainDN -SearchScope OneLevel)) {
    New-ADOrganizationalUnit -Name $BaseOUName -Path $domainDN
    Write-Host "Skapade huvud-OU: $BaseOUName" -ForegroundColor Gray
}

foreach ($u in $users) {
    $fName    = $u.FirstName.Trim()
    $lName    = $u.LastName.Trim()
    $dept     = $u.Department.Trim()
    $office   = "$($u.Office)".Trim()
    $fullName = if ($u.FullName) { $u.FullName.Trim() } else { "$fName $lName" }

    # ---- SamAccountName ----
    $firstClean = $fName.ToLower() -replace '[åä]','a' -replace 'ö','o' -replace '[^a-z]',''
    $lastClean  = $lName.ToLower() -replace '[åä]','a' -replace 'ö','o' -replace '[^a-z]',''
    $sam = "$firstClean.$lastClean"
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }

    $upn = "$sam@$domainFQDN"

    # ---- OU & Grupper ----
    $deptClean = $dept -replace '[^\w\s]', ''
    $ouPath = Create-OU $baseOUPath $deptClean

    $gg = "GL_$deptClean"
    $lg = "DL_$deptClean"

    Create-ADGroup $gg "Global" $ouPath
    Create-ADGroup $lg "DomainLocal" $ouPath

    # Koppla ihop grupperna (GL in i DL)
    Add-ADGroupMember -Identity $lg -Members $gg -ErrorAction SilentlyContinue

    # ---- Skapa användaren ----
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "⏭ Skippar $sam – finns redan" -ForegroundColor Yellow
    }
    else {
        try {
            $userParams = @{
                SamAccountName        = $sam
                Name                  = $fullName
                GivenName             = $fName
                Surname               = $lName
                DisplayName           = $fullName
                Title                 = $dept
                Department            = $dept
                Path                  = $ouPath
                Enabled               = $true
                AccountPassword       = $password
                ChangePasswordAtLogon = $true
                UserPrincipalName     = $upn
            }
            if ($office) { $userParams.Office = $office }
            New-ADUser @userParams -ErrorAction Stop

            # Lägg till användaren i den globala gruppen
            Add-ADGroupMember -Identity $gg -Members $sam -ErrorAction SilentlyContinue
            Write-Host "✔ Klar: $fullName" -ForegroundColor Green
        }
        catch {
            Write-Host "✖ Fel vid $fullName : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "=== Import klar ===" -ForegroundColor Cyan
