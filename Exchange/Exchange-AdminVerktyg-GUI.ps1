<#
.SYNOPSIS
    Grafiskt administrationsverktyg (WinForms) för AD-användare och Exchange 2019 on-prem.

.DESCRIPTION
    Ett fönster med fyra flikar:
      1. AD-Användare   – skapa användare (med mailbox direkt) och ta bort användare
      2. Delad Mailbox  – skapa delade postlådor, ge/ta bort Full Access, radera
      3. Grupper        – skapa distributionsgrupper, lägg till/ta bort medlemmar, radera
      4. Exchange Special – skapa/radera mötesrum, utrustning och accepterade domäner,
                           aktivera mailbox för en användare eller en hel OU
    Alla listor uppdateras med knappen "Uppdatera alla listor" och vid flikbyte.
    Raderingar kräver bekräftelse.

.NOTES
    Kör på Exchange-servern (eller en dator med Exchange Management Tools).
    Kräver ActiveDirectory-modulen och Exchange-snapin:en.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- MODULER & EXCHANGE SNAP-IN ---
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
if (!(Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue)) {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue
}

$defaultDomain = "$((Get-AcceptedDomain | Where-Object { $_.Default -eq $true }).DomainName)"
if (!$defaultDomain) { $defaultDomain = "$env:USERDNSDOMAIN".ToLower() }

$form = New-Object System.Windows.Forms.Form
$form.Text = "Exchange Admin Tool v3.3"
$form.Size = New-Object System.Drawing.Size(950, 950)
$form.StartPosition = "CenterScreen"

# --- TOPPANEL ---
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Size = New-Object System.Drawing.Size(950, 60); $topPanel.Dock = "Top"
$form.Controls.Add($topPanel)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "UPPDATERA ALLA LISTOR (F5)"; $btnUpdate.Location = "20, 10"; $btnUpdate.Size = "250, 40"; $btnUpdate.BackColor = "LightBlue"; $btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$topPanel.Controls.Add($btnUpdate)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "STÄNG"; $btnClose.Location = "800, 10"; $btnClose.Size = "100, 40"; $btnClose.Add_Click({ $form.Close() })
$topPanel.Controls.Add($btnClose)

# --- TAB CONTROL ---
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(910, 830); $tabControl.Location = "10, 70"
$form.Controls.Add($tabControl)

function Add-Label($tab, $text, $y, $w=150) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text; $lbl.Location = "15, $y"; $lbl.Size = "$w, 20"; $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($lbl)
}
function Confirm-Action($msg) { return [System.Windows.Forms.MessageBox]::Show($msg, "Bekräfta", "YesNo", "Warning") -eq "Yes" }

# --- FLIK 1 (AD-ANVÄNDARE) ---
$tab1 = New-Object System.Windows.Forms.TabPage; $tab1.Text = "1. AD-Användare"; $tabControl.TabPages.Add($tab1)
Add-Label $tab1 "--- SKAPA NY ANVÄNDARE ---" 10 300
Add-Label $tab1 "Förnamn:" 40; $txtFN = New-Object System.Windows.Forms.TextBox; $txtFN.Location = "170, 40"; $txtFN.Size = "200, 20"; $tab1.Controls.Add($txtFN)
Add-Label $tab1 "Efternamn:" 70; $txtLN = New-Object System.Windows.Forms.TextBox; $txtLN.Location = "170, 70"; $txtLN.Size = "200, 20"; $tab1.Controls.Add($txtLN)
Add-Label $tab1 "Användarnamn:" 100; $txtUN = New-Object System.Windows.Forms.TextBox; $txtUN.Location = "170, 100"; $txtUN.Size = "200, 20"; $tab1.Controls.Add($txtUN)
Add-Label $tab1 "Lösenord:" 130; $txtPW = New-Object System.Windows.Forms.TextBox; $txtPW.Location = "170, 130"; $txtPW.Size = "200, 20"; $txtPW.UseSystemPasswordChar = $true; $tab1.Controls.Add($txtPW)
Add-Label $tab1 "Mål-OU:" 160; $comboOU = New-Object System.Windows.Forms.ComboBox; $comboOU.Location = "170, 160"; $comboOU.Size = "400, 25"; $comboOU.DropDownStyle = "DropDownList"; $tab1.Controls.Add($comboOU)
Add-Label $tab1 "Domän:" 195; $txtDom = New-Object System.Windows.Forms.TextBox; $txtDom.Location = "170, 195"; $txtDom.Size = "200, 20"; $txtDom.Text = $defaultDomain; $tab1.Controls.Add($txtDom)
$btnCreateUser = New-Object System.Windows.Forms.Button; $btnCreateUser.Text = "SKAPA ANVÄNDARE"; $btnCreateUser.Location = "170, 235"; $btnCreateUser.Size = "200, 45"; $btnCreateUser.BackColor = "LightGreen"; $tab1.Controls.Add($btnCreateUser)
Add-Label $tab1 "--- TA BORT BEFINTLIG ---" 310 300
Add-Label $tab1 "Välj användare:" 340; $comboDelUser = New-Object System.Windows.Forms.ComboBox; $comboDelUser.Location = "170, 340"; $comboDelUser.Size = "300, 25"; $comboDelUser.DropDownStyle = "DropDownList"; $tab1.Controls.Add($comboDelUser)
$btnDelUser = New-Object System.Windows.Forms.Button; $btnDelUser.Text = "RADERA VALD"; $btnDelUser.Location = "480, 338"; $btnDelUser.Size = "150, 30"; $btnDelUser.BackColor = "MistyRose"; $tab1.Controls.Add($btnDelUser)

# --- FLIK 2 (DELAD MAILBOX) ---
$tab2 = New-Object System.Windows.Forms.TabPage; $tab2.Text = "2. Delad Mailbox"; $tabControl.TabPages.Add($tab2)
Add-Label $tab2 "Välj Delad Mailbox:" 20 200
$comboShList = New-Object System.Windows.Forms.ComboBox; $comboShList.Location = "210, 20"; $comboShList.Size = "350, 25"; $comboShList.DropDownStyle = "DropDownList"; $tab2.Controls.Add($comboShList)
Add-Label $tab2 "Ny Delad (Namn):" 60 200
$txtShName = New-Object System.Windows.Forms.TextBox; $txtShName.Location = "210, 60"; $txtShName.Size = "350, 20"; $tab2.Controls.Add($txtShName)
Add-Label $tab2 "Välj Användare:" 100 200
$comboUser2 = New-Object System.Windows.Forms.ComboBox; $comboUser2.Location = "210, 100"; $comboUser2.Size = "350, 25"; $comboUser2.DropDownStyle = "DropDownList"; $tab2.Controls.Add($comboUser2)
$btnCreateShared = New-Object System.Windows.Forms.Button; $btnCreateShared.Text = "SKAPA / LÄGG TILL TILLGÅNG"; $btnCreateShared.Location = "210, 140"; $btnCreateShared.Size = "200, 40"; $btnCreateShared.BackColor = "LightGreen"; $tab2.Controls.Add($btnCreateShared)
$btnDelSh = New-Object System.Windows.Forms.Button; $btnDelSh.Text = "RADERA MAILBOX"; $btnDelSh.Location = "420, 140"; $btnDelSh.Size = "140, 40"; $btnDelSh.BackColor = "MistyRose"; $tab2.Controls.Add($btnDelSh)
Add-Label $tab2 "Användare med Full Access:" 200 300
$listSharedMembers = New-Object System.Windows.Forms.ListBox; $listSharedMembers.Location = "210, 230"; $listSharedMembers.Size = "350, 200"; $tab2.Controls.Add($listSharedMembers)
$btnRemShAcc = New-Object System.Windows.Forms.Button; $btnRemShAcc.Text = "TA BORT TILLGÅNG"; $btnRemShAcc.Location = "570, 230"; $btnRemShAcc.Size = "150, 40"; $btnRemShAcc.BackColor = "MistyRose"; $tab2.Controls.Add($btnRemShAcc)

# --- FLIK 3 (GRUPPER) ---
$tab3 = New-Object System.Windows.Forms.TabPage; $tab3.Text = "3. Grupper"; $tabControl.TabPages.Add($tab3)
Add-Label $tab3 "Välj grupp:" 20; $comboGroups = New-Object System.Windows.Forms.ComboBox; $comboGroups.Location = "170, 20"; $comboGroups.Size = "350, 25"; $comboGroups.DropDownStyle = "DropDownList"; $tab3.Controls.Add($comboGroups)
Add-Label $tab3 "Ny grupp (om skapa):" 60; $txtNewGrp = New-Object System.Windows.Forms.TextBox; $txtNewGrp.Location = "170, 60"; $txtNewGrp.Size = "350, 20"; $tab3.Controls.Add($txtNewGrp)
Add-Label $tab3 "Välj medlem:" 100; $comboUser3 = New-Object System.Windows.Forms.ComboBox; $comboUser3.Location = "170, 100"; $comboUser3.Size = "350, 25"; $comboUser3.DropDownStyle = "DropDownList"; $tab3.Controls.Add($comboUser3)
$btnAddToGrp = New-Object System.Windows.Forms.Button; $btnAddToGrp.Text = "LÄGG TILL / SKAPA"; $btnAddToGrp.Location = "170, 150"; $btnAddToGrp.Size = "170, 40"; $btnAddToGrp.BackColor = "LightGreen"; $tab3.Controls.Add($btnAddToGrp)
$btnDeleteGrpObj = New-Object System.Windows.Forms.Button; $btnDeleteGrpObj.Text = "RADERA HELA GRUPPEN"; $btnDeleteGrpObj.Location = "350, 150"; $btnDeleteGrpObj.Size = "170, 40"; $btnDeleteGrpObj.BackColor = "MistyRose"; $tab3.Controls.Add($btnDeleteGrpObj)
Add-Label $tab3 "Medlemmar:" 210 400
$listMembers = New-Object System.Windows.Forms.ListBox; $listMembers.Location = "170, 240"; $listMembers.Size = "350, 250"; $tab3.Controls.Add($listMembers)
$btnRemMem = New-Object System.Windows.Forms.Button; $btnRemMem.Text = "TA BORT MEDLEM"; $btnRemMem.Location = "540, 240"; $btnRemMem.Size = "200, 40"; $btnRemMem.BackColor = "MistyRose"; $tab3.Controls.Add($btnRemMem)

# --- FLIK 4 (EXCHANGE SPECIAL) ---
$tab4 = New-Object System.Windows.Forms.TabPage; $tab4.Text = "4. Exchange Special"; $tabControl.TabPages.Add($tab4)
Add-Label $tab4 "--- SKAPA RUM/UTRUSTNING ---" 10 300
Add-Label $tab4 "Namn (Rum/Utr):" 40; $txtSpecialName = New-Object System.Windows.Forms.TextBox; $txtSpecialName.Location = "170, 40"; $txtSpecialName.Size = "300, 20"; $tab4.Controls.Add($txtSpecialName)
Add-Label $tab4 "Mål-OU:" 70; $comboOU4 = New-Object System.Windows.Forms.ComboBox; $comboOU4.Location = "170, 70"; $comboOU4.Size = "400, 25"; $comboOU4.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboOU4)
$btnCreateRoom = New-Object System.Windows.Forms.Button; $btnCreateRoom.Text = "Skapa Rum"; $btnCreateRoom.Location = "170, 105"; $btnCreateRoom.Size = "100, 35"; $btnCreateRoom.BackColor = "LightGreen"; $tab4.Controls.Add($btnCreateRoom)
$btnCreateEquip = New-Object System.Windows.Forms.Button; $btnCreateEquip.Text = "Skapa Utr."; $btnCreateEquip.Location = "280, 105"; $btnCreateEquip.Size = "100, 35"; $btnCreateEquip.BackColor = "LightGreen"; $tab4.Controls.Add($btnCreateEquip)
Add-Label $tab4 "--- SKAPA ACCEPTERAD DOMÄN ---" 160 300
Add-Label $tab4 "Domännamn:" 190; $txtNewDomName = New-Object System.Windows.Forms.TextBox; $txtNewDomName.Location = "170, 190"; $txtNewDomName.Size = "300, 20"; $tab4.Controls.Add($txtNewDomName)
$btnCreateDom = New-Object System.Windows.Forms.Button; $btnCreateDom.Text = "Skapa Domän"; $btnCreateDom.Location = "170, 220"; $btnCreateDom.Size = "150, 35"; $btnCreateDom.BackColor = "LightGreen"; $tab4.Controls.Add($btnCreateDom)
Add-Label $tab4 "--- AKTIVERA MAIL ---" 270 400
Add-Label $tab4 "Välj OU:" 300; $comboOUEnable = New-Object System.Windows.Forms.ComboBox; $comboOUEnable.Location = "170, 300"; $comboOUEnable.Size = "400, 25"; $comboOUEnable.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboOUEnable)
$btnEnableOU = New-Object System.Windows.Forms.Button; $btnEnableOU.Text = "Skapa mail OU"; $btnEnableOU.Location = "580, 298"; $btnEnableOU.Size = "150, 30"; $btnEnableOU.BackColor = "LightGreen"; $tab4.Controls.Add($btnEnableOU)
Add-Label $tab4 "Välj User:" 340; $comboUserEnable = New-Object System.Windows.Forms.ComboBox; $comboUserEnable.Location = "170, 340"; $comboUserEnable.Size = "400, 25"; $comboUserEnable.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboUserEnable)
$btnEnableSingle = New-Object System.Windows.Forms.Button; $btnEnableSingle.Text = "Skapa Mail användare"; $btnEnableSingle.Location = "580, 338"; $btnEnableSingle.Size = "150, 30"; $btnEnableSingle.BackColor = "LightGreen"; $tab4.Controls.Add($btnEnableSingle)
Add-Label $tab4 "--- TA BORT ---" 400 100
Add-Label $tab4 "Välj Rum:" 430; $comboRooms = New-Object System.Windows.Forms.ComboBox; $comboRooms.Location = "170, 430"; $comboRooms.Size = "300, 25"; $comboRooms.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboRooms)
$btnDelR = New-Object System.Windows.Forms.Button; $btnDelR.Text = "Radera Rum"; $btnDelR.Location = "480, 428"; $btnDelR.BackColor = "MistyRose"; $tab4.Controls.Add($btnDelR)
Add-Label $tab4 "Välj Utr:" 470; $comboEquip = New-Object System.Windows.Forms.ComboBox; $comboEquip.Location = "170, 470"; $comboEquip.Size = "300, 25"; $comboEquip.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboEquip)
$btnDelE = New-Object System.Windows.Forms.Button; $btnDelE.Text = "Radera Utr."; $btnDelE.Location = "480, 468"; $btnDelE.BackColor = "MistyRose"; $tab4.Controls.Add($btnDelE)
Add-Label $tab4 "Välj Domän:" 510; $comboDoms = New-Object System.Windows.Forms.ComboBox; $comboDoms.Location = "170, 510"; $comboDoms.Size = "300, 25"; $comboDoms.DropDownStyle = "DropDownList"; $tab4.Controls.Add($comboDoms)
$btnDelD = New-Object System.Windows.Forms.Button; $btnDelD.Text = "Radera Domän"; $btnDelD.Location = "480, 508"; $btnDelD.BackColor = "MistyRose"; $tab4.Controls.Add($btnDelD)

# --- LOGIK & FIXAR ---
$btnUpdate.Add_Click({
    $users = Get-ADUser -Filter 'Enabled -eq $true' | Select-Object -ExpandProperty SamAccountName | Sort-Object
    $comboDelUser.Items.Clear(); $comboUser2.Items.Clear(); $comboUser3.Items.Clear(); $comboUserEnable.Items.Clear()
    foreach($u in $users){ [void]$comboDelUser.Items.Add($u); [void]$comboUser2.Items.Add($u); [void]$comboUser3.Items.Add($u); [void]$comboUserEnable.Items.Add($u) }
    $ous = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName | Sort-Object
    $comboOU.Items.Clear(); $comboOU4.Items.Clear(); $comboOUEnable.Items.Clear()
    foreach($o in $ous){ [void]$comboOU.Items.Add($o); [void]$comboOU4.Items.Add($o); [void]$comboOUEnable.Items.Add($o) }
    $sh = Get-Mailbox -ResultSize Unlimited | Where-Object {$_.RecipientTypeDetails -eq "SharedMailbox"} | Select-Object -ExpandProperty Name | Sort-Object
    $comboShList.Items.Clear(); foreach($s in $sh){ [void]$comboShList.Items.Add($s) }
    $gr = Get-DistributionGroup | Select-Object -ExpandProperty Name | Sort-Object
    $comboGroups.Items.Clear(); foreach($g in $gr){ [void]$comboGroups.Items.Add($g) }
    $ro = Get-Mailbox -RecipientTypeDetails RoomMailbox | Select-Object -ExpandProperty Name | Sort-Object
    $comboRooms.Items.Clear(); foreach($r in $ro){ [void]$comboRooms.Items.Add($r) }
    $eq = Get-Mailbox -RecipientTypeDetails EquipmentMailbox | Select-Object -ExpandProperty Name | Sort-Object
    $comboEquip.Items.Clear(); foreach($e in $eq){ [void]$comboEquip.Items.Add($e) }
    $do = Get-AcceptedDomain | Select-Object -ExpandProperty Name | Sort-Object
    $comboDoms.Items.Clear(); foreach($d in $do){ [void]$comboDoms.Items.Add($d) }
})

# GRUPP-LOGIK (FIXAD FÖR ATT UNDVIKA NULL-FEL)
$comboGroups.Add_SelectedIndexChanged({
    $listMembers.Items.Clear()
    if ($comboGroups.SelectedItem) {
        try {
            $m = Get-DistributionGroupMember -Identity $comboGroups.SelectedItem.ToString() | Select-Object -ExpandProperty Name | Sort-Object
            foreach($item in $m){ [void]$listMembers.Items.Add($item) }
        } catch {}
    }
})

$btnAddToGrp.Add_Click({
    try {
        if (![string]::IsNullOrEmpty($txtNewGrp.Text)) {
            New-DistributionGroup -Name $txtNewGrp.Text -Type "Distribution" -ErrorAction Stop
            if ($comboUser3.SelectedItem) { Add-DistributionGroupMember -Identity $txtNewGrp.Text -Member $comboUser3.SelectedItem.ToString() }
            $txtNewGrp.Text = ""; $btnUpdate.PerformClick()
        } elseif ($comboGroups.SelectedItem -and $comboUser3.SelectedItem) {
            Add-DistributionGroupMember -Identity $comboGroups.SelectedItem.ToString() -Member $comboUser3.SelectedItem.ToString() -ErrorAction Stop
            $btnUpdate.PerformClick()
        }
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) }
})

$btnDeleteGrpObj.Add_Click({ 
    if($comboGroups.SelectedItem -and (Confirm-Action "Radera?")){ 
        Remove-DistributionGroup $comboGroups.SelectedItem.ToString() -Confirm:$false
        $listMembers.Items.Clear()
        $btnUpdate.PerformClick() 
    } 
})

$btnRemMem.Add_Click({ 
    if ($comboGroups.SelectedItem -and $listMembers.SelectedItem) {
        Remove-DistributionGroupMember -Identity $comboGroups.SelectedItem.ToString() -Member $listMembers.SelectedItem.ToString() -Confirm:$false
        $btnUpdate.PerformClick()
    }
})

# ÖVRIG LOGIK (Samma som innan)
$comboShList.Add_SelectedIndexChanged({ $listSharedMembers.Items.Clear(); if($comboShList.SelectedItem){ try { $acc = Get-MailboxPermission -Identity $comboShList.SelectedItem.ToString() | Where-Object { ($_.User -like "*\*") -and ($_.IsInherited -eq $false) } | Select-Object -ExpandProperty User; foreach($a in $acc){ [void]$listSharedMembers.Items.Add($a) } } catch {} } })
$btnCreateShared.Add_Click({ try { if (![string]::IsNullOrEmpty($txtShName.Text)) { New-Mailbox -Name $txtShName.Text -Shared -PrimarySmtpAddress "$($txtShName.Text)@$defaultDomain" -ErrorAction Stop; if ($comboUser2.SelectedItem) { Add-MailboxPermission -Identity $txtShName.Text -User $comboUser2.SelectedItem.ToString() -AccessRights FullAccess }; $txtShName.Text = ""; $btnUpdate.PerformClick() } elseif ($comboShList.SelectedItem -and $comboUser2.SelectedItem) { Add-MailboxPermission -Identity $comboShList.SelectedItem.ToString() -User $comboUser2.SelectedItem.ToString() -AccessRights FullAccess -ErrorAction Stop; $btnUpdate.PerformClick() } } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$btnRemShAcc.Add_Click({ if ($comboShList.SelectedItem -and $listSharedMembers.SelectedItem) { Remove-MailboxPermission -Identity $comboShList.SelectedItem.ToString() -User $listSharedMembers.SelectedItem.ToString() -AccessRights FullAccess -Confirm:$false; $listSharedMembers.Items.Remove($listSharedMembers.SelectedItem); $btnUpdate.PerformClick() } })
$btnDelSh.Add_Click({ if ($comboShList.SelectedItem -and (Confirm-Action "Radera?")) { Remove-Mailbox $comboShList.SelectedItem.ToString() -Confirm:$false; $listSharedMembers.Items.Clear(); $btnUpdate.PerformClick() } })
$btnEnableOU.Add_Click({ if ($comboOUEnable.SelectedItem) { $uInOu = Get-ADUser -Filter * -SearchBase $comboOUEnable.SelectedItem.ToString(); foreach ($u in $uInOu) { Enable-Mailbox -Identity $u.SamAccountName -ErrorAction SilentlyContinue }; [System.Windows.Forms.MessageBox]::Show("Klar!") } })
$btnEnableSingle.Add_Click({ if ($comboUserEnable.SelectedItem) { Enable-Mailbox -Identity $comboUserEnable.SelectedItem.ToString(); [System.Windows.Forms.MessageBox]::Show("Klar!") } })
$btnCreateUser.Add_Click({ try { $upn = "$($txtUN.Text)@$($txtDom.Text)"; $pass = ConvertTo-SecureString $txtPW.Text -AsPlainText -Force; New-ADUser -Name "$($txtFN.Text) $($txtLN.Text)" -GivenName $txtFN.Text -Surname $txtLN.Text -SamAccountName $txtUN.Text -UserPrincipalName $upn -Path $comboOU.SelectedItem.ToString() -AccountPassword $pass -Enabled $true -ErrorAction Stop; Start-Sleep -Seconds 2; Enable-Mailbox $txtUN.Text; $btnUpdate.PerformClick() } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$btnCreateRoom.Add_Click({ try { New-Mailbox -Name $txtSpecialName.Text -Room -OrganizationalUnit $comboOU4.SelectedItem.ToString() -PrimarySmtpAddress "$($txtSpecialName.Text)@$defaultDomain" -ErrorAction Stop; $btnUpdate.PerformClick() } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$btnCreateEquip.Add_Click({ try { New-Mailbox -Name $txtSpecialName.Text -Equipment -OrganizationalUnit $comboOU4.SelectedItem.ToString() -PrimarySmtpAddress "$($txtSpecialName.Text)@$defaultDomain" -ErrorAction Stop; $btnUpdate.PerformClick() } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$btnCreateDom.Add_Click({ try { New-AcceptedDomain -Name $txtNewDomName.Text -DomainName $txtNewDomName.Text -DomainType Authoritative -ErrorAction Stop; $btnUpdate.PerformClick() } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) } })
$btnDelR.Add_Click({ if($comboRooms.SelectedItem -and (Confirm-Action "Radera?")){ Remove-Mailbox $comboRooms.SelectedItem.ToString() -Confirm:$false; $btnUpdate.PerformClick() } })
$btnDelE.Add_Click({ if($comboEquip.SelectedItem -and (Confirm-Action "Radera?")){ Remove-Mailbox $comboEquip.SelectedItem.ToString() -Confirm:$false; $btnUpdate.PerformClick() } })
$btnDelD.Add_Click({ if($comboDoms.SelectedItem -and (Confirm-Action "Radera?")){ Remove-AcceptedDomain $comboDoms.SelectedItem.ToString() -Confirm:$false; $btnUpdate.PerformClick() } })
$btnDelUser.Add_Click({ if($comboDelUser.SelectedItem -and (Confirm-Action "Radera?")){ Remove-ADUser $comboDelUser.SelectedItem.ToString() -Confirm:$false; $btnUpdate.PerformClick() } })

$tabControl.Add_SelectedIndexChanged({ $btnUpdate.PerformClick() })
& { $btnUpdate.PerformClick() }
[void]$form.ShowDialog()
