# modules/01-Install-BaseApps.ps1
# Ares Prep Utility - Base App Installer (WinGet + WPF picker)
# Runs interactively (GUI) and installs selected apps silently using winget.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework

function Test-WinGet {
    try {
        $null = & winget --version 2>$null
        return $true
    } catch {
        return $false
    }
}

function Invoke-WinGetInstall {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [string]$Source = "winget"
    )

    # Keep installs predictable across endpoints
    $args = @(
        "install",
        "--id", $Id,
        "--source", $Source,
        "--exact",
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--disable-interactivity"
    )

    # winget returns nonzero on failure; we capture output for logs.
    $out = & winget @args 2>&1
    return $out
}

# ---- App Catalog (Top ~30 common MSP/base build apps) ----
# Note: Some apps are from "msstore" or have licensing prompts; this list sticks to reliable winget ids.
# You can swap/add as needed.
$apps = @(
    @{ Name="Google Chrome";                Id="Google.Chrome";                       Source="winget"; Category="Browsers" }
    @{ Name="Mozilla Firefox";              Id="Mozilla.Firefox";                     Source="winget"; Category="Browsers" }
    @{ Name="Microsoft Edge (Stable)";      Id="Microsoft.Edge";                      Source="winget"; Category="Browsers" }

    @{ Name="7-Zip";                        Id="7zip.7zip";                           Source="winget"; Category="Utilities" }
    @{ Name="Notepad++";                    Id="Notepad++.Notepad++";                 Source="winget"; Category="Utilities" }
    @{ Name="Everything Search";            Id="voidtools.Everything";                Source="winget"; Category="Utilities" }
    @{ Name="Sysinternals Suite";           Id="Microsoft.Sysinternals";              Source="winget"; Category="Utilities" }
    @{ Name="PowerToys";                    Id="Microsoft.PowerToys";                 Source="winget"; Category="Utilities" }
    @{ Name="TreeSize Free";                Id="JAMSoftware.TreeSize.Free";           Source="winget"; Category="Utilities" }
    @{ Name="WinDirStat";                   Id="WinDirStat.WinDirStat";               Source="winget"; Category="Utilities" }
    @{ Name="VLC Media Player";             Id="VideoLAN.VLC";                        Source="winget"; Category="Utilities" }
    @{ Name="SumatraPDF";                   Id="SumatraPDF.SumatraPDF";               Source="winget"; Category="Utilities" }
    @{ Name="Adobe Acrobat Reader DC";      Id="Adobe.Acrobat.Reader.64-bit";         Source="winget"; Category="Utilities" }

    @{ Name="Teams (work or school)";       Id="Microsoft.Teams";                     Source="winget"; Category="Collaboration" }
    @{ Name="Zoom";                         Id="Zoom.Zoom";                           Source="winget"; Category="Collaboration" }
    @{ Name="Webex";                        Id="Cisco.Webex";                         Source="winget"; Category="Collaboration" }

    @{ Name="Visual Studio Code";           Id="Microsoft.VisualStudioCode";          Source="winget"; Category="Dev" }
    @{ Name="Git";                          Id="Git.Git";                             Source="winget"; Category="Dev" }
    @{ Name="Python 3";                     Id="Python.Python.3";                     Source="winget"; Category="Dev" }
    @{ Name="Node.js LTS";                  Id="OpenJS.NodeJS.LTS";                   Source="winget"; Category="Dev" }
    @{ Name="PuTTY";                        Id="PuTTY.PuTTY";                         Source="winget"; Category="Dev" }
    @{ Name="WinSCP";                       Id="WinSCP.WinSCP";                       Source="winget"; Category="Dev" }
    @{ Name="Postman";                      Id="Postman.Postman";                     Source="winget"; Category="Dev" }

    @{ Name="Wireshark";                    Id="WiresharkFoundation.Wireshark";      Source="winget"; Category="Networking" }
    @{ Name="Advanced IP Scanner";          Id="Famatech.AdvancedIPScanner";          Source="winget"; Category="Networking" }
    @{ Name="Tailscale";                    Id="Tailscale.Tailscale";                 Source="winget"; Category="Networking" }

    @{ Name="Bitwarden";                    Id="Bitwarden.Bitwarden";                 Source="winget"; Category="Security" }
    @{ Name="KeePassXC";                    Id="KeePassXCTeam.KeePassXC";             Source="winget"; Category="Security" }
    @{ Name="Malwarebytes";                 Id="Malwarebytes.Malwarebytes";           Source="winget"; Category="Security" }

    @{ Name="OneDrive";                     Id="Microsoft.OneDrive";                  Source="winget"; Category="Microsoft" }
    @{ Name="Microsoft 365 Apps (Retail)";  Id="Microsoft.Office";                    Source="winget"; Category="Microsoft" }
)

# ---- Build WPF Picker UI (inline XAML) ----
# Shows a ListView with checkbox + name + category + winget id, plus Install/Cancel buttons.
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Install Base Apps"
        Height="560"
        Width="860"
        WindowStartupLocation="CenterScreen"
        Background="#f0f0f0"
        FontFamily="Segoe UI"
        FontSize="12">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Select apps to install (WinGet will pull latest versions)"
                 FontSize="16" FontWeight="Bold" Foreground="#202020"/>
      <TextBlock Name="WinGetStatus" Text="Checking WinGet..." Margin="0,3,0,0" Foreground="#505050"/>
    </StackPanel>

    <Border Grid.Row="1" Background="White" BorderBrush="#c0c0c0" BorderThickness="1">
      <ListView Name="AppList" BorderThickness="0">
        <ListView.View>
          <GridView>
            <GridViewColumn Width="40">
              <GridViewColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding IsSelected}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </GridViewColumn.CellTemplate>
            </GridViewColumn>
            <GridViewColumn Header="App" Width="260" DisplayMemberBinding="{Binding Name}"/>
            <GridViewColumn Header="Category" Width="140" DisplayMemberBinding="{Binding Category}"/>
            <GridViewColumn Header="WinGet Id" Width="300" DisplayMemberBinding="{Binding Id}"/>
          </GridView>
        </ListView.View>
      </ListView>
    </Border>

    <TextBlock Grid.Row="2" Name="ProgressText" Margin="2,10,0,6" Foreground="#505050"/>

    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
        <Button Name="InstallButton" Content="Install Selected" Width="140" Padding="10,5" Margin="0,0,8,0"/>
        <Button Name="CancelButton" Content="Cancel" Width="90" Padding="10,5"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$appList       = $window.FindName("AppList")
$installButton = $window.FindName("InstallButton")
$cancelButton  = $window.FindName("CancelButton")
$progressText  = $window.FindName("ProgressText")
$wingetStatus  = $window.FindName("WinGetStatus")

# Data binding collection
$items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
foreach ($a in $apps) {
    $items.Add([pscustomobject]@{
        IsSelected = $false
        Name       = $a.Name
        Category   = $a.Category
        Id         = $a.Id
        Source     = $a.Source
        Status     = ""
    }) | Out-Null
}
$appList.ItemsSource = $items

# WinGet check
if (Test-WinGet) {
    $wingetStatus.Text = "WinGet detected."
    $wingetStatus.Foreground = "#2a6f2a"
} else {
    $wingetStatus.Text = "WinGet NOT found. Install 'App Installer' from Microsoft Store, then retry."
    $wingetStatus.Foreground = "#9b2c2c"
    $installButton.IsEnabled = $false
}

$cancelButton.Add_Click({ $window.Close() })

$installButton.Add_Click({
    $selected = $items | Where-Object { $_.IsSelected }
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("No apps selected.", "Info", 'OK', 'Information') | Out-Null
        return
    }

    $installButton.IsEnabled = $false
    $cancelButton.IsEnabled = $false

    $logDir = Join-Path $env:ProgramData "Ares"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logPath = Join-Path $logDir ("BaseApps-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

    $i = 0
    foreach ($app in $selected) {
        $i++
        $progressText.Text = "Installing ($i/$($selected.Count)): $($app.Name)..."
        $window.Dispatcher.Invoke([action]{})

        try {
            Add-Content -Path $logPath -Value ("`r`n==== " + $app.Name + " (" + $app.Id + ") ====")
            $out = Invoke-WinGetInstall -Id $app.Id -Name $app.Name -Source $app.Source
            $out | ForEach-Object { Add-Content -Path $logPath -Value $_ }
        }
        catch {
            Add-Content -Path $logPath -Value ("ERROR: " + $_.Exception.Message)
        }
    }

    $progressText.Text = "Done. Log: $logPath"
    $cancelButton.IsEnabled = $true
    $installButton.IsEnabled = $true

    [System.Windows.MessageBox]::Show("Selected apps processed.`n`nLog: $logPath", "Completed", 'OK', 'Information') | Out-Null
})

# Show dialog
$null = $window.ShowDialog()
