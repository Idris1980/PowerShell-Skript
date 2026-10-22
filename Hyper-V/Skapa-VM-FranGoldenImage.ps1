<#
.SYNOPSIS
    Skapar VM:ar snabbt genom att kopiera en förberedd "golden image" (sysprepad VHDX).

.DESCRIPTION
    För varje ny VM kopieras mall-VHDX:en till en ny disk, en Generation 2-VM
    skapas med valt minne och antal CPU-kärnor, disken kopplas på och sätts
    som första boot-enhet, och VM:en startas. Namnen kan numreras automatiskt
    (VM1, VM2, ...) eller anges per VM.

.PARAMETER TemplateVHD
    Sökväg till golden image (sysprepad .vhdx).

.PARAMETER VMPath
    Mapp för VM-konfigurationen. Standard: Hyper-V-värdens standardsökväg.

.PARAMETER VHDPath
    Mapp där de nya VHDX-filerna sparas. Standard: Hyper-V-värdens standardsökväg.

.PARAMETER SwitchName
    Virtuell switch som VM:arna kopplas till.

.EXAMPLE
    .\Skapa-VM-FranGoldenImage.ps1 -TemplateVHD "D:\Hyper-V\Templates\Win2022-Golden.vhdx" -SwitchName LAN

.NOTES
    Kör som administratör på Hyper-V-värden. Mallen bör vara generaliserad med
    sysprep /generalize /oobe /shutdown för att undvika dubbla SID.
#>

param(
    [Parameter(Mandatory)]
    [string]$TemplateVHD,

    [string]$VMPath = (Get-VMHost).VirtualMachinePath,

    [string]$VHDPath = (Get-VMHost).VirtualHardDiskPath,

    [Parameter(Mandatory)]
    [string]$SwitchName
)

if (-not (Test-Path $TemplateVHD)) {
    Write-Host "Fel: Golden image finns inte på $TemplateVHD" -ForegroundColor Red
    exit 1
}

# ---------- INTERAKTIV INPUT ----------
$VMCount  = [int](Read-Host "Hur många VM vill du skapa?")
$MemoryGB = [int](Read-Host "Ange mängd RAM i GB för alla VM")
$CPUCount = [int](Read-Host "Ange antal CPU-kärnor för alla VM")
$AutoName = Read-Host "Vill du automatiskt numrera VM (Ja/Nej)?"

# ---------- SKAPA MÅLMAPP OM DEN INTE FINNS ----------
if (-not (Test-Path $VHDPath)) {
    Write-Host "Mappen $VHDPath finns inte, skapar den..."
    New-Item -ItemType Directory -Path $VHDPath | Out-Null
}

# ---------- LOOP FÖR ATT SKAPA VM ----------
for ($i = 1; $i -le $VMCount; $i++) {

    # Hantera namn på VM
    if ($AutoName -match "^[Jj]") {
        $VMName = "VM$i"
    } else {
        $VMName = Read-Host "Ange namn för VM #$i"
    }

    # Kopiera golden image till ny VHDX
    $NewVHD = Join-Path $VHDPath "$VMName.vhdx"
    if (Test-Path $NewVHD) {
        Write-Host "Disken $NewVHD finns redan – hoppar över $VMName." -ForegroundColor Yellow
        continue
    }

    Write-Host "`nKopierar golden image till $NewVHD..."
    Copy-Item -Path $TemplateVHD -Destination $NewVHD

    # Skapa VM (Generation 2)
    Write-Host "Skapar VM $VMName..."
    New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -Path $VMPath -SwitchName $SwitchName | Out-Null

    # Sätt CPU
    Set-VMProcessor -VMName $VMName -Count $CPUCount

    # Koppla hårddisk
    Add-VMHardDiskDrive -VMName $VMName -Path $NewVHD

    # Säkerställ korrekt boot-enhet
    $HDD = Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.Path -eq $NewVHD }
    Set-VMFirmware -VMName $VMName -FirstBootDevice $HDD

    # Starta VM
    Start-VM -Name $VMName

    Write-Host "VM $VMName skapad och startad med boot från hårddisk!" -ForegroundColor Green
}

Write-Host "`nKlart!"
