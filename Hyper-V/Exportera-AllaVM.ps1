<#
.SYNOPSIS
    Exporterar ALLA Hyper-V-VM:ar till t.ex. en extern disk.

.DESCRIPTION
    Går igenom samtliga VM:ar på värden. VM:ar som är igång stängs av,
    exporteras och startas sedan igen. VM:ar som var avstängda exporteras
    och förblir avstängda. En avstängd VM ger en helt konsistent export.

.PARAMETER ExportPath
    Mapp dit exporterna skrivs, t.ex. E:\HyperV_Backup

.PARAMETER Online
    Exportera utan att stänga av VM:arna (Hyper-V gör då en
    kontrollpunktsbaserad export).

.EXAMPLE
    .\Exportera-AllaVM.ps1 -ExportPath E:\HyperV_Backup
#>

param(
    [Parameter(Mandatory)]
    [string]$ExportPath,

    [switch]$Online
)

# Skapa mappen om den inte finns
if (!(Test-Path $ExportPath)) {
    New-Item -Path $ExportPath -ItemType Directory | Out-Null
}

# Hämta alla virtuella maskiner
$VMs = Get-VM

foreach ($VM in $VMs) {
    Write-Host "Exporterar: $($VM.Name)" -ForegroundColor Cyan

    $wasRunning = ($VM.State -eq 'Running')

    # Stäng av VM om den är igång
    if ($wasRunning -and -not $Online) {
        Stop-VM -Name $VM.Name -Force
    }

    try {
        # Exportera VM (rensa ev. tidigare export av samma VM först)
        $target = Join-Path $ExportPath $VM.Name
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Export-VM -Name $VM.Name -Path $ExportPath -ErrorAction Stop
    }
    catch {
        Write-Host "Fel vid export av $($VM.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        # Starta bara VM:ar som var igång innan
        if ($wasRunning -and -not $Online) {
            Start-VM -Name $VM.Name
        }
    }
}

Write-Host "Export klar. Alla VM:ar finns i $ExportPath" -ForegroundColor Green
