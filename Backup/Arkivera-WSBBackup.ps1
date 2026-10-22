<#
.SYNOPSIS
    Kopierar den senaste Windows Server Backup-disken (VHDX) till en arkivmapp med tidsstämpel.

.DESCRIPTION
    Windows Server Backup (WSB) skriver över sin backup på en nätverksshare vid
    varje körning. Det här skriptet letar upp den senaste .vhdx-filen i
    WindowsImageBackup-mappen och kopierar den till en arkivmapp med namnet
    <Server>-Backup-<yyyy-MM-dd_HHmm>.vhdx, så att flera versioner sparas.
    Replikeras arkivmappen med DFS-R finns kopiorna på flera servrar.

    Rekommenderat upplägg:
      1. Skapa en staging-share på filservern, t.ex. \\FS01\BackupStaging,
         som bara används av WSB.
      2. Konfigurera WSB på servern som ska backas upp att spara till sharen
         och kör en backup (mappen WindowsImageBackup skapas).
      3. Skapa en separat arkiv-share, t.ex. \\FS01\BackupArchive.
      4. (Valfritt) Sätt upp DFS-replikering av arkivmappen till en andra filserver.
      5. Schemalägg skriptet i Task Scheduler att köras efter att backupen är klar,
         t.ex. kl 03:00 om backupen startar 01:00:
           powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Arkivera-WSBBackup.ps1 -StagingPath \\FS01\BackupStaging -ArchivePath \\FS01\BackupArchive

.PARAMETER StagingPath
    UNC-sökväg till sharen där WSB sparar (mappen som innehåller WindowsImageBackup).

.PARAMETER ArchivePath
    UNC-sökväg till mappen där kopiorna ska sparas.

.PARAMETER ServerName
    Servernamn som används i filnamnet. Standard: datorns namn.

.EXAMPLE
    .\Arkivera-WSBBackup.ps1 -StagingPath \\FS01\BackupStaging -ArchivePath \\FS01\BackupArchive
#>

param(
    [Parameter(Mandatory)]
    [string]$StagingPath,

    [Parameter(Mandatory)]
    [string]$ArchivePath,

    [string]$ServerName = $env:COMPUTERNAME
)

try {
    Write-Host "Startar arkivering av backup..." -ForegroundColor Green

    # 1. Hitta roten för WSB-mappen
    $WsbRoot = Join-Path -Path $StagingPath -ChildPath "WindowsImageBackup"
    if (-not (Test-Path $WsbRoot)) {
        throw "Mappen WindowsImageBackup hittades inte i '$WsbRoot'. Kontrollera -StagingPath."
    }
    Write-Host "Hittade WSB-rot: $WsbRoot"

    # 2. Hitta den senaste VHDX-filen i hela strukturen
    Write-Host "Letar efter senaste VHDX-filen..."
    $SourceVHDX = Get-ChildItem -Path $WsbRoot -Recurse -Filter *.vhdx |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1

    if ($null -eq $SourceVHDX) {
        throw "Ingen .vhdx-fil hittades i '$WsbRoot'. Har en backup körts?"
    }
    Write-Host "Källfil: $($SourceVHDX.FullName)"

    # 3. Skapa nytt filnamn med tidsstämpel
    $Timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $NewFileName = "$ServerName-Backup-$Timestamp.vhdx"
    $DestinationFile = Join-Path -Path $ArchivePath -ChildPath $NewFileName
    Write-Host "Ny arkivfil: $DestinationFile"

    # 4. Skapa arkivmappen om den saknas
    if (-not (Test-Path $ArchivePath)) {
        Write-Host "Arkivmappen '$ArchivePath' saknas, skapar den..." -ForegroundColor Yellow
        New-Item -Path $ArchivePath -ItemType Directory | Out-Null
    }

    # 5. Kopiera filen
    Write-Host "Kopierar VHDX... Detta kan ta en stund."
    Copy-Item -Path $SourceVHDX.FullName -Destination $DestinationFile -ErrorAction Stop

    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "KLART: Arkiveringen lyckades." -ForegroundColor Green
    Write-Host "Fil kopierad till: $DestinationFile"
    Write-Host "============================================="
}
catch {
    Write-Error "SKRIPTET MISSLYCKADES: $($_.Exception.Message)"
    exit 1
}
