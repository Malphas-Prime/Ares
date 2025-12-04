# Example: use winget to install core apps
Write-Host "Installing base applications..." -ForegroundColor Cyan

$apps = @(
    "Google.Chrome",
    "7zip.7zip",
    "Adobe.Acrobat.Reader.64-bit",
    "Microsoft.VisualStudioCode",
    "Notepad++.Notepad++"
)

foreach ($app in $apps) {
    Write-Host "Installing $app..."
    try {
        winget install --id $app -e --silent -h 0
    } catch {
        Write-Warning "Failed to install $app: $_"
    }
}

Write-Host "Base app installation complete." -ForegroundColor Green

