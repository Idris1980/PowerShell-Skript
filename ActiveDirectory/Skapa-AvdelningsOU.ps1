<#
.SYNOPSIS
    Skapar en "Departments"-OU med en under-OU per avdelning.

.DESCRIPTION
    Skapar OU=Departments under -ParentOU (om den saknas) och därefter en
    under-OU för varje avdelning i -Departments. OU:er som redan finns
    hoppas över, så skriptet kan köras flera gånger.

.PARAMETER ParentOU
    DistinguishedName för OU:n där "Departments" ska ligga,
    t.ex. "OU=Foretaget,DC=lab,DC=local".

.PARAMETER Departments
    Namnen på avdelnings-OU:erna.

.EXAMPLE
    .\Skapa-AvdelningsOU.ps1 -ParentOU "OU=Foretaget,DC=lab,DC=local"
#>

param(
    [Parameter(Mandatory)]
    [string]$ParentOU,

    [string[]]$Departments = @(
        "IT",
        "Lager",
        "Ekonomi",
        "Sälj",
        "Marknad",
        "Logistik",
        "Ledning",
        "VD"
    )
)

Import-Module ActiveDirectory

$RootOU = "OU=Departments,$ParentOU"

# Skapa Departments-OU
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Departments'" -SearchBase $ParentOU -SearchScope OneLevel)) {
    New-ADOrganizationalUnit -Name "Departments" -Path $ParentOU
    Write-Host "Skapade OU=Departments" -ForegroundColor Green
} else {
    Write-Host "OU=Departments finns redan." -ForegroundColor Yellow
}

# Skapa en OU per avdelning
foreach ($Dept in $Departments) {

    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Dept'" -SearchBase $RootOU -SearchScope OneLevel)) {
        New-ADOrganizationalUnit -Name $Dept -Path $RootOU
        Write-Host "Skapade OU=$Dept" -ForegroundColor Green
    }
    else {
        Write-Host "OU=$Dept finns redan." -ForegroundColor Yellow
    }
}
