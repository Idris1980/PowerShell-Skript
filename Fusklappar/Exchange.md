# Fusklapp: Exchange Server 2019 (on-prem)

Kör kommandona i **Exchange Management Shell**. Byt ut exempelvärden mot din miljö.

## Förberedelse och installation

```powershell
# Förbered AD (körs från den monterade Exchange-ISO:n)
.\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareSchema
.\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAD /OrganizationName:"Contoso"
.\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAllDomains

# Ta reda på databasnamn
Get-MailboxDatabase | Select-Object Name, Server
```

## Mailboxar

```powershell
# Aktivera mailbox för alla användare i en OU
Get-User -OrganizationalUnit "OU=Users,OU=Foretaget,DC=lab,DC=local" -RecipientTypeDetails User |
    Enable-Mailbox -Database "Mailbox Database 01"

# Skapa delad postlåda
New-Mailbox -Shared -Name "Info" -Alias info

# Ge en användare Full Access till den delade postlådan
Add-MailboxPermission -Identity "Info" -User "anna.andersson" -AccessRights FullAccess -InheritanceType All

# Ge användaren rätt att skicka som postlådan (on-prem)
Add-ADPermission -Identity "Info" -User "anna.andersson" -ExtendedRights "Send As"
```

> `Add-RecipientPermission` finns bara i Exchange Online – on-prem används `Add-ADPermission`.

## Distributionsgrupper

```powershell
# Skapa en grupp
New-DistributionGroup -Name "Alla anställda" -Alias alla -Type Distribution

# Lägg till en användare
Add-DistributionGroupMember -Identity "Alla anställda" -Member "anna.andersson"

# Lägg till alla mailboxar i en OU
Get-Mailbox -OrganizationalUnit "OU=Users,OU=Foretaget,DC=lab,DC=local" |
    ForEach-Object { Add-DistributionGroupMember -Identity "Alla anställda" -Member $_.Identity }

# Lägg till alla på en viss avdelning (Department i AD)
Get-Recipient -RecipientTypeDetails UserMailbox -Filter "Department -eq 'Sälj'" |
    ForEach-Object { Add-DistributionGroupMember -Identity "Sälj-Teamet" -Member $_.Identity }

# Visa grupp och medlemmar
Get-DistributionGroup -Identity "Alla anställda"
Get-DistributionGroupMember -Identity "Alla anställda"
```

## Resurser

```powershell
# Mötesrum som accepterar bokningar automatiskt
New-Mailbox -Name "Konferensrum 1" -Alias konf1 -Room
Set-CalendarProcessing -Identity konf1 -AutomateProcessing AutoAccept

# Utrustning
New-Mailbox -Name "Projektor 1" -Equipment
```

## Domäner och e-postadresser

```powershell
# Lägg till en accepterad domän
New-AcceptedDomain -Name "contoso.com" -DomainName "contoso.com" -DomainType Authoritative

# Lägg till en extra adress på en användare
Set-Mailbox -Identity "anna.andersson" -EmailAddresses @{Add="anna.andersson@contoso.com"}

# Sätt primär adress (stänger av e-postadresspolicyn för användaren)
Set-Mailbox -Identity "anna.andersson" -EmailAddressPolicyEnabled $false -PrimarySmtpAddress "anna.andersson@contoso.com"
```

## Transport och kvoter

```powershell
# Send Connector för utgående e-post till internet via DNS
New-SendConnector -Name "Internet-utgång" -Usage Internet -AddressSpaces "SMTP:*;1" `
    -DNSRoutingEnabled $true -SourceTransportServers "EX01"

# Kvoter på en databas
Set-MailboxDatabase "Mailbox Database 01" -IssueWarningQuota 4GB -ProhibitSendQuota 4.5GB -ProhibitSendReceiveQuota 5GB
```

## Certifikat

```powershell
# Skapa ett självsignerat SAN-certifikat
New-ExchangeCertificate -SubjectName "CN=mail.contoso.com" -FriendlyName "Exchange SAN" `
    -DomainName mail.contoso.com, autodiscover.contoso.com, EX01, EX01.lab.local `
    -PrivateKeyExportable $true

# Visa certifikat och thumbprint
Get-ExchangeCertificate | Format-List FriendlyName, Subject, Services, Thumbprint

# Aktivera certifikatet för tjänsterna
Enable-ExchangeCertificate -Thumbprint "<THUMBPRINT>" -Services IIS, SMTP

# Exportera den publika delen (.cer) till klienterna
$cert = Get-ExchangeCertificate -Thumbprint "<THUMBPRINT>"
[System.IO.File]::WriteAllBytes("C:\Temp\ExchangeSAN.cer",
    $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
```

## Felsökning

```powershell
# Testa Autodiscover/EWS för en användare
Test-OutlookWebServices -Identity anna.andersson -MailboxCredential (Get-Credential)

# Visa alla URL:er för virtuella kataloger
..\Exchange\Konfigurera-VirtuellaKataloger.ps1 -ShowOnly
```
