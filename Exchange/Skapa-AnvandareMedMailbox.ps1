<#
.SYNOPSIS
    Interaktiv provisionering av EN användare: AD-konto, mailbox, delad postlåda, distributionsgrupp och AD-grupper.

.DESCRIPTION
    Skriptet frågar steg för steg och visar en sammanfattning innan något görs:
      1. Välj OU (numrerad lista över alla OU:er)
      2. Välj e-postdomän (numrerad lista över accepterade domäner)
      3. Ange för- och efternamn -> användarnamn fornamn.efternamn
      4. Ange delad postlåda (skapas om den saknas) – användaren får
         Full Access (med automapping) och Send As
      5. Ange distributionsgrupp (skapas om den saknas) – användaren läggs till
      6. Välj valfritt antal AD-grupper att lägga användaren i
    Befintliga objekt återanvänds, så skriptet kan köras flera gånger.

.NOTES
    Kör i Exchange Management Shell (Exchange 2016/2019 on-prem).
    Kräver även ActiveDirectory-modulen.
#>

Import-Module ActiveDirectory

Write-Host "`n=== PROVISIONERING: AD + EXCHANGE ===" -ForegroundColor Cyan

# Hjälpfunktion: visar en numrerad lista och returnerar valt objekt
function Select-FromList {
    param([string]$Title, [object[]]$Items, [string]$Display)
    Write-Host "`n$Title"
    for ($n = 0; $n -lt $Items.Count; $n++) {
        Write-Host "$($n + 1)) $($Items[$n].$Display)"
    }
    do {
        $choice = Read-Host "Ange siffra"
    } while (-not ($choice -as [int]) -or [int]$choice -lt 1 -or [int]$choice -gt $Items.Count)
    return $Items[[int]$choice - 1]
}

# =========================
# 1. Välj OU
# =========================
$OUs = @(Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName)
$OU  = (Select-FromList -Title "Välj OU:" -Items $OUs -Display DistinguishedName).DistinguishedName

# =========================
# 2. Välj accepterad domän
# =========================
$AcceptedDomains = @(Get-AcceptedDomain | Sort-Object DomainName)
$Domain = "$((Select-FromList -Title "Välj domän:" -Items $AcceptedDomains -Display DomainName).DomainName)"

# =========================
# 3. Ange användarens namn
# =========================
$FirstName = Read-Host "`nAnge förnamn"
$LastName  = Read-Host "Ange efternamn"
$Username  = "$FirstName.$LastName".ToLower() -replace '[åä]','a' -replace 'ö','o' -replace '[^a-z0-9.]',''
if ($Username.Length -gt 20) { $Username = $Username.Substring(0, 20) }
$UPN       = "$Username@$Domain"

# =========================
# 4. Ange delad postlåda
# =========================
$SharedMailboxName  = Read-Host "`nAnge namn på delad postlåda"
$SharedMailboxAlias = Read-Host "Ange alias för delad postlåda"

# =========================
# 5. Ange distributionsgrupp
# =========================
$DistributionGroup  = Read-Host "`nAnge namn på distributionsgrupp"
$DistributionAlias  = Read-Host "Ange alias för distributionsgrupp"

# =========================
# 6. Sammanfattning & bekräftelse
# =========================
Write-Host "`n=== Sammanfattning ===" -ForegroundColor Yellow
Write-Host "Namn: $FirstName $LastName"
Write-Host "Användarnamn: $Username"
Write-Host "UPN: $UPN"
Write-Host "OU: $OU"
Write-Host "Domän: $Domain"
Write-Host "Delad postlåda: $SharedMailboxName ($SharedMailboxAlias)"
Write-Host "Distributionsgrupp: $DistributionGroup ($DistributionAlias)"

do {
    $Confirm = Read-Host "Fortsätta med provisionering? (J/N)"
} while (-not ($Confirm -in @("J","j","Y","y","N","n")))

if ($Confirm -in @("N","n")) { Write-Host "Avbrutet." -ForegroundColor Red; exit }

# =========================
# 7. Skapa AD-användare
# =========================
if (-not (Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue)) {
    Write-Host "`nSkapar AD-användare..." -ForegroundColor Green
    $Password = Read-Host "Ange startlösenord för $Username" -AsSecureString
    New-ADUser -Name "$FirstName $LastName" `
        -GivenName $FirstName `
        -Surname $LastName `
        -SamAccountName $Username `
        -UserPrincipalName $UPN `
        -Path $OU `
        -Enabled $true `
        -AccountPassword $Password `
        -ChangePasswordAtLogon $true
} else {
    Write-Host "AD-användare finns redan – hoppar över." -ForegroundColor Yellow
}

# =========================
# 8. Skapa Exchange-mailbox
# =========================
if (-not (Get-Mailbox -Identity $Username -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar mailbox..." -ForegroundColor Green
    Enable-Mailbox -Identity $Username | Out-Null
} else {
    Write-Host "Mailbox finns redan – hoppar över." -ForegroundColor Yellow
}

# =========================
# 9. Skapa / tilldela delad postlåda
# =========================
if (-not (Get-Mailbox -Identity $SharedMailboxName -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar delad postlåda..." -ForegroundColor Green
    New-Mailbox -Shared -Name $SharedMailboxName -Alias $SharedMailboxAlias | Out-Null
}

Write-Host "Tilldelar Full Access och Send As till $Username..." -ForegroundColor Green
Add-MailboxPermission -Identity $SharedMailboxName -User $Username -AccessRights FullAccess -InheritanceType All -AutoMapping $true | Out-Null
# On-prem använder Add-ADPermission för Send As (Add-RecipientPermission finns bara i Exchange Online)
Add-ADPermission -Identity $SharedMailboxName -User $Username -ExtendedRights "Send As" | Out-Null

# =========================
# 10. Skapa / uppdatera distributionsgrupp
# =========================
if (-not (Get-DistributionGroup -Identity $DistributionGroup -ErrorAction SilentlyContinue)) {
    Write-Host "Skapar distributionsgrupp..." -ForegroundColor Green
    New-DistributionGroup -Name $DistributionGroup -Alias $DistributionAlias -Type Distribution | Out-Null
}

Write-Host "Lägger till användaren i distributionsgruppen..." -ForegroundColor Green
Add-DistributionGroupMember -Identity $DistributionGroup -Member $Username -ErrorAction SilentlyContinue

# =========================
# 11. Lägg till användaren i valfria AD-grupper
# =========================
$ADGroups = @(Get-ADGroup -Filter * | Sort-Object Name)
for ($n = 0; $n -lt $ADGroups.Count; $n++) {
    Write-Host "$($n + 1)) $($ADGroups[$n].Name)"
}

$SelectedGroups = @()
Write-Host "`nVälj AD-grupper att lägga användaren i (Enter när du är klar):"
do {
    $GroupChoice = Read-Host "Ange siffra"
    if (($GroupChoice -as [int]) -and [int]$GroupChoice -ge 1 -and [int]$GroupChoice -le $ADGroups.Count) {
        $g = $ADGroups[[int]$GroupChoice - 1]
        if ($SelectedGroups -notcontains $g.DistinguishedName) {
            $SelectedGroups += $g.DistinguishedName
            Write-Host "Lagt till: $($g.Name)" -ForegroundColor Green
        } else {
            Write-Host "Gruppen är redan vald." -ForegroundColor Yellow
        }
    }
} while ($GroupChoice)

foreach ($gDN in $SelectedGroups) {
    try {
        Add-ADGroupMember -Identity $gDN -Members $Username -ErrorAction Stop
        Write-Host "Användaren $Username har lagts till i $gDN" -ForegroundColor Green
    } catch {
        Write-Host "Kunde inte lägga till i $gDN : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =========================
# KLART
# =========================
Write-Host "`n✅ Provisionering klar!" -ForegroundColor Cyan
