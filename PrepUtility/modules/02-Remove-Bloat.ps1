Write-Host "Removing pre-installed bloatware..." -ForegroundColor Cyan

# Example: remove common OEM / MS bloat (customize this)
$appsToRemove = @(
    "Microsoft.3DBuilder",
    "Microsoft.XboxApp",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted"
)

foreach ($pkg in $appsToRemove) {
    Get-AppxPackage -Name $pkg -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
}

Write-Host "Bloat removal complete." -ForegroundColor Green

