# Connect to Microsoft Graph
Connect-MgGraph -Scopes "AuditLog.Read.All", "User.Read.All"

# Set target date
$targetDate = Get-Date "11/10/2025"

# Get all users with UPN containing 'torranceasc.com'
$users = Get-MgUser -All | Where-Object {
    $_.UserPrincipalName -like "*torranceasc.com*"
}

# Prepare output array
$filteredUsers = @()

foreach ($user in $users) {
    $signIn = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -Top 1 | Sort-Object createdDateTime -Descending | Select-Object -First 1

    if ($signIn) {
        $lastSignInDate = $signIn.createdDateTime

        # Exclude users who signed in on the target date
        if ($lastSignInDate.Date -ne $targetDate.Date) {
            $filteredUsers += [PSCustomObject]@{
                UPN = $user.UserPrincipalName
                LastSignIn = $lastSignInDate
            }
        }
    } else {
        # No sign-in record found
        $filteredUsers += [PSCustomObject]@{
            UPN = $user.UserPrincipalName
            LastSignIn = "Never Signed In"
        }
    }
}

# Output results
$filteredUsers | Format-Table -AutoSize

# Optional: Export to CSV
# $filteredUsers | Export-Csv "FilteredAzureUsers.csv" -NoTypeInformation