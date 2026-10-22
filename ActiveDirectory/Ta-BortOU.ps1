<#
.SYNOPSIS
    Tar bort en vald OU och ALLT dess innehåll, inklusive raderingsskydd.

.DESCRIPTION
    Visar alla OU:er i en lista (Out-GridView). Efter bekräftelse tas
    "Protect object from accidental deletion" bort från den valda OU:n och
    alla under-OU:er, och sedan raderas OU:n rekursivt.

    VARNING: Allt i OU:n (användare, grupper, datorer, under-OU:er) raderas.

.NOTES
    Kräver: ActiveDirectory-modulen och grafiskt gränssnitt (Out-GridView).
#>

Import-Module ActiveDirectory

# Hämta alla OU i domänen
$allOUs = Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName

# Låt användaren välja OU
$selectedOU = $allOUs | Out-GridView `
    -Title "Välj den OU du vill ta bort" `
    -PassThru

# Om ingen OU valdes
if (-not $selectedOU) {
    Write-Host "Ingen OU valdes. Avbryter." -ForegroundColor Yellow
    return
}

$ouDN = $selectedOU.DistinguishedName

Write-Host "Du har valt:" -ForegroundColor Cyan
Write-Host $ouDN -ForegroundColor Cyan

# Bekräftelse
$confirmation = Read-Host "Är du säker på att du vill ta bort denna OU och ALLT innehåll? (Ja/Nej)"

if ($confirmation -notin @("Ja", "ja", "J", "j")) {
    Write-Host "Åtgärden avbröts av användaren." -ForegroundColor Yellow
    return
}

Write-Host "Tar bort skydd mot oavsiktlig radering..." -ForegroundColor Cyan

# Ta bort skydd från OU och alla under-OU
Get-ADOrganizationalUnit -Filter * -SearchBase $ouDN |
    Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false

Write-Host "Raderar OU och allt innehåll..." -ForegroundColor Red

# Ta bort OU rekursivt
Remove-ADOrganizationalUnit `
    -Identity $ouDN `
    -Recursive `
    -Confirm:$false

Write-Host "OU raderad framgångsrikt!" -ForegroundColor Green
