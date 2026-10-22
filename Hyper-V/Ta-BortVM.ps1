<#
.SYNOPSIS
    Tar bort en Hyper-V-VM och dess virtuella hårddiskar ("återställ labbet").

.DESCRIPTION
    Stoppar VM:en om den körs, hämtar sökvägarna till alla anslutna VHD/VHDX,
    tar bort VM:en och raderar sedan diskfilerna. Är VM-mappen tom efteråt
    tas även den bort. Kräver bekräftelse om inte -Force anges.

.PARAMETER VMName
    Namnet på VM:en som ska tas bort.

.PARAMETER Force
    Hoppa över bekräftelsefrågan.

.EXAMPLE
    .\Ta-BortVM.ps1 -VMName DC01
#>

param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [switch]$Force
)

Write-Host "🔍 Kontrollerar om VM '$VMName' finns..."

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "⚠️ VM '$VMName' hittades inte." -ForegroundColor Yellow
    return
}

# Spara diskarnas sökvägar och VM-mappen innan VM:en tas bort
$disks  = @(Get-VMHardDiskDrive -VMName $VMName | Select-Object -ExpandProperty Path)
$vmPath = $vm.Path

Write-Host "Följande tas bort:" -ForegroundColor Cyan
Write-Host "  VM:    $VMName"
$disks | ForEach-Object { Write-Host "  Disk:  $_" }

if (-not $Force) {
    $confirm = Read-Host "Är du säker? (J/N)"
    if ($confirm -notin @("J","j","Ja","ja")) { Write-Host "Avbrutet." -ForegroundColor Yellow; return }
}

if ($vm.State -eq 'Running') {
    Write-Host "🛑 Stoppar VM..."
    Stop-VM -Name $VMName -TurnOff -Force
}

Write-Host "🧨 Tar bort VM '$VMName'..."
Remove-VM -Name $VMName -Force

# Ta bort VHD-filer
foreach ($disk in $disks) {
    if (Test-Path $disk) {
        Write-Host "🗑️ Tar bort disk: $disk"
        Remove-Item $disk -Force
    } else {
        Write-Host "📁 Disk hittades inte: $disk"
    }
}

# Ta bort VM-mappen om den är tom
if ((Test-Path $vmPath) -and -not (Get-ChildItem $vmPath -Recurse -File)) {
    Write-Host "🧹 Tar bort tom mapp: $vmPath"
    Remove-Item $vmPath -Recurse -Force
}

Write-Host "Klart." -ForegroundColor Green
