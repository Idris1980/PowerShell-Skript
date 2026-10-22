<#
.SYNOPSIS
    Bygger helt obevakade (zero-touch) Windows Server-VM:ar i Hyper-V, med valfri ny AD-domän.

.DESCRIPTION
    Skriptet frågar interaktivt efter antal VM:ar och, per VM, namn, IP,
    lösenord, minne, CPU, disk, switch och serverroller. Därefter byggs
    maskinerna en i taget, helt utan installationsguide:

      1. En VHDX skapas och partitioneras (EFI/MSR/Windows) och Windows
         appliceras direkt från ISO:ns install.wim/esd (Expand-WindowsImage).
      2. En unattend.xml injiceras som sätter datornamn, tidszon, svenskt
         tangentbord, administratörslösenord, statisk IP och DNS.
      3. Ett PostSetup-skript injiceras som vid första inloggning installerar
         valda roller och antingen
           - befordrar maskinen till DC i en ny skog (om AD DS valts), eller
           - ansluter maskinen till domänen.
      4. Domänkontrollanten byggs FÖRST och skriptet väntar tills den är klar
         innan övriga maskiner byggs och ansluts.
      5. Status läses tillbaka från gästen via PowerShell Direct
         (C:\ZeroTouchStatus.json) och en slutrapport skrivs som logg + HTML.

    Misslyckas en VM rullas den tillbaka (VM och disk tas bort).

.PARAMETER ISOPath
    Sökväg till Windows Server-ISO:n.

.PARAMETER VMLocation
    Mapp där VHDX-filer, logg och rapport sparas.

.PARAMETER SwitchName
    Standardswitch i Hyper-V (kan ändras per VM).

.PARAMETER Subnet
    Prefixlängd för IP-adresserna. Standard: 24

.PARAMETER Gateway
    Default gateway för alla VM:ar.

.PARAMETER DNS
    DNS-server för VM:ar som inte ansluts till en ny domän.

.PARAMETER BaseIP
    Första IP-adressen. Följande VM:ar föreslås nästa adress i ordning.

.PARAMETER ImageIndex
    Index i install.wim. För Server 2022: 1 = Standard Core, 2 = Standard (Desktop Experience).

.EXAMPLE
    .\Skapa-VM-ZeroTouch.ps1 -ISOPath "D:\ISO\Server2022.iso" -VMLocation "D:\Hyper-V\VMs"

.NOTES
    Kör som administratör på Hyper-V-värden. Kräver Hyper-V- och Storage-modulerna.
    Lösenorden skrivs i klartext i unattend.xml inne i VM:en (krav från Windows
    Setup) men filen raderas automatiskt när installationen är klar.
#>

param(
    [Parameter(Mandatory)]
    [string]$ISOPath,

    [Parameter(Mandatory)]
    [string]$VMLocation,

    [string]$SwitchName = "LAN",
    [string]$Subnet     = "24",
    [string]$Gateway    = "192.168.1.1",
    [string]$DNS        = "8.8.8.8",
    [string]$BaseIP     = "192.168.1.10",
    [int]$ImageIndex    = 2,
    [int]$MemoryGB      = 4,
    [int]$CPUCount      = 2,
    [int]$DiskGB        = 50,
    [string]$TimeZoneID = "W. Europe Standard Time"
)

Clear-Host

if (!(Test-Path $ISOPath)) { throw "ISO-filen hittades inte: $ISOPath" }
If (!(Test-Path $VMLocation)) { New-Item -ItemType Directory -Force -Path $VMLocation | Out-Null }

# Standardlösenord för lokala administratören - används för VM:ar där inget eget lösenord anges
$DefaultCred = Get-Credential -UserName "Administrator" -Message "Standardlösenord för lokal administratör på de nya VM:arna"
if ($null -eq $DefaultCred) { throw "Ett standardlösenord krävs." }
$AdminPass = $DefaultCred.GetNetworkCredential().Password

$LogFile = "$VMLocation\VM-Build-Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host $Message -ForegroundColor $Color
    "$Timestamp  $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "===== ZERO-TOUCH-KÖRNING STARTAD (v7 Sekventiell) =====" "Cyan"
Write-Log "Loggfil (värden): $LogFile"

# ==========================================
# 1b. GLOBALA FRÅGOR
# ==========================================
Write-Host ""
$DomainInput = Read-Host "Vad heter din Active Directory-domän? (Enter = foretaget.local)"
$DomainName  = if ([string]::IsNullOrWhiteSpace($DomainInput)) { "foretaget.local" } else { $DomainInput }

[int]$VMCount = Read-Host "Hur många VM vill du skapa?"
if ($VMCount -lt 1) { throw "Du måste ange minst 1." }

# ==========================================
# 1c. TILLGÄNGLIGA SERVERROLLER
# ==========================================
$RoleList = @(
    [PSCustomObject]@{ ID = 1; Display = "Active Directory Domain Services (befordras automatiskt)"; Feature = "AD-Domain-Services" },
    [PSCustomObject]@{ ID = 2; Display = "DNS Server";                                               Feature = "DNS" },
    [PSCustomObject]@{ ID = 3; Display = "DHCP Server";                                              Feature = "DHCP" },
    [PSCustomObject]@{ ID = 4; Display = "Web Server (IIS)";                                         Feature = "Web-Server" },
    [PSCustomObject]@{ ID = 5; Display = "File Server";                                              Feature = "FS-FileServer" },
    [PSCustomObject]@{ ID = 6; Display = "Print Server";                                             Feature = "Print-Server" },
    [PSCustomObject]@{ ID = 7; Display = "Remote Desktop Services (Labb: Host, Broker, Web)";        Feature = @("RDS-RD-Server", "RDS-Connection-Broker", "RDS-Web-Access") },
    [PSCustomObject]@{ ID = 8; Display = "Windows Server Update Services";                           Feature = "UpdateServices" }
)

# ==========================================
# 2. SAMLA IN INSTÄLLNINGAR PER VM
# ==========================================
$IPParts = $BaseIP.Split(".")
$VMConfigs = @()

for ($i = 1; $i -le $VMCount; $i++) {
    Write-Host ""
    Write-Host "--- VM $i av $VMCount ---" -ForegroundColor Cyan

    $DefaultName = "SRV-{0:D2}" -f $i
    $Name = Read-Host "  Namn (Enter = $DefaultName)"
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $DefaultName }
    if ($VMConfigs.Name -contains $Name) { throw "Namnet '$Name' är redan använt." }
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "Det finns redan en VM som heter '$Name' i Hyper-V." }

    $DefaultIP = "$($IPParts[0]).$($IPParts[1]).$($IPParts[2]).$([int]$IPParts[3] + $i - 1)"
    $IP = Read-Host "  IP-adress (Enter = $DefaultIP)"
    if ([string]::IsNullOrWhiteSpace($IP)) { $IP = $DefaultIP }
    if ($VMConfigs.IP -contains $IP) { throw "IP '$IP' är redan tilldelad en annan VM i denna körning." }

    $Cred = Get-Credential -UserName "Administrator" -Message "Lösenord för $Name (avbryt/tomt = standardlösenord)"
    if ($null -eq $Cred) {
        $Pass = $AdminPass
    } else {
        $PlainFromCred = $Cred.GetNetworkCredential().Password
        $Pass = if ([string]::IsNullOrWhiteSpace($PlainFromCred)) { $AdminPass } else { $PlainFromCred }
    }

    $MemInput  = Read-Host "  Minne i GB (Enter = $MemoryGB)"
    $Mem       = if ([string]::IsNullOrWhiteSpace($MemInput)) { $MemoryGB } else { [int]$MemInput }
    $CpuInput  = Read-Host "  Antal CPU-kärnor (Enter = $CPUCount)"
    $Cpu       = if ([string]::IsNullOrWhiteSpace($CpuInput)) { $CPUCount } else { [int]$CpuInput }
    $DiskInput = Read-Host "  Diskstorlek i GB (Enter = $DiskGB)"
    $Disk      = if ([string]::IsNullOrWhiteSpace($DiskInput)) { $DiskGB } else { [int]$DiskInput }

    $SwitchInput = Read-Host "  Hyper-V switch (Enter = $SwitchName)"
    $Switch = if ([string]::IsNullOrWhiteSpace($SwitchInput)) { $SwitchName } else { $SwitchInput }

    Write-Host "  Tillgängliga roller:"
    foreach ($R in $RoleList) { Write-Host "    $($R.ID). $($R.Display)" }
    $RoleInput = Read-Host "  Vilka roller? (kommaseparerade nummer, Enter = inga)"
    $SelectedRoles = @()
    $SelectedRoleNames = @()
    if (!([string]::IsNullOrWhiteSpace($RoleInput))) {
        foreach ($Choice in ($RoleInput -split "," | ForEach-Object { $_.Trim() })) {
            $Match = $RoleList | Where-Object { $_.ID -eq [int]$Choice }
            if ($Match) {
                $SelectedRoles += $Match.Feature
                $SelectedRoleNames += $Match.Display
            }
        }
    }

    $VMConfigs += [PSCustomObject]@{
        Name       = $Name
        IP         = $IP
        Password   = $Pass
        MemoryGB   = $Mem
        CPUCount   = $Cpu
        DiskGB     = $Disk
        Switch     = $Switch
        Roles      = $SelectedRoles
        RoleNames  = $SelectedRoleNames
        DnsServer  = $null
        JoinDomain = $false
    }
}

# ==========================================
# 2b. LÖS DOMÄNORDNING
# ==========================================
$DCConfig = $VMConfigs | Where-Object { $_.Roles -contains "AD-Domain-Services" } | Select-Object -First 1

$ExtraDCs = $VMConfigs | Where-Object { $_.Roles -contains "AD-Domain-Services" } | Select-Object -Skip 1
foreach ($Extra in $ExtraDCs) {
    Write-Host ""
    Write-Host "VARNING: '$($Extra.Name)' valde också AD DS, men bara EN ny domän kan skapas per körning." -ForegroundColor Yellow
    Write-Host "         Tar bort AD DS-rollen från '$($Extra.Name)' (behåller ev. övriga roller)." -ForegroundColor Yellow
    $Extra.Roles = @($Extra.Roles | Where-Object { $_ -ne "AD-Domain-Services" })
    $Extra.RoleNames = @($Extra.RoleNames | Where-Object { $_ -notlike "Active Directory*" })
}

$JoinDomainGlobal = $false
Write-Host ""
$JoinInput = Read-Host "Ska VM-maskinerna automatiskt gå med i domänen $DomainName? (j/n, Enter = j)"
$JoinDomainGlobal = ($JoinInput -notin @("n","N","nej","Nej"))

$ExistingDCPassword = ""
if ($JoinDomainGlobal -and !$DCConfig) {
    $DNS = Read-Host "Vilken IP-adress har din existerande domänkontrollant? (T.ex. 192.168.1.10)"
    $ExistingDCCred = Get-Credential -UserName "administrator@$DomainName" -Message "Ange domänens administratörslösenord (krävs för att maskinen ska kunna ansluta)"
    if ($null -eq $ExistingDCCred) { throw "Domänlösenord krävs för att kunna gå med i en befintlig domän." }
    $ExistingDCPassword = $ExistingDCCred.GetNetworkCredential().Password
}

foreach ($VM in $VMConfigs) {
    if ($VM.Roles -contains "AD-Domain-Services") {
        $VM.DnsServer  = "127.0.0.1"
        $VM.JoinDomain = $false
    }
    elseif ($DCConfig -and $JoinDomainGlobal) {
        $VM.DnsServer  = $DCConfig.IP
        $VM.JoinDomain = $true
    }
    elseif ($JoinDomainGlobal) {
        $VM.DnsServer  = $DNS
        $VM.JoinDomain = $true
    }
    else {
        $VM.DnsServer  = $DNS
        $VM.JoinDomain = $false
    }
}

Write-Host ""
Write-Host "===== Sammanfattning =====" -ForegroundColor Cyan
$VMConfigs | Select-Object Name, IP, DnsServer, JoinDomain, @{N="Roller";E={ if ($_.RoleNames.Count -gt 0) { $_.RoleNames -join ", " } else { "Inga" } }} | Format-Table -AutoSize -Wrap
$Confirm = Read-Host "Ser det bra ut? Fortsätt helt obevakat? (j/n)"
if ($Confirm -notin @("j","J","ja","Ja")) { Write-Host "Avbrutet av användaren."; exit }

# ==========================================
# 3. FUNKTION SOM BYGGER EN (1) SJÄLVSTYRANDE VM
# ==========================================
function New-AutonomousVM {
    param($VMConfig, $WimPath, $VMLocation, $ImageIndex, $TimeZoneID, $Subnet, $Gateway, $DomainName, $DCPassword)

    $LocalLog = New-Object System.Collections.ArrayList
    function Add-Log { param([string]$m) [void]$LocalLog.Add("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m") }

    $VMName  = $VMConfig.Name
    $VHDPath = "$VMLocation\$VMName.vhdx"
    $Success = $false

    try {
        Add-Log ">>> Bygger $VMName ($($VMConfig.IP))..."

        $DriveRoot = (Get-Item $VMLocation).PSDrive.Name
        $FreeSpaceGB = [math]::Round((Get-PSDrive -Name $DriveRoot).Free / 1GB, 1)
        $RequiredGB = $VMConfig.DiskGB + 10
        if ($FreeSpaceGB -lt $RequiredGB) { throw "För lite diskutrymme ($FreeSpaceGB GB ledigt, behöver minst $RequiredGB GB)." }

        if (Test-Path $VHDPath) { Remove-Item $VHDPath -Force }
        New-VHD -Path $VHDPath -SizeBytes ($VMConfig.DiskGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
        $VDisk = Mount-VHD -Path $VHDPath -PassThru -ErrorAction Stop
        Initialize-Disk -Number $VDisk.Number -PartitionStyle GPT -ErrorAction Stop | Out-Null

        $PartEFI = New-Partition -DiskNumber $VDisk.Number -Size 500MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter -ErrorAction Stop
        Format-Volume -Partition $PartEFI -FileSystem FAT32 -Confirm:$false -ErrorAction Stop | Out-Null
        $EFIDrive = $PartEFI.DriveLetter

        New-Partition -DiskNumber $VDisk.Number -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -ErrorAction Stop | Out-Null

        $PartWin = New-Partition -DiskNumber $VDisk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
        Format-Volume -Partition $PartWin -FileSystem NTFS -Confirm:$false -ErrorAction Stop | Out-Null
        $WinDrive = $PartWin.DriveLetter

        Add-Log "Applicerar Windows..."
        Expand-WindowsImage -ImagePath $WimPath -Index $ImageIndex -ApplyPath "$($WinDrive):\" -ErrorAction Stop | Out-Null

        $ImageBcdBoot = "$($WinDrive):\Windows\System32\bcdboot.exe"
        if (!(Test-Path $ImageBcdBoot)) { $ImageBcdBoot = "bcdboot.exe" }
        $BcdArgs = "$($WinDrive):\Windows /s $($EFIDrive): /f UEFI"
        $BcdProc = Start-Process -FilePath $ImageBcdBoot -ArgumentList $BcdArgs -Wait -PassThru -NoNewWindow
        if ($BcdProc.ExitCode -ne 0) { throw "Bootfilerna kunde inte skapas. Felkod: $($BcdProc.ExitCode)" }

        $IsDC           = ($VMConfig.Roles -contains "AD-Domain-Services")
        $JoinDomain     = [bool]$VMConfig.JoinDomain
        $RolesForScript = ($VMConfig.Roles -join "','")

        # Escapa lösenord: ' dubblas för PowerShell-strängar, XML-tecken för unattend.xml
        $PassPS  = $VMConfig.Password -replace "'", "''"
        $DCPassPS = "$DCPassword" -replace "'", "''"
        $PassXml = [System.Security.SecurityElement]::Escape($VMConfig.Password)

        $InjectedScript = @"
param([switch]`$Phase2)
`$StatusPath = "C:\ZeroTouchStatus.json"

function Write-GuestLog { param([string]`$Msg) "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  `$Msg" | Out-File -FilePath "C:\PostSetupLog.txt" -Append -Encoding UTF8 }
function Save-Status { param(`$Obj) `$Obj | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path `$StatusPath -Encoding UTF8 }
function Remove-DeploymentArtifacts {
    Remove-Item -Path "C:\Windows\Panther\unattend.xml" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ZeroTouchPhase2" -ErrorAction SilentlyContinue
}

`$Status = [ordered]@{
    VMName              = "$VMName"
    IsDomainController  = `$$IsDC
    RolesRequested      = @('$RolesForScript') | Where-Object { `$_ -ne '' }
    RolesInstalled      = @()
    ADPromotionSuccess  = `$null
    DomainJoinRequested = `$$JoinDomain
    DomainJoinSuccess   = `$null
    Completed           = `$false
    Errors              = @()
}

if (`$Phase2) {
    Write-GuestLog "===== FAS 2 (efter omstart) ====="
    if (Test-Path `$StatusPath) {
        try {
            `$Prev = Get-Content `$StatusPath -Raw | ConvertFrom-Json
            foreach (`$p in `$Prev.PSObject.Properties) { `$Status[`$p.Name] = `$p.Value }
        } catch {}
    }
    Remove-DeploymentArtifacts
    `$Status.Completed = `$true
    if (`$Status.IsDomainController)  { `$Status.ADPromotionSuccess = `$true }
    if (`$Status.DomainJoinRequested) { `$Status.DomainJoinSuccess  = `$true }
    Save-Status `$Status
    Write-GuestLog "Zero-touch klart."
    Remove-Item -Path "C:\PostSetup.ps1" -Force -ErrorAction SilentlyContinue
    exit
}

Write-GuestLog "===== FAS 1 startad ====="
Save-Status `$Status

`$Ready = `$false
`$Tries = 0
while (!`$Ready -and `$Tries -lt 40) {
    try { `$null = Get-WindowsFeature -ErrorAction Stop; `$Ready = `$true }
    catch { Start-Sleep -Seconds 15; `$Tries++ }
}

`$RolesToInstall = @('$RolesForScript') | Where-Object { `$_ -ne '' }
if (`$RolesToInstall.Count -gt 0) {
    foreach (`$Role in `$RolesToInstall) {
        try {
            `$R = Install-WindowsFeature -Name `$Role -IncludeManagementTools -ErrorAction Stop
            `$Status.RolesInstalled += [PSCustomObject]@{ Role = `$Role; Success = `$R.Success }
        } catch {
            `$Status.RolesInstalled += [PSCustomObject]@{ Role = `$Role; Success = `$false }
            `$Status.Errors += "Roll `$Role : `$(`$_.Exception.Message)"
        }
    }
}
Save-Status `$Status
"@

        if ($IsDC) {
            $InjectedScript += @"

try {
    `$SecPass = ConvertTo-SecureString '$PassPS' -AsPlainText -Force
    Install-ADDSForest -DomainName '$DomainName' -SafeModeAdministratorPassword `$SecPass -InstallDns -Force -NoReboot -ErrorAction Stop | Out-Null
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ZeroTouchPhase2" -Value 'powershell.exe -ExecutionPolicy Bypass -File C:\PostSetup.ps1 -Phase2'
    Save-Status `$Status
    Start-Process "shutdown.exe" -ArgumentList "/r /t 45 /c ""Zero-touch: slutfor AD DS"" /f" -NoNewWindow
    Write-GuestLog "AD DS forberedd. Omstart schemalagd om 45 sekunder."
}
catch {
    `$Status.Errors += "AD DS: `$(`$_.Exception.Message)"
    `$Status.Completed = `$true
    Save-Status `$Status
    Write-GuestLog "FEL vid AD DS: `$(`$_.Exception.Message)"
    Remove-DeploymentArtifacts
    Remove-Item -Path "C:\PostSetup.ps1" -Force -ErrorAction SilentlyContinue
}
"@
        }
        elseif ($JoinDomain) {
            $InjectedScript += @"

try {
    `$DomCred = New-Object System.Management.Automation.PSCredential ("administrator@$DomainName", (ConvertTo-SecureString '$DCPassPS' -AsPlainText -Force))
    Add-Computer -DomainName '$DomainName' -Credential `$DomCred -Force -ErrorAction Stop
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ZeroTouchPhase2" -Value 'powershell.exe -ExecutionPolicy Bypass -File C:\PostSetup.ps1 -Phase2'
    Save-Status `$Status
    Start-Process "shutdown.exe" -ArgumentList "/r /t 45 /c ""Zero-touch: domananslutning"" /f" -NoNewWindow
    Write-GuestLog "Domänanslutning lyckades. Omstart schemalagd."
}
catch {
    `$Status.DomainJoinSuccess = `$false
    `$Status.Completed = `$true
    `$Status.Errors += "Domananslutning: `$(`$_.Exception.Message)"
    Save-Status `$Status
    Write-GuestLog "FEL vid domananslutning: `$(`$_.Exception.Message)"
    Remove-DeploymentArtifacts
    Remove-Item -Path "C:\PostSetup.ps1" -Force -ErrorAction SilentlyContinue
}
"@
        }
        else {
            $InjectedScript += @"

`$Status.Completed = `$true
Save-Status `$Status
Remove-DeploymentArtifacts
Remove-Item -Path "C:\PostSetup.ps1" -Force -ErrorAction SilentlyContinue
"@
        }

        $XMLTemplate = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$VMName</ComputerName>
      <TimeZone>$TimeZoneID</TimeZone>
    </component>
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>041d:0000041d</InputLocale>
      <SystemLocale>sv-SE</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>sv-SE</UserLocale>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <AutoLogon>
        <Password><Value>$PassXml</Value><PlainText>true</PlainText></Password>
        <Enabled>true</Enabled><LogonCount>999</LogonCount><Username>Administrator</Username>
      </AutoLogon>
      <OOBE>
        <HideEULAPage>true</HideEULAPage><HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><NetworkLocation>Work</NetworkLocation><ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE><SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword><Value>$PassXml</Value><PlainText>true</PlainText></AdministratorPassword>
      </UserAccounts>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell -Command "New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress $($VMConfig.IP) -PrefixLength $Subnet -DefaultGateway $Gateway"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>powershell -Command "Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses $($VMConfig.DnsServer)"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>powershell -ExecutionPolicy Bypass -File C:\PostSetup.ps1</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@

        $PantherDir = "$($WinDrive):\Windows\Panther"
        if (!(Test-Path $PantherDir)) { New-Item -ItemType Directory -Path $PantherDir -ErrorAction Stop | Out-Null }
        $XMLTemplate | Set-Content -Path "$PantherDir\unattend.xml" -Encoding UTF8
        $InjectedScript | Set-Content -Path "$($WinDrive):\PostSetup.ps1" -Encoding UTF8

        Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue

        New-VM -Name $VMName -MemoryStartupBytes ($VMConfig.MemoryGB * 1GB) -SwitchName $VMConfig.Switch -Generation 2 -ErrorAction Stop | Out-Null
        Set-VMProcessor -VMName $VMName -Count $VMConfig.CPUCount
        Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath -ErrorAction Stop

        $HDD = Get-VMHardDiskDrive -VMName $VMName | Select-Object -First 1
        Set-VMFirmware -VMName $VMName -FirstBootDevice $HDD -EnableSecureBoot Off -ErrorAction Stop

        Add-Log "Klar! Startar $VMName."
        Start-VM -Name $VMName
        $Success = $true
    }
    catch {
        Add-Log "FEL: $($_.Exception.Message)"
        try {
            if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
                Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        try { Get-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Dismount-VHD -ErrorAction SilentlyContinue } catch {}
        try { if (Test-Path $VHDPath) { Remove-Item $VHDPath -Force -ErrorAction SilentlyContinue } } catch {}
        Add-Log "Städat bort ofullständig VM/disk (rollback). IP $($VMConfig.IP) är fri igen."
        $Success = $false
    }
    finally {
        Get-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Dismount-VHD -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{ Name = $VMName; Success = $Success; LogLines = $LocalLog; VMConfig = $VMConfig }
}

# ==========================================
# 3b. VÄNTA PÅ GÄSTEN VIA JSON
# ==========================================
function Wait-ForZeroTouchStatus {
    param($VMName, $AdminPass, $DomainName, $TimeoutMinutes = 20)

    $SecurePass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
    $CredLocal  = New-Object System.Management.Automation.PSCredential ("Administrator", $SecurePass)
    $CredDomain = if (![string]::IsNullOrWhiteSpace($DomainName)) { New-Object System.Management.Automation.PSCredential ("administrator@$DomainName", $SecurePass) } else { $null }

    $Deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $Attempt = 0
    $LastError = ""

    while ((Get-Date) -lt $Deadline) {
        $Attempt++
        foreach ($Cred in @($CredLocal, $CredDomain) | Where-Object { $_ }) {
            try {
                $Json = Invoke-Command -VMName $VMName -Credential $Cred -ErrorAction Stop -ScriptBlock {
                    if (Test-Path "C:\ZeroTouchStatus.json") { Get-Content "C:\ZeroTouchStatus.json" -Raw } else { $null }
                }
                if ($Json) {
                    $Status = $Json | ConvertFrom-Json
                    if ($Status.Completed) { return $Status }
                }
                $LastError = ""
                break
            } catch {
                $LastError = $_.Exception.Message
                continue
            }
        }
        if ($Attempt % 3 -eq 0) {
            $MinLeft = [int](($Deadline - (Get-Date)).TotalMinutes)
            $ErrText = if ($LastError) { " - senaste fel: $LastError" } else { " - ansluten, väntar på att gästen ska bli klar" }
            Write-Host "  ... väntar fortfarande på $VMName (försök $Attempt, ~$MinLeft min kvar)$ErrText" -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds 20
    }
    return $null
}

# ==========================================
# 4. KÖRNING
# ==========================================
Write-Log ""
Write-Log "Monterar Windows ISO..." "Cyan"
$ISO = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
$ISODrive = ($ISO | Get-Volume).DriveLetter
$WimPath = "$($ISODrive):\sources\install.wim"
if (!(Test-Path $WimPath)) { $WimPath = "$($ISODrive):\sources\install.esd" }

$Results = @()

try {
    if ($DCConfig) {
        Write-Log "Bygger domänkontrollanten $($DCConfig.Name) FÖRST..." "Cyan"
        $BuildResult = New-AutonomousVM -VMConfig $DCConfig -WimPath $WimPath -VMLocation $VMLocation -ImageIndex $ImageIndex -TimeZoneID $TimeZoneID -Subnet $Subnet -Gateway $Gateway -DomainName $DomainName -DCPassword $DCConfig.Password
        $BuildResult.LogLines | ForEach-Object { Write-Log $_ }

        if ($BuildResult.Success) {
            Write-Log "Väntar på att $($DCConfig.Name) blir en fungerande domänkontrollant (tar ca 15 min)..." "Yellow"
            $Status = Wait-ForZeroTouchStatus -VMName $DCConfig.Name -AdminPass $DCConfig.Password -DomainName $DomainName -TimeoutMinutes 30
            $Results += [PSCustomObject]@{ Namn = $DCConfig.Name; IP = $DCConfig.IP; Roll = "Domänkontrollant"; Startad = $true; GuestStatus = $Status }
        } else {
            Write-Log "Kunde inte bygga $($DCConfig.Name) - ingen domän kommer finnas för övriga VM att gå med i." "Red"
            $Results += [PSCustomObject]@{ Namn = $DCConfig.Name; IP = $DCConfig.IP; Roll = "Domänkontrollant"; Startad = $false; GuestStatus = $null }
        }
    }

    $WorkerConfigs = @(if ($DCConfig) { $VMConfigs | Where-Object { $_.Name -ne $DCConfig.Name } } else { $VMConfigs })

    if ($WorkerConfigs.Count -gt 0) {
        Write-Log ""
        Write-Log "Bygger $($WorkerConfigs.Count) övriga VM sekventiellt (en i taget)..." "Cyan"

        $DCPass = if ($DCConfig) { $DCConfig.Password } else { $ExistingDCPassword }

        foreach ($VM in $WorkerConfigs) {
            Write-Log "Startar bygge av $($VM.Name)..." "Cyan"
            $Res = New-AutonomousVM -VMConfig $VM -WimPath $WimPath -VMLocation $VMLocation -ImageIndex $ImageIndex -TimeZoneID $TimeZoneID -Subnet $Subnet -Gateway $Gateway -DomainName $DomainName -DCPassword $DCPass
            $Res.LogLines | ForEach-Object { Write-Log $_ }

            if ($Res.Success) {
                Write-Log "Väntar på att $($VM.Name) blir klar inifrån (roller/domänanslutning)..." "Yellow"
                $Status = Wait-ForZeroTouchStatus -VMName $VM.Name -AdminPass $VM.Password -DomainName $DomainName -TimeoutMinutes 20
                $Results += [PSCustomObject]@{ Namn = $VM.Name; IP = $VM.IP; Roll = ($VM.RoleNames -join ", "); Startad = $true; GuestStatus = $Status }
            } else {
                $Results += [PSCustomObject]@{ Namn = $VM.Name; IP = $VM.IP; Roll = ($VM.RoleNames -join ", "); Startad = $false; GuestStatus = $null }
            }
        }
    }
}
finally {
    Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue | Out-Null
}

# ==========================================
# 7. SLUTRAPPORT
# ==========================================
Write-Log ""
Write-Log "===== SLUTRAPPORT =====" "Cyan"

$ReportRows = foreach ($R in $Results) {
    $GuestOk = if ($R.GuestStatus) { ($R.GuestStatus.Errors.Count -eq 0) } else { $false }
    [PSCustomObject]@{
        Namn         = $R.Namn
        IP           = $R.IP
        Roll         = $R.Roll
        VM_Byggd     = $R.Startad
        Gast_Klar    = [bool]$R.GuestStatus.Completed
        Utan_Fel     = $GuestOk
        DomanStatus  = if ($R.GuestStatus.IsDomainController) { "Domänkontrollant" } elseif ($R.GuestStatus.DomainJoinRequested) { if ($R.GuestStatus.DomainJoinSuccess) { "Anslöt OK" } else { "Misslyckades" } } else { "-" }
        Fel          = if ($R.GuestStatus.Errors) { $R.GuestStatus.Errors -join "; " } else { "" }
    }
}

$ReportRows | Format-Table -AutoSize -Wrap
$ReportRows | Format-Table -AutoSize -Wrap | Out-String | Add-Content -Path $LogFile -Encoding UTF8

$HtmlPath = "$VMLocation\VM-Rapport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
$ReportRows | ConvertTo-Html -Title "Zero-Touch VM-rapport" -PreContent "<h2>Zero-Touch VM-rapport - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</h2>" | Out-File -FilePath $HtmlPath -Encoding UTF8

Write-Log "Loggfil: $LogFile"
Write-Log "HTML-rapport: $HtmlPath" "Green"
Write-Log "(Detaljerad guest-logg finns i C:\PostSetupLog.txt inne i respektive VM)"
