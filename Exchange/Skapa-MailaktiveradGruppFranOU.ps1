<#
.SYNOPSIS
    Skapar en mail-aktiverad säkerhetsgrupp och lägger in alla aktiva användare från en OU.

.DESCRIPTION
    Skapar gruppen med New-DistributionGroup -Type Security (så att den både
    kan få e-post och användas för behörigheter) om den saknas, och lägger
    sedan till alla aktiverade användare i käll-OU:n som medlemmar.

.PARAMETER SourceOU
    OU vars aktiva användare ska bli medlemmar.

.PARAMETER GroupName
    Namn (och alias) på gruppen, t.ex. SG-Legal.

.PARAMETER GroupOU
    OU där gruppen skapas. Standard: samma som SourceOU.

.EXAMPLE
    .\Skapa-MailaktiveradGruppFranOU.ps1 -SourceOU "OU=Legal,OU=Foretaget,DC=lab,DC=local" -GroupName SG-Legal

.NOTES
    Kör i Exchange Management Shell. Kräver även ActiveDirectory-modulen.
#>

param(
    [Parameter(Mandatory)]
    [string]$SourceOU,

    [Parameter(Mandatory)]
    [string]$GroupName,

    [string]$GroupOU = $SourceOU
)

Import-Module ActiveDirectory

# --- Skapa grupp om den inte finns ---
$Group = Get-ADGroup -Filter "Name -eq '$GroupName'"

if (-not $Group) {
    New-DistributionGroup `
        -Name $GroupName `
        -Alias $GroupName `
        -Type Security `
        -OrganizationalUnit $GroupOU | Out-Null

    # Vänta tills gruppen syns i AD
    $tries = 0
    do {
        Start-Sleep -Seconds 2
        $Group = Get-ADGroup -Filter "Name -eq '$GroupName'"
        $tries++
    } while (-not $Group -and $tries -lt 10)

    if (-not $Group) { throw "Gruppen $GroupName kunde inte hittas i AD efter skapandet." }
    Write-Host "Skapade grupp: $GroupName" -ForegroundColor Green
}

# --- Hämta aktiva användare i OU ---
$Users = Get-ADUser -SearchBase $SourceOU -Filter "Enabled -eq 'True'"

# --- Lägg till användare i gruppen ---
foreach ($User in $Users) {
    Add-ADGroupMember -Identity $Group -Members $User -ErrorAction SilentlyContinue
    Write-Host "  + $($User.SamAccountName)"
}

Write-Host "Klart! $(@($Users).Count) användare i $GroupName." -ForegroundColor Cyan
