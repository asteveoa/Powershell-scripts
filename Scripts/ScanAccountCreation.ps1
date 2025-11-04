#May need PowerShell 7+ on Windows (WinForms supported), Microsoft.Graph module installed
#Install-Module Microsoft.Graph 
#Install-Module ExchangeOnlineManagement -Scope CurrentUser
#Import-Module ExchangeOnlineManagement 
#ENSURE ID and NAMES TAGGED WITH #REPLACE ACTUALLY REPLACED WHEN NEEDED

#Loading fun WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#Sign in to Microsoft Graph 
$scopes = "User.Read.All","Group.ReadWrite.All","Directory.ReadWrite.All","Domain.Read.All", "Policy.ReadWrite.ConditionalAccess", "Policy.Read.All"
try {
    Connect-MgGraph -Scopes $scopes -NoWelcome
} catch {
    Connect-MgGraph -Scopes $scopes -UseDeviceAuthentication -NoWelcome
}
Get-MgContext | Out-Null

Connect-ExchangeOnline 
Connect-IPPSSession

# 3) Get domains and groups (Graph)
$conditionalAccessPolicyId = "1a71732e-2efb-416b-b3b2-96e20c0ceab0"  #REPLACE WHEN NEEDED CURRENTLY BASED OFF HIDEMYBACKGROUND TENANT
$retentionPolicyName = "Retention Policy Test"  #REPLACE WHEN NEEDED CURRENTLY BASED OFF HIDEMYBACKGROUND TENANT

# Show only verified domains via dropdown
$domainObjs = Get-MgDomain | Select-Object Id, IsVerified, IsDefault, IsInitial
$verifiedDomainObjs = @($domainObjs | Where-Object { $_.IsVerified -eq $true })
$domains = @($verifiedDomainObjs | Select-Object -ExpandProperty Id)

# Groups -> pull all and filter client-side
$allGroups = Get-MgGroup -All -ConsistencyLevel eventual
$groups = @(
    $allGroups |
    Where-Object { $_.DisplayName -match 'M365\s*F3' } |
    Select-Object -ExpandProperty DisplayName -Unique
)

# 4) Create form
$form = New-Object System.Windows.Forms.Form
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$form.Text = "Create Scan User"
$form.Size = New-Object System.Drawing.Size(600, 600)
$form.StartPosition = "CenterScreen"

$labels = @(
  "User Principal Name", "Given Name", "Surname", "Domain",
  "Display Name", "Password", "Company Name", "Department",
  "Office", "Location", "License Group"
)

$y = 40
$inputs = @{}

foreach ($label in $labels) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label
    $lbl.Location = New-Object System.Drawing.Point(50, $y)
    $lbl.Size = New-Object System.Drawing.Size(200, 40)
    $form.Controls.Add($lbl)

    if ($label -eq "Domain" -or $label -eq "License Group") {
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cb.Location = New-Object System.Drawing.Point(300, $y)
        $cb.Size = New-Object System.Drawing.Size(250, 25)
        $form.Controls.Add($cb)
        $inputs[$label] = $cb
    } else {
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(300, $y)
        $tb.Size = New-Object System.Drawing.Size(250, 25)
        if ($label -eq "Password") { $tb.UseSystemPasswordChar = $true }
        $form.Controls.Add($tb)
        $inputs[$label] = $tb
    }
    $y += 40
}

# Populate combo boxes safely (never pass $null to AddRange)
$inputs["Domain"].Items.Clear()
if ($domains.Count -gt 0) {
    $inputs["Domain"].Items.AddRange([object[]]$domains)
    $inputs["Domain"].SelectedIndex = 0
} else {
    $inputs["Domain"].Items.Add("[no domains found]")
    $inputs["Domain"].SelectedIndex = 0
}

$inputs["License Group"].Items.Clear()
if ($groups.Count -gt 0) {
    $inputs["License Group"].Items.AddRange([object[]]$groups)
    $inputs["License Group"].SelectedIndex = 0
} else {
    $inputs["License Group"].Items.Add("[no matching groups]")
    $inputs["License Group"].SelectedIndex = 0
}

# 5) Add button
$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Add User"
$btn.Location = New-Object System.Drawing.Point(200, 500)
$btn.Size = New-Object System.Drawing.Size(180, 30)
$form.Controls.Add($btn)

$btn.Add_Click({
  try {
    # inputs NEEED TO FIX SHOULDNT HAVE TO PUT IN MULTIPLE TIEMES UPN ETC
    $upnLocal     = $inputs["User Principal Name"].Text
    $domainSel    = $inputs["Domain"].Text
    $givenName    = $inputs["Given Name"].Text
    $surname      = $inputs["Surname"].Text
    $displayName  = $inputs["Display Name"].Text
    $password     = $inputs["Password"].Text
    $company      = $inputs["Company Name"].Text
    $department   = $inputs["Department"].Text
    $office       = $inputs["Office"].Text
    $location     = $inputs["Location"].Text   # e.g., "US"
    $licenseGroup = $inputs["License Group"].Text

    if ([string]::IsNullOrWhiteSpace($upnLocal) -or
        [string]::IsNullOrWhiteSpace($displayName) -or
        [string]::IsNullOrWhiteSpace($password)) {
        [System.Windows.Forms.MessageBox]::Show("UPN (left side or full), Display Name, and Password are required.","Missing data")
        return
    }

    #Can Split UPN
    if ($upnLocal -like '*@*') {
        $parts = $upnLocal.Split('@', 2)
        $upnName   = $parts[0]
        $upnDomain = $parts[1]
    } else {
        $upnName   = $upnLocal
        $upnDomain = $domainSel
    }

    # Validate against verified domains we loaded
    if ($upnDomain -eq '[no domains found]' -or -not ($domains -contains $upnDomain)) {
        [System.Windows.Forms.MessageBox]::Show("The domain '$upnDomain' is not one of your **verified** tenant domains. Choose a verified domain from the list.", "Failed")
        return
    }

    $UserPrincipalName = "$upnName@$upnDomain"
    $mailNickname = $upnName

    # Graph password profile (correct property names)
    $passwordProfile = @{
        password                      = $password
        forceChangePasswordNextSignIn = $true
    }

    # Create user
    $newUser = New-MgUser `
      -UserPrincipalName $UserPrincipalName `
      -DisplayName $displayName `
      -GivenName $givenName `
      -Surname $surname `
      -CompanyName $company `
      -Department $department `
      -OfficeLocation $office `
      -UsageLocation $location `
      -MailNickname $mailNickname `
      -PasswordProfile $passwordProfile `
      -AccountEnabled:$true
      [System.Windows.Forms.MessageBox]::Show("User '$UserPrincipalName' created.","Success")

    #Add to license group if a real group is selected (compare literally, no wildcards)
    $grp = $null
    if (-not [string]::IsNullOrWhiteSpace($licenseGroup) -and $licenseGroup -ne '[no matching groups]') {
        $escaped = $licenseGroup.Replace("'","''")
        $grp = Get-MgGroup -Filter "displayName eq '$escaped'"
    }

    if ($grp) {
       New-MgGroupMemberByRef -GroupId $grp.Id -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)" }

        [System.Windows.Forms.MessageBox]::Show("User '$UserPrincipalName' created and added to '$licenseGroup'.","Success")
    } else {
        [System.Windows.Forms.MessageBox]::Show("User created. Group '$licenseGroup' not found or not selected.","Partial Success")
    }

    

  try {
    # Get the policy by its ID
    $policy = Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $conditionalAccessPolicyId
    if (-not $policy) {
        throw "Conditional Access policy '$conditionalAccessPolicyId' not found."
    }

    # Preserve current assignments and append the user Id to excludeUsers
    $usersCond     = $policy.Conditions.Users
    $includeUsers  = @($usersCond.IncludeUsers)
    $excludeUsers  = @($usersCond.ExcludeUsers)
    $includeGroups = @($usersCond.IncludeGroups)
    $excludeGroups = @($usersCond.ExcludeGroups)
    $includeRoles  = @($usersCond.IncludeRoles)
    $excludeRoles  = @($usersCond.ExcludeRoles)

    if ($excludeUsers -notcontains $newUser.Id) {
        $excludeUsers += $newUser.Id
    }

    $body = @{
        conditions = @{
            users = @{
                includeUsers  = $includeUsers
                excludeUsers  = $excludeUsers
                includeGroups = $includeGroups
                excludeGroups = $excludeGroups
                includeRoles  = $includeRoles
                excludeRoles  = $excludeRoles
            }
        }
    }

    Update-MgIdentityConditionalAccessPolicy `
        -ConditionalAccessPolicyId $conditionalAccessPolicyId `
        -BodyParameter $body

    [System.Windows.Forms.MessageBox]::Show("User '$UserPrincipalName' added to the Conditional Access policy exclusion.","Success")
}
catch {
    [System.Windows.Forms.MessageBox]::Show("CA policy update failed: $($_.Exception.Message)","Failed")
}
# === End CA exclusion update ===

# === Exchange Mailbox modifications ===
#https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-casmailbox?view=exchange-ps

# Wait for mailbox provisioning and apply CAS settings
[System.Windows.Forms.MessageBox]::Show("Waiting 5 minutes before modifying mailbox access for '$UserPrincipalName' ","Sleeping for 5 minutes!")
$retryDelay = 300
Start-Sleep -Seconds $retryDelay
    try {
            Set-CASMailbox -Identity $UserPrincipalName `
            -ActiveSyncEnabled $true `
            -OWAEnabled $true `
            -PopEnabled $true `
            -SmtpClientAuthenticationDisabled $false `
            -ImapEnabled $false `
            -EwsEnabled $false `
            -MAPIEnabled $false `
            -ErrorAction Stop

        [System.Windows.Forms.MessageBox]::Show(
            "Exchange mailbox settings successfully applied for '$UserPrincipalName'",
            "Success"
        )
        }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Exchange mailbox settings modification failed for: $($_.Exception.Message)","Failed")
        
    }
# ==End of Exchange modifications==
#NEeed to Modify Data Retnetion Policy  for exlusion of the scanner mailbox;
#Add catch
try{
Set-RetentionCompliancePolicy -Identity $retentionPolicyName `
 -AddExchangeLocationException $UserPrincipalName `
 -ErrorAction Stop
 [System.Windows.Forms.MessageBox]::Show("User '$UserPrincipalName' added to the Retention Policy exclusion.","Success")
}
catch{
    [System.Windows.Forms.MessageBox]::Show("Retention Policy modification failed: $($_.Exception.Message)","Failed")
}
 #https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-retentioncompliancepolicy?view=exchange-ps

    #below for form catch (do not modify below)
}
  catch {
    [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Failed")
  }


})



$form.ShowDialog()
