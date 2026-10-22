<#
.SYNOPSIS
    Allt-i-ett-meny för att sätta upp en Windows Server-labbmiljö.

.DESCRIPTION
    Samlar hela flödet för en ny labbmiljö i en meny:
      1. [Hyper-V]  Skapa en eller flera VM:ar (välj switch, resurser och ISO per VM)
      2. [Setup]    Statisk IP, DNS, IPv4-prioritet, installera AD DS/DNS/DHCP och byt datornamn
      3. [ADDS]     Installera en ny AD-skog (forest)
      4. [DHCP]     Auktorisera DHCP i AD, skapa scope och sätt gateway/DNS-options
      5. [Admin]    AD-administration: skapa OU, bygg standardstruktur,
                    importera användare från CSV (OU + GG_/LG_-grupper per avdelning)
                    och ta bort OU inklusive innehåll

    Alternativ 1 körs på Hyper-V-värden, övriga på servern som ska bli DC.

.NOTES
    Kräver: Hyper-V-modulen (alt. 1), ServerManager/ADDSDeployment/DhcpServer
    (alt. 2-4) och ActiveDirectory-modulen (alt. 5). Kör som administratör.
#>

Add-Type -AssemblyName System.Windows.Forms
Import-Module DHCPServer, ADDSDeployment, ActiveDirectory -ErrorAction SilentlyContinue

# ==============================================================================
# SEKTION 1: HJÄLPFUNKTIONER
# ==============================================================================

# Grafiskt val av en OU via en lista
function Get-SelectedOU ($Title) {
    Get-ADOrganizationalUnit -Filter * |
        Select-Object Name, DistinguishedName |
        Out-GridView -Title $Title -PassThru
}

# Skapar en OU om den inte redan finns och returnerar dess DN
function Create-OU ($Path, $Name) {
    $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
    if ($existing) { return $existing.DistinguishedName }
    try {
        $newOU = New-ADOrganizationalUnit -Name $Name -Path $Path -PassThru -ErrorAction Stop
        Write-Host "OU '$Name' skapad." -ForegroundColor Gray
        return $newOU.DistinguishedName
    } catch {
        Write-Host "Kunde inte skapa OU '$Name': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Skapar en säkerhetsgrupp (Global/DomainLocal) om den inte redan finns
function Create-ADGroup ($Name, $Scope, $Path) {
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        try {
            New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -ErrorAction Stop
            Write-Host "Grupp '$Name' skapad." -ForegroundColor Green
        } catch {
            Write-Host "Kunde inte skapa grupp '$Name'." -ForegroundColor Red
        }
    }
}

# Flexibel import av användare från CSV
function Import-Users {
    param([ValidateSet("Manual","Dept")][string]$Mode = "Manual")

    $csvPath = Read-Host "Ange sökväg till CSV-fil"
    if (-not (Test-Path $csvPath)) { Write-Host "Filen hittades inte!" -ForegroundColor Red; return }

    $users = @(Import-Csv $csvPath -Delimiter ";" -Encoding UTF8)
    if ($users.Count -eq 0) { Write-Host "CSV-filen är tom!" -ForegroundColor Yellow; return }

    Write-Host "`nKolumner som hittades i CSV: $($users[0].PSObject.Properties.Name -join ', ')" -ForegroundColor Cyan

    $colFirst = Read-Host "Kolumn för Förnamn (t.ex. GivenName)"
    $colLast  = Read-Host "Kolumn för Efternamn (t.ex. Surname)"
    $colSam   = Read-Host "Kolumn för SamAccountName (Enter för auto-namn)"
    $colDept  = if ($Mode -eq "Dept") { Read-Host "Kolumn för Avdelning" } else { "" }

    $selOU = Get-SelectedOU "Välj bas-OU för importen"
    if (-not $selOU) { return }
    $baseOUPath = $selOU.DistinguishedName
    $domainFQDN = (Get-ADDomain).DNSRoot

    $pass = Read-Host "Ange startlösenord för de nya användarna" -AsSecureString

    foreach ($u in $users) {
        $fName = $u.$colFirst
        $lName = $u.$colLast
        $dept  = if ($colDept) { $u.$colDept } else { "" }

        # Skapa SamAccountName automatiskt (små bokstäver, tvättar bort åäö)
        if ([string]::IsNullOrWhiteSpace($colSam) -or -not $u.$colSam) {
            $samRaw = "$($fName).$($lName)".ToLower()
            $sam = $samRaw -replace '[åä]','a' -replace 'ö','o' -replace '[^a-z.]',''
            if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
        } else {
            $sam = $u.$colSam
        }

        if ([string]::IsNullOrWhiteSpace($sam)) { continue }

        # Skapa UPN: förnamn.efternamn@domän (små bokstäver, utan åäö)
        $upnRaw = "$($fName).$($lName)@$($domainFQDN)".ToLower()
        $upn = $upnRaw -replace '[åä]','a' -replace 'ö','o'

        $currentPath = $baseOUPath
        if ($Mode -eq "Dept" -and $dept) {
            $deptClean = $dept -replace '[^\w\s]', ''
            $currentPath = Create-OU $baseOUPath $deptClean

            # Skapa globala och lokala grupper för avdelningen (AGDLP)
            Create-ADGroup "GG_$deptClean" "Global" $currentPath
            Create-ADGroup "LG_$deptClean" "DomainLocal" $currentPath

            # Koppla global grupp till lokal grupp
            Add-ADGroupMember -Identity "LG_$deptClean" -Members "GG_$deptClean" -ErrorAction SilentlyContinue
        }

        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            Write-Host "Skippar $sam - finns redan." -ForegroundColor Yellow
            continue
        }

        try {
            $userParams = @{
                SamAccountName        = $sam
                Name                  = "$fName $lName"
                GivenName             = $fName
                Surname               = $lName
                Path                  = $currentPath
                Enabled               = $true
                AccountPassword       = $pass
                ChangePasswordAtLogon = $true
                UserPrincipalName     = $upn
            }
            New-ADUser @userParams -ErrorAction Stop
            if ($Mode -eq "Dept" -and $dept) { Add-ADGroupMember -Identity "GG_$deptClean" -Members $sam -ErrorAction SilentlyContinue }
            Write-Host "Användare $sam skapad (UPN: $upn)" -ForegroundColor Green
        } catch { Write-Host "Fel vid $sam : $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Skapar en standardstruktur för ett nytt labbnätverk och importerar användare
function Create-FullADStructure {
    $ouName = Read-Host "Ange namn på ny huvud-OU"
    if ([string]::IsNullOrWhiteSpace($ouName)) { return }
    $rootDN = (Get-ADDomain).DistinguishedName
    $baseOUPath = Create-OU $rootDN $ouName
    if (-not $baseOUPath) { return }

    $computersOU = Create-OU $rootDN "Computers"
    if ($computersOU) {
        Create-OU $computersOU "Servers" | Out-Null
        Create-OU $computersOU "Workstations" | Out-Null
    }
    Create-OU $rootDN "ServiceAccounts" | Out-Null
    $groupsRootOU = Create-OU $rootDN "Groups"
    if ($groupsRootOU) {
        Create-OU $groupsRootOU "Global" | Out-Null
        Create-OU $groupsRootOU "Local" | Out-Null
    }
    Import-Users "Dept"
}

# Raderar en hel OU och dess innehåll (inkl. raderingsskydd)
function Remove-SelectedOU {
    $selectedOU = Get-SelectedOU "Välj den OU du vill ta bort"

    if (-not $selectedOU) {
        Write-Host "Ingen OU valdes. Avbryter." -ForegroundColor Yellow
        return
    }

    $ouDN = $selectedOU.DistinguishedName
    Write-Host "Du har valt: $ouDN" -ForegroundColor Cyan
    $confirmation = Read-Host "Är du säker på att du vill ta bort denna OU och ALLT innehåll? (Ja/Nej)"

    if ($confirmation -notin @("Ja", "ja", "J", "j")) {
        Write-Host "Åtgärden avbröts av användaren." -ForegroundColor Yellow
        return
    }

    Write-Host "Tar bort skydd mot oavsiktlig radering..." -ForegroundColor Cyan
    Get-ADOrganizationalUnit -Filter * -SearchBase $ouDN | Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false

    Write-Host "Raderar OU och allt innehåll..." -ForegroundColor Red
    Remove-ADOrganizationalUnit -Identity $ouDN -Recursive -Confirm:$false
    Write-Host "OU raderad framgångsrikt!" -ForegroundColor Green
}

# ==============================================================================
# SEKTION 2: HUVUDMODULER
# ==============================================================================

# Skapar virtuella maskiner i Hyper-V
function Run-HyperV {
    $VMHostSettings = Get-VMHost
    $VMBasePath  = $VMHostSettings.VirtualMachinePath
    $VHDBasePath = $VMHostSettings.VirtualHardDiskPath

    $SwitchName = (Get-VMSwitch | Out-GridView -Title "Välj Switch" -PassThru).Name
    if (-not $SwitchName) { return }

    $VMCount = [int](Read-Host "Antal VM")
    $Memory  = [int](Read-Host "Minne (GB)") * 1GB
    $CPUs    = [int](Read-Host "Antal CPU")
    $Disk    = [int](Read-Host "Disk (GB)") * 1GB

    for ($i = 1; $i -le $VMCount; $i++) {
        $VMName = Read-Host "Namn för VM #$i"
        $OF = New-Object System.Windows.Forms.OpenFileDialog
        $OF.Title  = "Välj ISO-fil för $VMName"
        $OF.Filter = "ISO files (*.iso)|*.iso"
        $ISO = if ($OF.ShowDialog() -eq "OK") { $OF.FileName } else { $null }

        try {
            New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $Memory -Path $VMBasePath -SwitchName $SwitchName -ErrorAction Stop | Out-Null
            Set-VMProcessor -VMName $VMName -Count $CPUs
            $VHD = Join-Path $VHDBasePath "$VMName.vhdx"
            New-VHD -Path $VHD -SizeBytes $Disk -Dynamic | Out-Null
            Add-VMHardDiskDrive -VMName $VMName -Path $VHD
            if ($ISO) {
                Add-VMDvdDrive -VMName $VMName -Path $ISO
                Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)
            }
            Write-Host "$VMName skapad!" -ForegroundColor Green
        } catch { Write-Host "Fel vid skapande av $VMName : $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Grundläggande serverinställningar och installation av roller
function Run-ServerSetup {
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $iface = $adapter.InterfaceAlias

    $ip = Read-Host "IP-adress"; $pref = Read-Host "Prefix (t.ex. 24)"; $gw = Read-Host "Gateway"
    Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceAlias $iface -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $ip -PrefixLength $pref -DefaultGateway $gw
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses $ip

    Set-NetIPInterface -InterfaceAlias $iface -AddressFamily IPv6 -RouterDiscovery Disabled
    Set-NetIPInterface -InterfaceAlias $iface -AddressFamily IPv4 -InterfaceMetric 10

    Write-Host "Installerar AD DS, DNS och DHCP..." -ForegroundColor Yellow
    Install-WindowsFeature AD-Domain-Services, DNS, DHCP -IncludeManagementTools

    Write-Host "Kör DHCP Post-Deployment (säkerhetsgrupper)..." -ForegroundColor Yellow
    netsh dhcp add securitygroups | Out-Null

    $newName = Read-Host "Nytt datornamn"
    if ($newName -and $env:COMPUTERNAME -ne $newName) {
        Rename-Computer -NewName $newName -Force
        Write-Host "Datornamn ändrat. Startar om..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5; Restart-Computer
    }
}

# Installerar en ny Active Directory-skog
function Run-ADForest {
    $dom  = Read-Host "Domännamn (ex: lab.local)"
    $pass = Read-Host "DSRM-lösenord" -AsSecureString
    Install-ADDSForest -DomainName $dom -SafeModeAdministratorPassword $pass -InstallDNS -Force
}

# Auktoriserar DHCP i AD och skapar ett scope
function Run-DHCPConfig {
    Write-Host "Auktoriserar DHCP i AD..." -ForegroundColor Yellow
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
    $domain = Get-ADDomain
    $fqdn = "$env:COMPUTERNAME.$($domain.DNSRoot)"

    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $ip -ErrorAction SilentlyContinue

    $sName = Read-Host "Scope-namn"; $sStart = Read-Host "Start-IP"; $sEnd = Read-Host "Slut-IP"; $sMask = Read-Host "Mask"
    $scope = Add-DhcpServerv4Scope -Name $sName -StartRange $sStart -EndRange $sEnd -SubnetMask $sMask -State Active -PassThru

    $sGW = Read-Host "Gateway"; $sDNS = Read-Host "DNS-server"
    Set-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -Router $sGW -DnsServer $sDNS -DnsDomain $domain.DNSRoot
    Write-Host "DHCP aktiverat!" -ForegroundColor Green
}

# Undermeny för AD-administration
function Run-ADAdminMenu {
    while ($true) {
        Clear-Host
        Write-Host "=== AD ADMINISTRATION SYSTEM ===" -ForegroundColor Cyan
        Write-Host "1: Skapa OU i rot          | 2: Skapa under-OU"
        Write-Host "3: Bygg full AD-struktur   | 4: TA BORT OU (inkl. innehåll)"
        Write-Host "5: Importera CSV (OU + grupper per avdelning)"
        Write-Host "B: Gå tillbaka"

        $c = Read-Host "Val"
        if ($c.ToUpper() -eq "B") { break }
        switch ($c) {
            "1" { Create-OU (Get-ADDomain).DistinguishedName (Read-Host "Namn") | Out-Null }
            "2" { $p = Get-SelectedOU "Välj förälder"; if ($p) { Create-OU $p.DistinguishedName (Read-Host "Namn") | Out-Null } }
            "3" { Create-FullADStructure }
            "4" { Remove-SelectedOU }
            "5" { Import-Users "Dept" }
        }
        Read-Host "Klar. Enter..."
    }
}

# ==============================================================================
# HUVUDMENY
# ==============================================================================

while ($true) {
    Clear-Host
    Write-Host "================ MASTER LAB TOOLKIT ================" -ForegroundColor Magenta
    Write-Host "1. [Hyper-V]  Skapa VM:ar (ISO-val per maskin)"
    Write-Host "2. [Setup]    IP, Roller & DHCP Post-Deploy"
    Write-Host "3. [ADDS]     Installera AD Forest"
    Write-Host "4. [DHCP]     Auktorisera & Aktivera Scope"
    Write-Host "5. [Admin]    Full AD Administration (OU/CSV)"
    Write-Host "Q. Avsluta"
    Write-Host "===================================================="

    $ans = Read-Host "Välj alternativ"
    switch ($ans.ToUpper()) {
        "1" { Run-HyperV }
        "2" { Run-ServerSetup }
        "3" { Run-ADForest }
        "4" { Run-DHCPConfig }
        "5" { Run-ADAdminMenu }
        "Q" { exit }
    }
}
