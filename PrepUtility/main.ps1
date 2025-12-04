param(
    [switch]$DevMode # optional: run from local folder for testing
)

# ---------------------------
# Config: where modules live
# ---------------------------
if ($DevMode) {
    $Global:ModuleBase = Split-Path -Parent $PSCommandPath
} else {
    # Raw GitHub URL, or your own server
    $Global:ModuleBase = "https://raw.githubusercontent.com/YourUser/PrepUtility/main"
}

function Get-RemoteScript {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ($DevMode) {
        return Get-Content -Raw -Path (Join-Path $ModuleBase $RelativePath)
    } else {
        $url = "$ModuleBase/$RelativePath"
        Write-Host "Downloading: $url"
        return (Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop).Content
    }
}

# ---------------------------
# Define “tasks” for the GUI
# ---------------------------
$Global:PrepTasks = @(
    [pscustomobject]@{
        Name        = "Install Base Apps"
        Description = "Install browser, 7-Zip, PDF reader, etc."
        ScriptPath  = "modules/01-Install-BaseApps.ps1"
    }
    [pscustomobject]@{
        Name        = "Remove OEM Bloat"
        Description = "Remove pre-installed OEM crapware and UWP junk."
        ScriptPath  = "modules/02-Remove-Bloat.ps1"
    }
    [pscustomobject]@{
        Name        = "Apply Windows Defaults"
        Description = "Set power settings, Explorer options, taskbar, etc."
        ScriptPath  = "modules/03-Set-Defaults.ps1"
    }
    [pscustomobject]@{
        Name        = "Join Domain / Configure User"
        Description = "Join domain, set local admin, rename PC."
        ScriptPath  = "modules/10-Join-Domain.ps1"
    }
    [pscustomobject]@{
        Name        = "Install RMM / AV"
        Description = "Install your RMM agent and security tools."
        ScriptPath  = "modules/20-Install-RMM.ps1"
    }
)

# ---------------------------
# Simple WPF GUI via XAML
# ---------------------------
Add-Type -AssemblyName PresentationFramework

$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Client PC Prep Utility"
        Height="450" Width="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Select tasks to run:" FontSize="18" Margin="0,0,0,10" />

        <ListView Grid.Row="1" Name="TaskList" SelectionMode="Extended">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Run" Width="50">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}" />
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Task" DisplayMemberBinding="{Binding Name}" Width="200"/>
                    <GridViewColumn Header="Description" DisplayMemberBinding="{Binding Description}" Width="*" />
                    <GridViewColumn Header="Status" DisplayMemberBinding="{Binding Status}" Width="120" />
                </GridView>
            </ListView.View>
        </ListView>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <TextBlock Name="StatusText" VerticalAlignment="Center" Margin="0,0,10,0" />
            <Button Name="RunButton" Width="120" Margin="0,0,5,0">Run Selected</Button>
            <Button Name="CloseButton" Width="80">Close</Button>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

$TaskList   = $Window.FindName("TaskList")
$RunButton  = $Window.FindName("RunButton")
$CloseButton= $Window.FindName("CloseButton")
$StatusText = $Window.FindName("StatusText")

# Bind tasks to the ListView
$TaskList.ItemsSource = $PrepTasks

# Add extra properties for GUI
foreach ($t in $PrepTasks) {
    $t | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false
    $t | Add-Member -NotePropertyName Status     -NotePropertyValue ""
}

# ---------------------------
# Logic to run selected tasks
# ---------------------------
$RunButton.Add_Click({
    $selected = $PrepTasks | Where-Object IsSelected

    if (-not $selected) {
        [System.Windows.MessageBox]::Show("No tasks selected.","Info",'OK','Information') | Out-Null
        return
    }

    $RunButton.IsEnabled = $false
    $StatusText.Text = "Running tasks..."

    foreach ($task in $selected) {
        $task.Status = "Running..."
        $TaskList.Items.Refresh()

        try {
            $scriptContent = Get-RemoteScript -RelativePath $task.ScriptPath
            # Run in its own scope; you can pass parameters if needed
            & ([scriptblock]::Create($scriptContent))
            $task.Status = "Completed"
        }
        catch {
            $task.Status = "Failed"
            Write-Warning "Task '$($task.Name)' failed: $_"
        }

        $TaskList.Items.Refresh()
    }

    $StatusText.Text = "All selected tasks finished."
    $RunButton.IsEnabled = $true
})

$CloseButton.Add_Click({
    $Window.Close()
})

# Recommended: require admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    [System.Windows.MessageBox]::Show("Run PowerShell as Administrator for best results.","Warning",'OK','Warning') | Out-Null
}

$Window.Topmost = $true
$Window.ShowDialog() | Out-Null

