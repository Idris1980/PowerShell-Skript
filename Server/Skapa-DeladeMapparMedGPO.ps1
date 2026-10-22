<#
.SYNOPSIS
    Skapar avdelningsmappar på en filserver, delar ut dem och länkar en GPO för mappade enheter.

.DESCRIPTION
    - Skapar (vid behov) en GPO och länkar den till angiven OU.
    - Skapar en mapp per avdelning under -BasePath och delar ut den som en
      SMB-share med full åtkomst för -FullAccessGroup.
    Själva Drive Maps-inställningarna läggs därefter till i GPO:n via
    Group Policy Management (GUI), eftersom det saknas cmdlets för det.

.PARAMETER TargetOU
    DistinguishedName för OU:n som GPO:n ska länkas till.

.PARAMETER BasePath
    Lokal sökväg där mapparna skapas. Standard: C:\Shares

.PARAMETER Folders
    Mappar/shares som ska skapas.

.PARAMETER FullAccessGroup
    Grupp som får full åtkomst till sharen. Standard: Domain Users

.PARAMETER GPOName
    Namn på GPO:n. Standard: "Drive Mapping – Shares"

.EXAMPLE
    .\Skapa-DeladeMapparMedGPO.ps1 -TargetOU "OU=Users,OU=Foretaget,DC=lab,DC=local"

.NOTES
    Kör på filservern. Kräver GroupPolicy-modulen (RSAT) och domänadmin-rättigheter.
#>

param(
    [Parameter(Mandatory)]
    [string]$TargetOU,

    [string]$BasePath = "C:\Shares",

    [string[]]$Folders = @("Ekonomi","IT","Lager","Marknad","Sälj","VD"),

    [string]$FullAccessGroup = "Domain Users",

    [string]$GPOName = "Drive Mapping – Shares"
)

Import-Module GroupPolicy

# 1. Skapa GPO om den inte finns
$gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GPOName
    Write-Host "Skapade GPO: $GPOName"
} else {
    Write-Host "GPO finns redan: $GPOName"
}

# 2. Länka GPO till OU (om den inte redan är länkad)
$linked = (Get-GPInheritance -Target $TargetOU).GpoLinks | Where-Object { $_.DisplayName -eq $GPOName }
if (-not $linked) {
    New-GPLink -Name $GPOName -Target $TargetOU -Enforced No -LinkEnabled Yes | Out-Null
    Write-Host "Länkade GPO till OU: $TargetOU"
} else {
    Write-Host "GPO är redan länkad till: $TargetOU"
}

# 3. Skapa och dela ut undermappar
foreach ($folder in $Folders) {
    $FullPath = Join-Path $BasePath $folder
    $ShareName = $folder

    # Skapa mappen om den inte finns
    if (-not (Test-Path $FullPath)) {
        New-Item -Path $FullPath -ItemType Directory -Force | Out-Null
        Write-Host "Skapade mappen: $FullPath"
    } else {
        Write-Host "Mappen finns redan: $FullPath"
    }

    # Skapa share om den inte finns
    if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $ShareName -Path $FullPath -FullAccess $FullAccessGroup | Out-Null
        Write-Host "Delade ut $FullPath som \\$env:COMPUTERNAME\$ShareName till $FullAccessGroup"
    } else {
        Write-Host "Share $ShareName finns redan"
    }
}

Write-Host "`n✔ KLART! Mappar skapade, delade ut och GPO länkad. Lägg nu till Drive Maps i GPO:n via GUI." -ForegroundColor Green
