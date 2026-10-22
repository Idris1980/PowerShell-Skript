<#
.SYNOPSIS
    Interaktiv Exchange-provisionering för en hel OU: mailboxar, delad postlåda, grupp, mötesrum och domän.

.DESCRIPTION
    Frågar efter alla värden och kör sedan i ordning:
      1. Aktiverar mailbox för alla användare i OU:n som saknar en
      2. Skapar en delad postlåda (om den saknas)
      3. Ger en utvald användare Full Access (med automapping) och Send As
      4. Skapar en distributionsgrupp (om den saknas)
      5. Lägger alla användare i OU:n i distributionsgruppen
      6. Skapar ett mötesrum som automatiskt accepterar bokningar
      7. Skapar en accepterad domän (om den saknas)
      8. Sätter den utvalda användarens primära SMTP-adress till den domänen

.NOTES
    Kör i Exchange Management Shell (Exchange 2016/2019 on-prem).
#>

Write-Host "=== Interaktiv Exchange-provisionering ===" -ForegroundColor Cyan

# ===== INDATA =====
$OU            = Read-Host "Ange OU (ex: OU=Users,OU=Foretaget,DC=lab,DC=local)"
$PrimaryDomain = Read-Host "Ange primär e-postdomän (ex: contoso.com)"
$User          = Read-Host "Ange användare som ska få åtkomst (ex: fornamn.efternamn)"

$SharedMailbox = Read-Host "Namn på delad postlåda (ex: Info)"
$SharedAlias   = Read-Host "Alias för delad postlåda (ex: info)"

$RoomName  = Read-Host "Namn på mötesrum (ex: Konferensrum 1)"
$RoomAlias = Read-Host "Alias för mötesrum (ex: konf1)"

$DGName  = Read-Host "Namn på distributionsgrupp (ex: Alla anställda)"
$DGAlias = Read-Host "Alias för distributionsgrupp (ex: alla)"

$Confirm = Read-Host "Fortsätta med dessa inställningar? (J/N)"
if ($Confirm -notin @("J","j","Y","y")) {
    Write-Host "Avbrutet av användaren." -ForegroundColor Red
    exit
}

############################################
# 1. Skapa mailboxar för alla användare i OU
############################################
Write-Host "Skapar mailboxar för användare i OU..." -ForegroundColor Yellow

Get-User -OrganizationalUnit $OU -RecipientTypeDetails User |
    Where-Object { -not (Get-Mailbox $_.Identity -ErrorAction SilentlyContinue) } |
    Enable-Mailbox | Out-Null

############################################
# 2. Skapa delad postlåda
############################################
if (-not (Get-Mailbox -Identity $SharedMailbox -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar delad postlåda..." -ForegroundColor Yellow
    New-Mailbox -Shared -Name $SharedMailbox -Alias $SharedAlias | Out-Null
}

############################################
# 3. Tilldela rättigheter
############################################
Write-Host "Tilldelar rättigheter till delad postlåda..." -ForegroundColor Yellow

Add-MailboxPermission -Identity $SharedMailbox `
    -User $User `
    -AccessRights FullAccess `
    -AutoMapping $true `
    -InheritanceType All `
    -ErrorAction SilentlyContinue | Out-Null

# On-prem: Send As sätts med Add-ADPermission
Add-ADPermission -Identity $SharedMailbox `
    -User $User `
    -ExtendedRights "Send As" `
    -ErrorAction SilentlyContinue | Out-Null

############################################
# 4. Skapa distributionsgrupp
############################################
if (-not (Get-DistributionGroup -Identity $DGName -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar distributionsgrupp..." -ForegroundColor Yellow
    New-DistributionGroup -Name $DGName -Alias $DGAlias -Type Distribution | Out-Null
}

############################################
# 5. Lägg till alla användare i OU till gruppen
############################################
Write-Host "Lägger till användare i distributionsgruppen..." -ForegroundColor Yellow

Get-Mailbox -OrganizationalUnit $OU -RecipientTypeDetails UserMailbox |
    ForEach-Object {
        Add-DistributionGroupMember -Identity $DGName -Member $_.Identity -ErrorAction SilentlyContinue
    }

############################################
# 6. Skapa mötesrum
############################################
if (-not (Get-Mailbox -Identity $RoomAlias -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar mötesrum..." -ForegroundColor Yellow
    New-Mailbox -Name $RoomName -Alias $RoomAlias -Room | Out-Null
    Set-CalendarProcessing $RoomAlias -AutomateProcessing AutoAccept
}

############################################
# 7. Skapa accepterad domän
############################################
if (-not (Get-AcceptedDomain | Where-Object { "$($_.DomainName)" -eq $PrimaryDomain })) {
    Write-Host "Skapar accepterad domän..." -ForegroundColor Yellow
    New-AcceptedDomain -Name $PrimaryDomain -DomainName $PrimaryDomain -DomainType Authoritative | Out-Null
}

############################################
# 8. Sätt primär SMTP-adress
############################################
Write-Host "Uppdaterar primär SMTP-adress för $User..." -ForegroundColor Yellow

Set-Mailbox -Identity $User `
    -EmailAddressPolicyEnabled $false `
    -PrimarySmtpAddress "$User@$PrimaryDomain"

############################################
# KLART
############################################
Write-Host "=== Provisionering slutförd ===" -ForegroundColor Green
