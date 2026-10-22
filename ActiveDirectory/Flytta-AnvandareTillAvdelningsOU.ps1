<#
.SYNOPSIS
    Flyttar befintliga AD-användare till rätt avdelnings-OU utifrån en CSV-fil.

.DESCRIPTION
    Läser en CSV med kolumnerna GivenName, Surname och Department. Varje
    användare slås upp i AD på för- och efternamn och flyttas till
    OU=<Department>,<DepartmentsOU>. Saknas avdelning, OU eller användare
    skrivs en varning och raden hoppas över.

    Passar ihop med Skapa-AvdelningsOU.ps1 som skapar avdelnings-OU:erna.

.PARAMETER CsvPath
    Sökväg till CSV-filen (semikolonseparerad).

.PARAMETER DepartmentsOU
    DistinguishedName för OU:n som innehåller avdelnings-OU:erna,
    t.ex. "OU=Departments,OU=Foretaget,DC=lab,DC=local".

.EXAMPLE
    .\Flytta-AnvandareTillAvdelningsOU.ps1 -CsvPath C:\Temp\users.csv -DepartmentsOU "OU=Departments,OU=Foretaget,DC=lab,DC=local"
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$DepartmentsOU
)

Import-Module ActiveDirectory

$UserData = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8

Write-Host "`n--- Flyttar användare till rätt OU ---`n" -ForegroundColor Yellow

foreach ($User in $UserData) {

    if ([string]::IsNullOrWhiteSpace($User.Department)) {
        Write-Warning "Saknar Department för: $($User.GivenName) $($User.Surname)"
        continue
    }

    $Dept     = $User.Department.Trim()
    $TargetOU = "OU=$Dept,$DepartmentsOU"

    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Dept'" -SearchBase $DepartmentsOU -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        Write-Warning "OU för avdelning '$Dept' finns inte under $DepartmentsOU. Hoppar över."
        continue
    }

    # Slå upp användaren på för- och efternamn
    $GivenName = $User.GivenName.Trim()
    $Surname   = $User.Surname.Trim()
    $ADUser = @(Get-ADUser -Filter "GivenName -eq '$GivenName' -and Surname -eq '$Surname'" -ErrorAction SilentlyContinue)

    if ($ADUser.Count -eq 0) {
        Write-Warning "Kunde inte hitta AD-konto för $GivenName $Surname. Hoppar över."
        continue
    }
    if ($ADUser.Count -gt 1) {
        Write-Warning "Flera AD-konton heter $GivenName $Surname. Hoppar över (flytta manuellt)."
        continue
    }

    # Flytta
    try {
        Move-ADObject -Identity $ADUser[0].DistinguishedName -TargetPath $TargetOU -ErrorAction Stop
        Write-Host "SUCCESS: $($ADUser[0].SamAccountName) flyttad till $TargetOU" -ForegroundColor Green
    }
    catch {
        Write-Host "FEL: Kunde inte flytta $($ADUser[0].SamAccountName) → $TargetOU : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n--- Färdigt! ---`n" -ForegroundColor Yellow
