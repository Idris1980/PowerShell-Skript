<#
.SYNOPSIS
    Skapar en uppsättning globala säkerhetsgrupper i en angiven OU.

.DESCRIPTION
    Skapar en global säkerhetsgrupp för varje namn i -Groups. Grupper som
    redan finns hoppas över. Kontrollerar först att mål-OU:n finns.

.PARAMETER GroupOU
    DistinguishedName för OU:n där grupperna ska skapas.

.PARAMETER Groups
    Namnen på grupperna som ska skapas.

.EXAMPLE
    .\Skapa-Sakerhetsgrupper.ps1 -GroupOU "OU=Groups,OU=Foretaget,DC=lab,DC=local"

.EXAMPLE
    .\Skapa-Sakerhetsgrupper.ps1 -GroupOU "OU=Groups,DC=lab,DC=local" -Groups GG_IT,GG_HR
#>

param(
    [Parameter(Mandatory)]
    [string]$GroupOU,

    [string[]]$Groups = @(
        "GG_Lager",
        "GG_IT",
        "GG_HR",
        "GG_Ekonomi",
        "GG_Sälj",
        "GG_Logistik",
        "GG_Ledning"
    )
)

Import-Module ActiveDirectory

Write-Host "Kontrollerar OU: $GroupOU" -ForegroundColor Yellow
try {
    Get-ADOrganizationalUnit -Identity $GroupOU -ErrorAction Stop | Out-Null
} catch {
    Write-Error "Fel: OU:n hittas inte. Kontrollera DN!"
    exit 1
}

Write-Host "`n--- Skapar säkerhetsgrupper ---" -ForegroundColor Cyan

foreach ($Group in $Groups) {

    Write-Host "Skapar grupp: $Group" -ForegroundColor Cyan

    # Kontrollera om gruppen finns
    if (Get-ADGroup -Filter "Name -eq '$Group'") {
        Write-Host "Hoppar över – gruppen finns redan: $Group" -ForegroundColor Yellow
        continue
    }

    try {
        New-ADGroup `
            -Name $Group `
            -SamAccountName $Group `
            -GroupScope Global `
            -GroupCategory Security `
            -Path $GroupOU `
            -ErrorAction Stop

        Write-Host "SUCCESS: Grupp skapad -> $Group" -ForegroundColor Green
    }
    catch {
        Write-Host "FEL: Kunde inte skapa gruppen $Group" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
}

Write-Host "`n--- Gruppskapande slutfört ---" -ForegroundColor Green
