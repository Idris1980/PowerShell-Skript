<#
.SYNOPSIS
    Enkel import av AD-användare från en CSV-fil till en vald OU.

.DESCRIPTION
    Läser en CSV med kolumnerna first_name, last_name och department och skapar
    ett AD-konto per rad:
      - SamAccountName: förnamn.efternamn (mellanslag bort, å/ä -> a, ö -> o,
        övriga specialtecken bort, max 20 tecken)
      - Name/DisplayName: "Förnamn Efternamn"
      - UPN: SamAccountName@<domänen>
      - Användaren måste byta lösenord vid första inloggning.
    Rader som saknar för- eller efternamn och användare som redan finns hoppas över.

    Exempel på CSV-format finns i Exempeldata\anvandare-enkel.csv.

.PARAMETER CsvPath
    Sökväg till CSV-filen.

.PARAMETER TargetOU
    DistinguishedName för OU:n där användarna ska skapas.
    Utelämnas den får du välja OU i en lista (Out-GridView).

.PARAMETER Delimiter
    Avgränsare i CSV-filen. Standard är komma.

.EXAMPLE
    .\Importera-AnvandareFranCSV.ps1 -CsvPath C:\Temp\Users.csv -TargetOU "OU=Users,OU=Foretaget,DC=lab,DC=local"

.NOTES
    Kräver: ActiveDirectory-modulen. Startlösenordet frågas efter vid körning.
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$TargetOU,

    [string]$Delimiter = ","
)

Import-Module ActiveDirectory

# --- Steg 1: Förberedelser ---

if (-not $TargetOU) {
    $TargetOU = (Get-ADOrganizationalUnit -Filter * |
        Select-Object Name, DistinguishedName |
        Out-GridView -Title "Välj OU för de nya användarna" -PassThru).DistinguishedName
    if (-not $TargetOU) { Write-Host "Ingen OU vald. Avbryter." -ForegroundColor Yellow; exit }
}

Write-Host "Kontrollerar OU-sökväg: $TargetOU" -ForegroundColor Yellow
try {
    Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop | Out-Null
} catch {
    Write-Error "KRITISKT FEL: OU hittades inte ($TargetOU)."
    exit 1
}

if (-not (Test-Path $CsvPath)) {
    Write-Error "KRITISKT FEL: CSV-filen hittades inte ($CsvPath)."
    exit 1
}

$UpnSuffix       = (Get-ADDomain).DNSRoot
$DefaultPassword = Read-Host "Ange startlösenord för de nya användarna" -AsSecureString

Write-Host "Importerar CSV..." -ForegroundColor Yellow
$UserData = @(Import-Csv -Path $CsvPath -Delimiter $Delimiter -Encoding UTF8)

Write-Host "`nHittade $($UserData.Count) rader att bearbeta." -ForegroundColor Yellow
Write-Host "`n--- Startar Användarskapande ---" -ForegroundColor Cyan

# --- Steg 2: Loopa igenom CSV ---

foreach ($User in $UserData) {

    # Kontrollera att nödvändiga fält finns
    if ([string]::IsNullOrWhiteSpace($User.first_name) -or
        [string]::IsNullOrWhiteSpace($User.last_name)) {

        Write-Warning "Hoppar över rad – 'first_name' eller 'last_name' saknas. Data: $($User | Select-Object *)"
        continue
    }

    # Rensa bort mellanslag/åäö för SamAccountName
    $CleanFirst = ($User.first_name.ToLower() -replace '\s+', '' -replace '[åä]', 'a' -replace 'ö', 'o')
    $CleanLast  = ($User.last_name.ToLower()  -replace '\s+', '' -replace '[åä]', 'a' -replace 'ö', 'o')

    $SamAccountName = "$CleanFirst.$CleanLast" -replace '[^a-z0-9\.]', ''
    if ($SamAccountName.Length -gt 20) { $SamAccountName = $SamAccountName.Substring(0, 20) }

    $DisplayName = "$($User.first_name) $($User.last_name)"
    $UPN         = "$SamAccountName@$UpnSuffix"
    $Department  = $User.department

    Write-Host "`nFörsöker skapa: $SamAccountName ($DisplayName)" -ForegroundColor Cyan

    # Kontrollera om användaren redan finns
    if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
        Write-Host "Hoppar över – användare finns redan: $SamAccountName" -ForegroundColor Yellow
        continue
    }

    # --- Skapa användaren ---
    try {
        $userParams = @{
            Name                  = $DisplayName
            SamAccountName        = $SamAccountName
            UserPrincipalName     = $UPN
            GivenName             = $User.first_name
            Surname               = $User.last_name
            DisplayName           = $DisplayName
            AccountPassword       = $DefaultPassword
            ChangePasswordAtLogon = $true
            Enabled               = $true
            Path                  = $TargetOU
        }
        if ($Department) { $userParams.Department = $Department }
        New-ADUser @userParams -ErrorAction Stop

        Write-Host "SUCCESS: $SamAccountName skapad." -ForegroundColor Green
    }
    catch {
        Write-Host "FEL: Kunde inte skapa $SamAccountName" -ForegroundColor Red
        Write-Host "Detaljer: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Write-Host "`n--- Import Slutförd ---" -ForegroundColor Green
