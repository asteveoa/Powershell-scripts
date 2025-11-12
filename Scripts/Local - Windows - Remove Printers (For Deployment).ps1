# Get all printers except "Microsoft Print to PDF"
$printers = Get-Printer | Where-Object { $_.Name -ne "Microsoft Print to PDF" }

# Loop through each printer and remove it
foreach ($printer in $printers) {
    try {
        Remove-Printer -Name $printer.Name -ErrorAction Stop
        Write-Host "Removed printer: $($printer.Name)"
    } catch {
        Write-Host "Failed to remove printer: $($printer.Name) - $_"
    }
}
