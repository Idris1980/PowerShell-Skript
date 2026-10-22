# Fusklapp: Active Directory & Windows Server

Korta, användbara kommandon. Byt ut exempelvärden (`lab.local`, IP-adresser, namn) mot din miljö.

## Nätverk

```powershell
# Visa nätverkskort
Get-NetAdapter

# Sätt fast IP och gateway
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.5 -PrefixLength 24 -DefaultGateway 192.168.1.1

# Sätt DNS-server
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.10

# Byt datornamn
Rename-Computer -NewName "SRV01" -Restart
```

## Roller och domän

```powershell
# Installera flera roller på en gång
Install-WindowsFeature -Name AD-Domain-Services, DHCP, DNS -IncludeManagementTools

# Anslut en dator till domänen
Add-Computer -DomainName "lab.local" -Credential LAB\Administrator -Restart

# Domän- och DC-information
Get-ADDomain
Get-ADDomainController -Identity "DC01"
```

## Fjärrhantering och brandvägg

```powershell
# Tillåt PowerShell Remoting
Enable-PSRemoting -Force

# Tillåt Server Manager-fjärrhantering
Configure-SMRemoting.exe -Enable

# Öppna brandväggsregler för fjärrhantering och fildelning
Set-NetFirewallRule -DisplayGroup "File and Printer Sharing"   -Enabled True
Set-NetFirewallRule -DisplayGroup "Remote Event Log Management" -Enabled True
Set-NetFirewallRule -DisplayGroup "Remote Service Management"   -Enabled True
Set-NetFirewallRule -DisplayGroup "Remote Volume Management"    -Enabled True
```

## Användare och grupper

```powershell
# Lista alla användare i en OU
Get-ADUser -SearchBase "OU=Users,DC=lab,DC=local" -Filter *

# Lägg till användare i en grupp
Add-ADGroupMember -Identity "GG_IT" -Members "anna.andersson"

# Importera användare från CSV (kolumner: SamAccountName,GivenName,Surname,DisplayName)
$pw = Read-Host "Startlösenord" -AsSecureString
Import-Csv -Path "C:\Temp\users.csv" | ForEach-Object {
    New-ADUser -Name $_.DisplayName `
               -SamAccountName $_.SamAccountName `
               -GivenName $_.GivenName `
               -Surname $_.Surname `
               -DisplayName $_.DisplayName `
               -AccountPassword $pw `
               -ChangePasswordAtLogon $true `
               -Path "OU=Users,DC=lab,DC=local" `
               -Enabled $true
}
```

## Organisationsenheter (OU)

```powershell
# Skapa en OU i domänens rot
New-ADOrganizationalUnit -Name "Users" -Path "DC=lab,DC=local"

# Skapa OU:er från CSV
# ous.csv:
#   Name,Path
#   Users,"DC=lab,DC=local"
#   Staff,"OU=Users,DC=lab,DC=local"
Import-Csv -Path "C:\Temp\ous.csv" | ForEach-Object {
    New-ADOrganizationalUnit -Name $_.Name -Path $_.Path
}
```

> Tänk på ordningen i CSV-filen: förälder-OU:n måste skapas före sina under-OU:er.

## Grupprinciper

```powershell
# Se vilka GPO:er som tillämpas på aktuell användare/dator (HTML-rapport)
gpresult /h "C:\Temp\gpo_result.html" /f

# Tvinga uppdatering av grupprinciper
gpupdate /force
```
