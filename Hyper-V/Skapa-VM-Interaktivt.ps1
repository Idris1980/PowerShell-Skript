<#
.SYNOPSIS
    Skapar en eller flera Hyper-V-VM:ar (Generation 2) som bootar från en vald ISO.

.DESCRIPTION
    - Hämtar standardsökvägar för VM och VHDX från Hyper-V-värdens inställningar.
    - Låter dig välja ISO-fil i en filväljare och switch från en lista.
    - Frågar efter antal VM:ar, minne, CPU och diskstorlek (gäller alla).
    - Frågar efter namn per VM, skapar VM + dynamisk VHDX, kopplar ISO:n
      och sätter DVD som första boot-enhet.
    Därefter installerar du Windows i VM:en som vanligt.

.NOTES
    Kör som administratör på Hyper-V-värden.
#>

Add-Type -AssemblyName System.Windows.Forms

# ==== 1. Hämta sökvägar automatiskt från Hyper-V-inställningar ====
$VMHostSettings = Get-VMHost
$VMBasePath  = $VMHostSettings.VirtualMachinePath
$VHDBasePath = $VMHostSettings.VirtualHardDiskPath

# Säkerställ att mapparna finns
foreach ($Path in @($VMBasePath, $VHDBasePath)) {
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# ==== 2. Välj ISO-fil ====
$OpenFile = New-Object System.Windows.Forms.OpenFileDialog
$OpenFile.Filter = "ISO files (*.iso)|*.iso"
$OpenFile.Title  = "Välj ISO-fil"

if ($OpenFile.ShowDialog() -ne "OK") {
    Write-Host "Ingen ISO vald. Avbryter." -ForegroundColor Red
    exit
}
$ISOPath = $OpenFile.FileName

# ==== 3. Välj virtuell switch ====
$AvailableSwitches = Get-VMSwitch
Write-Host "`nTillgängliga virtuella switchar:" -ForegroundColor Cyan
$AvailableSwitches | Select-Object Name, SwitchType | Out-String | Write-Host

$SwitchName = Read-Host "Ange namnet på den switch du vill använda"
if (-not ($AvailableSwitches.Name -contains $SwitchName)) {
    Write-Host "Switchen '$SwitchName' finns inte. Avbryter." -ForegroundColor Red
    exit
}

# ==== 4. Frågor om resurser ====
$VMCount  = [int](Read-Host "`nHur många VM vill du skapa?")
$MemoryGB = [int](Read-Host "Minne per VM (GB)")
$CPUCount = [int](Read-Host "Antal CPU per VM")
$DiskGB   = [int](Read-Host "Diskstorlek per VM (GB)")

$MemoryBytes = $MemoryGB * 1GB
$DiskBytes   = $DiskGB   * 1GB

# ==== 5. Loop där du namnger varje VM ====
for ($i = 1; $i -le $VMCount; $i++) {

    $VMName = Read-Host "`nAnge namn för VM #$i"
    Write-Host "Skapar $VMName..." -ForegroundColor Cyan

    try {
        # Skapa VM
        New-VM `
            -Name $VMName `
            -Generation 2 `
            -MemoryStartupBytes $MemoryBytes `
            -Path $VMBasePath `
            -SwitchName $SwitchName `
            -ErrorAction Stop | Out-Null

        # Processor
        Set-VMProcessor -VMName $VMName -Count $CPUCount

        # Hårddisk (VHDX)
        $VHDPath = Join-Path $VHDBasePath "$VMName.vhdx"
        New-VHD -Path $VHDPath -SizeBytes $DiskBytes -Dynamic | Out-Null
        Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

        # DVD + boot-ordning
        Add-VMDvdDrive -VMName $VMName -Path $ISOPath
        Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

        Write-Host "$VMName är klar!" -ForegroundColor Green
    }
    catch {
        Write-Host "Fel vid skapande av $VMName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nFärdigt! Alla $VMCount maskiner har behandlats." -ForegroundColor Yellow
