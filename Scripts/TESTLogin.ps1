<# 
Script: Setup-EntraUserRDP.ps1
Description:
  Enables RDP temporarily, adds Entra user access, performs setup, 
  removes RDP rights, disables RDP again, and logs everything to OneDrive.
#>

$csvPath = "C:\scripts\user_devices.csv"

# 🔹 Path to OneDrive folder (auto-resolves for current user)
$oneDrivePath = [Environment]::GetFolderPath("OneDrive")

# If script runs as SYSTEM (e.g., Intune), define a fixed OneDrive Business path instead:
# $oneDrivePath = "C:\Users\Public\OneDriveLogs"

# 🔹 Create a Logs folder in OneDrive if missing
$logDir = Join-Path $oneDrivePath "RDP_Logs"
if (!(Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

# Timestamped log file
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logDir "RDP_AuditLog_$timestamp.txt"

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "u"), $Type, $Message
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

# Import CSV
$data = Import-Csv $csvPath

Write-Log "---- Starting RDP access automation ----"

foreach ($entry in $data) {
    $computer = $entry.ComputerName
    $user = $entry.UserPrincipalName
    $dept = $entry.Department
    $pass = $entry.InitialPassword

    Write-Log "Processing $user on $computer (Dept: $dept)"

    try {
        # 1️⃣ Enable RDP
        Invoke-Command -ComputerName $computer -ScriptBlock {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        } -ErrorAction Stop
        Write-Log "✅ Enabled RDP on $computer"

        # 2️⃣ Add Entra user
        $addCmd = "net localgroup 'Remote Desktop Users' /add `"AzureAD\$user`""
        Invoke-Command -ComputerName $computer -ScriptBlock { param($cmd) Invoke-Expression $cmd } -ArgumentList $addCmd
        Write-Log "✅ Added $user to Remote Desktop Users on $computer"

        # ⚙️ 3️⃣ (Optional setup or validation tasks here)
        # Example connectivity check:
        # Invoke-Command -ComputerName $computer -ScriptBlock { Test-NetConnection -ComputerName "login.microsoftonline.com" }

        # 4️⃣ Remove RDP access for the user
        $removeCmd = "net localgroup 'Remote Desktop Users' /delete `"AzureAD\$user`""
        Invoke-Command -ComputerName $computer -ScriptBlock { param($cmd) Invoke-Expression $cmd } -ArgumentList $removeCmd
        Write-Log "🗑️ Removed $user from RDP group on $computer"

        # 5️⃣ Disable RDP again
        Invoke-Command -ComputerName $computer -ScriptBlock {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1
            Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
        }
        Write-Log "🔒 Disabled RDP on $computer"
    }
    catch {
        Write-Log "⚠️ Failed processing $computer: $_" "ERROR"
    }
}

Write-Log "---- RDP automation complete ----"
Write-Host "`nLogs saved to: $logFile" -ForegroundColor Green
