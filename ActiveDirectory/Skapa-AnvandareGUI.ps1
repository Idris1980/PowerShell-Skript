<#
.SYNOPSIS
    Enkelt grafiskt formulär (WinForms) för att skapa en AD-användare.

.DESCRIPTION
    Formuläret låter dig fylla i förnamn, efternamn, SamAccountName,
    visningsnamn och lösenord, välja OU från en lista över alla OU:er i
    domänen och valfritt lägga användaren i en grupp. Det går även att
    välja "måste byta lösenord" och "lösenordet går aldrig ut".
    UPN sätts automatiskt till SamAccountName@<domänen>.

.NOTES
    Kräver: ActiveDirectory-modulen och grafiskt gränssnitt.
    Grupplistan fylls från AD:s säkerhetsgrupper.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module ActiveDirectory

$upnSuffix = (Get-ADDomain).DNSRoot

# ---------- Hämta OUs ----------
$ouList = Get-ADOrganizationalUnit -Filter * |
          Select-Object -ExpandProperty DistinguishedName |
          Sort-Object

# ---------- Hämta säkerhetsgrupper ----------
$groupList = Get-ADGroup -Filter "GroupCategory -eq 'Security'" |
             Select-Object -ExpandProperty Name |
             Sort-Object

# ---------- Fönster ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Skapa AD-användare - GUI"
$form.Size = New-Object System.Drawing.Size(450, 500)
$form.StartPosition = "CenterScreen"

# -------------------- Labels & Textfält --------------------

# Förnamn
$lblFN = New-Object System.Windows.Forms.Label
$lblFN.Text = "Förnamn:"
$lblFN.Location = "10,20"
$form.Controls.Add($lblFN)

$txtFN = New-Object System.Windows.Forms.TextBox
$txtFN.Location = "150,20"
$form.Controls.Add($txtFN)

# Efternamn
$lblLN = New-Object System.Windows.Forms.Label
$lblLN.Text = "Efternamn:"
$lblLN.Location = "10,60"
$form.Controls.Add($lblLN)

$txtLN = New-Object System.Windows.Forms.TextBox
$txtLN.Location = "150,60"
$form.Controls.Add($txtLN)

# SamAccountName
$lblSAM = New-Object System.Windows.Forms.Label
$lblSAM.Text = "SamAccountName:"
$lblSAM.Location = "10,100"
$form.Controls.Add($lblSAM)

$txtSAM = New-Object System.Windows.Forms.TextBox
$txtSAM.Location = "150,100"
$form.Controls.Add($txtSAM)

# DisplayName
$lblDN = New-Object System.Windows.Forms.Label
$lblDN.Text = "DisplayName:"
$lblDN.Location = "10,140"
$form.Controls.Add($lblDN)

$txtDN = New-Object System.Windows.Forms.TextBox
$txtDN.Location = "150,140"
$form.Controls.Add($txtDN)


# -------------------- Lösenord --------------------
$lblPW = New-Object System.Windows.Forms.Label
$lblPW.Text = "Lösenord:"
$lblPW.Location = "10,180"
$form.Controls.Add($lblPW)

$txtPW = New-Object System.Windows.Forms.TextBox
$txtPW.Location = "150,180"
$txtPW.UseSystemPasswordChar = $true
$form.Controls.Add($txtPW)


# -------------------- Checkboxar --------------------
$chkChange = New-Object System.Windows.Forms.CheckBox
$chkChange.Text = "Must change password at next logon"
$chkChange.Location = "150,220"
$chkChange.Width = 250
$chkChange.Checked = $true
$form.Controls.Add($chkChange)

$chkNeverExpire = New-Object System.Windows.Forms.CheckBox
$chkNeverExpire.Text = "Password never expires"
$chkNeverExpire.Location = "150,250"
$chkNeverExpire.Width = 250
$form.Controls.Add($chkNeverExpire)


# -------------------- Dropdown för OU --------------------
$lblOU = New-Object System.Windows.Forms.Label
$lblOU.Text = "Välj OU:"
$lblOU.Location = "10,290"
$form.Controls.Add($lblOU)

$cbOU = New-Object System.Windows.Forms.ComboBox
$cbOU.Location = "150,290"
$cbOU.Width = 250
$cbOU.DropDownStyle = "DropDownList"
$cbOU.Items.AddRange([object[]]$ouList)
$form.Controls.Add($cbOU)

# -------------------- Dropdown för grupp --------------------
$lblGR = New-Object System.Windows.Forms.Label
$lblGR.Text = "Lägg till i grupp:"
$lblGR.Location = "10,330"
$form.Controls.Add($lblGR)

$cbGroup = New-Object System.Windows.Forms.ComboBox
$cbGroup.Location = "150,330"
$cbGroup.Width = 250
$cbGroup.DropDownStyle = "DropDownList"
$cbGroup.Items.AddRange([object[]]$groupList)
$form.Controls.Add($cbGroup)


# -------------------- Skapa-knapp --------------------
$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Text = "Skapa användare"
$btnCreate.Location = "150,380"
$btnCreate.Width = 150
$form.Controls.Add($btnCreate)


# -------------------- Funktion när knappen trycks --------------------
$btnCreate.Add_Click({

    try {
        if ([string]::IsNullOrWhiteSpace($txtSAM.Text) -or -not $cbOU.SelectedItem) {
            throw "SamAccountName och OU måste fyllas i."
        }

        $securePW = ConvertTo-SecureString $txtPW.Text -AsPlainText -Force

        # Name är obligatoriskt för New-ADUser - använd visningsnamnet eller för- och efternamn
        $fullName = if ($txtDN.Text) { $txtDN.Text } else { "$($txtFN.Text) $($txtLN.Text)".Trim() }

        # Skapa användaren
        New-ADUser `
            -Name $fullName `
            -GivenName $txtFN.Text `
            -Surname $txtLN.Text `
            -SamAccountName $txtSAM.Text `
            -UserPrincipalName "$($txtSAM.Text)@$upnSuffix" `
            -DisplayName $fullName `
            -AccountPassword $securePW `
            -Path $cbOU.SelectedItem `
            -Enabled $true `
            -ChangePasswordAtLogon $chkChange.Checked `
            -PasswordNeverExpires $chkNeverExpire.Checked `
            -ErrorAction Stop

        # Lägg till grupp
        if ($cbGroup.SelectedItem) {
            Add-ADGroupMember -Identity $cbGroup.SelectedItem -Members $txtSAM.Text
        }

        [System.Windows.Forms.MessageBox]::Show("Användaren skapades utan problem!", "KLART")
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Fel: $($_.Exception.Message)", "ERROR")
    }

})

# -------------------- Visa GUI --------------------
[void]$form.ShowDialog()
