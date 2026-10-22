<#
.SYNOPSIS
    Exporterar utvalda Hyper-V-VM:ar till en tidsstämplad backupmapp med loggning.

.DESCRIPTION
    - Startar Hyper-V-tjänsten (vmms) om den inte är igång.
    - Exporterar varje VM i -VMName till <BackupPath>\<VM>_<yyyyMMdd_HHmm>.
    - VM:ar som inte finns hoppas över.
    - Allt loggas både till konsolen och till en loggfil.
    Export-VM fungerar även när VM:en är igång (Hyper-V 2012 R2 och senare).

.PARAMETER VMName
    Namnen på VM:arna som ska säkerhetskopieras.

.PARAMETER BackupPath
    Basmapp för backuperna.

.PARAMETER LogPath
    Mapp för loggfiler. Standard: <BackupPath>\Logs

.EXAMPLE
    .\Backup-VM.ps1 -VMName DC01,FS01,CL01 -BackupPath D:\Backup\Hyper-V

.NOTES
    Lämpar sig för att schemaläggas i Task Scheduler.
#>

param(
    [Parameter(Mandatory)]
    [string[]]$VMName,

    [Parameter(Mandatory)]
    [string]$BackupPath,

    [string]$LogPath = (Join-Path $BackupPath "Logs")
)

# Datumformat för backupmapp
$Date = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile = Join-Path $LogPath "HyperV_Backup_$Date.log"

# ----------------------------------------
# Funktion: Logga meddelanden till fil och konsol
# ----------------------------------------
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Host $entry
}

# ----------------------------------------
# Kontrollera att loggmapp finns
# ----------------------------------------
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory | Out-Null
}

# ----------------------------------------
# Starta Hyper-V-tjänsten om den inte är igång
# ----------------------------------------
$vmmsService = Get-Service -Name "vmms" -ErrorAction SilentlyContinue
if ($vmmsService.Status -ne 'Running') {
    Write-Log "Startar Hyper-V-tjänsten (vmms)..."
    Start-Service -Name "vmms"
    Start-Sleep -Seconds 5
}

# ----------------------------------------
# Backup-processen
# ----------------------------------------

Write-Log "Backup startad."

foreach ($vm in $VMName) {
    try {
        # Kontrollera om VM finns
        $vmObj = Get-VM -Name $vm -ErrorAction SilentlyContinue
        if ($null -eq $vmObj) {
            Write-Log "VM '${vm}' hittades inte. Hoppar över."
            continue
        }

        # Skapa unik backupmapp för varje VM
        $vmBackupPath = Join-Path -Path $BackupPath -ChildPath "${vm}_$Date"
        if (!(Test-Path $vmBackupPath)) {
            New-Item -Path $vmBackupPath -ItemType Directory | Out-Null
            Write-Log "Skapade mapp: $vmBackupPath"
        }

        # Exportera VM
        Write-Log "Startar export av ${vm}..."
        Export-VM -Name $vm -Path $vmBackupPath -ErrorAction Stop
        Write-Log "Export av ${vm} klar."

    } catch {
        Write-Log "Fel vid export av ${vm}: $($_.Exception.Message)"
    }
}

Write-Log "Backup avslutad."
