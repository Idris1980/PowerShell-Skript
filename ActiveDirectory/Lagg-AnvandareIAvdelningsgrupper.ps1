<#
.SYNOPSIS
    Lägger AD-användare i säkerhetsgrupper utifrån avdelningen i en CSV-fil.

.DESCRIPTION
    Läser en CSV med kolumnerna GivenName, Surname och Department. Varje
    användare slås upp i AD på för- och efternamn och läggs i gruppen
    <GroupPrefix><Department>, t.ex. GG_IT eller GG_Ekonomi.

    Passar ihop med Skapa-Sakerhetsgrupper.ps1 som skapar grupperna.

.PARAMETER CsvPath
    Sökväg till CSV-filen (semikolonseparerad).

.PARAMETER GroupPrefix
    Prefix för gruppnamnen. Standard är "GG_".

.EXAMPLE
    .\Lagg-AnvandareIAvdelningsgrupper.ps1 -CsvPath C:\Temp\users.csv
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$GroupPrefix = "GG_"
)

Import-Module ActiveDirectory

Write-Host "Läser användare från CSV (UTF-8)..." -ForegroundColor Yellow
$UserData = Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8

Write-Host "`n--- Lägger användare i grupper ---" -ForegroundColor Cyan

foreach ($User in $UserData) {

    # Kontrollera att avdelning finns
    if ([string]::IsNullOrWhiteSpace($User.Department)) {
        Write-Warning "Ingen Department angiven för $($User.GivenName) $($User.Surname) – hoppar över."
        continue
    }

    $GroupName = "$GroupPrefix$($User.Department.Trim())"

    # Hämta användaren i AD
    $GivenName = $User.GivenName.Trim()
    $Surname   = $User.Surname.Trim()
    $ADUser = @(Get-ADUser -Filter "GivenName -eq '$GivenName' -and Surname -eq '$Surname'" -ErrorAction SilentlyContinue)
    if ($ADUser.Count -ne 1) {
        Write-Warning "Hittade $($ADUser.Count) AD-konton för $GivenName $Surname – hoppar över."
        continue
    }

    # Kontrollera att gruppen finns
    if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
        Write-Warning "Gruppen saknas i AD: $GroupName"
        continue
    }

    try {
        Add-ADGroupMember -Identity $GroupName -Members $ADUser[0] -ErrorAction Stop
        Write-Host "SUCCESS: $($ADUser[0].SamAccountName) → $GroupName" -ForegroundColor Green
    }
    catch {
        Write-Host "FEL: Kunde inte lägga till $($ADUser[0].SamAccountName) i $GroupName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
}

Write-Host "`n--- Färdigt! ---" -ForegroundColor Green
