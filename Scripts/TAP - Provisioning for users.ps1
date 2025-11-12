# Install Microsoft Graph module if needed
#Install-Module Microsoft.Graph -Scope CurrentUser -Force
#Import-Module Microsoft.Graph

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All"

# Define list of users (UPNs or Object IDs)
$users = @(
    
<"USER@domain.com">#ADD Users here



)

# Set TAP parameters
$startTime = (Get-Date).ToUniversalTime()
$endTime = $startTime.AddHours(72)  #72 hour TAP
$lengthInMinutes = 4320 #72x60

# Store results
$tapResults = @()

foreach ($user in $users) {
    try {
        $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user -BodyParameter @{
            StartDateTime = $startTime
            EndDateTime = $endTime
            LifetimeInMinutes = $lengthInMinutes
            IsUsableOnce = $false
        }

        $tapResults += [PSCustomObject]@{
            User  = $user
            TAP   = $tap.TemporaryAccessPass
            Expiry = $tap.EndDateTime
        }
    } catch {
        Write-Warning "Failed to create TAP for $user : $_"
        $tapResults += [PSCustomObject]@{
            User  = $user
            TAP   = "Error"
            Expiry = "N/A"
        }
    }
}

# Output results
$tapResults | Format-Table -AutoSize
$tapResults | Export-Csv -Path "TAP_Codes.csv" -NoTypeInformation

Write-Host "✅ TAP codes generated and saved to TAP_Codes.csv"