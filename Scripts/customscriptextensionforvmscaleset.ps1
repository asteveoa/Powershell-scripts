# Install IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
$hostname = $env:COMPUTERNAME

# Create a simple HTML page
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Hello from $hostname!</h1>
</body>
</html>
"@
Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $htmlContent