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
    $Global:ModuleBase = "https://raw.githubusercontent.com/Malphas-Prime/Ares/main/PrepUtility"
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
        Title="Ares Prep Utility"
        Height="480" Width="820"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        Background="#0B1120"
        FontFamily="Segoe UI"
        FontSize="13">
    <Window.Resources>
        <!-- Color palette -->
        <SolidColorBrush x:Key="BgBrush" Color="#020617" />
        <SolidColorBrush x:Key="CardBrush" Color="#020617" />
        <SolidColorBrush x:Key="CardBorderBrush" Color="#1E293B" />
        <SolidColorBrush x:Key="PrimaryBrush" Color="#38BDF8" />
        <SolidColorBrush x:Key="PrimaryBrushDark" Color="#0EA5E9" />
        <SolidColorBrush x:Key="PrimaryBrushLight" Color="#7DD3FC" />
        <SolidColorBrush x:Key="TextBrush" Color="#E5E7EB" />
        <SolidColorBrush x:Key="TextMutedBrush" Color="#9CA3AF" />
        <SolidColorBrush x:Key="RowHoverBrush" Color="#111827" />
        <SolidColorBrush x:Key="RowSelectedBrush" Color="#1D4ED8" />
        <SolidColorBrush x:Key="RowSelectedText" Color="#E5E7EB" />

        <!-- Modern button style -->
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}" />
            <Setter Property="Padding" Value="10,6" />
            <Setter Property="Margin" Value="4,0,0,0" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="{StaticResource PrimaryBrushDark}" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="{StaticResource PrimaryBrushLight}" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4" />
                                <Setter Property="Cursor" Value="Arrow" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern ListView style -->
        <Style TargetType="ListView">
            <Setter Property="Background" Value="{StaticResource CardBrush}" />
            <Setter Property="BorderBrush" Value="{StaticResource CardBorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
        </Style>

        <!-- ListViewItem style with hover/selection -->
        <Style TargetType="ListViewItem">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="Padding" Value="4" />
            <Setter Property="HorizontalContentAlignment" Value="Stretch" />
            <Setter Property="VerticalContentAlignment" Value="Center" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="SnapsToDevicePixels" Value="True" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListViewItem">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource RowHoverBrush}" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource RowSelectedBrush}" />
                                <Setter Property="Foreground" Value="{StaticResource RowSelectedText}" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Status text style -->
        <Style x:Key="StatusTextStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextMutedBrush}" />
            <Setter Property="FontSize" Value="12" />
        </Style>
    </Window.Resources>

    <Grid Background="{StaticResource BgBrush}">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="16,12,16,8">
            <TextBlock Text="Ares Prep Utility"
                       FontSize="22"
                       FontWeight="Bold"
                       Foreground="{StaticResource TextBrush}" />
            <TextBlock Text="Select the tasks you want to run on this machine."
                       Margin="0,4,0,0"
                       Foreground="{StaticResource TextMutedBrush}" />
        </StackPanel>

        <!-- Card container -->
        <Border Grid.Row="1"
                Margin="16"
                CornerRadius="10"
                Background="{StaticResource CardBrush}"
                BorderBrush="{StaticResource CardBorderBrush}"
                BorderThickness="1">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>

                <!-- Column headers (lightweight) -->
                <DockPanel Grid.Row="0" Margin="4,0,4,6">
                    <TextBlock Text="Run"
                               Width="40"
                               Foreground="{StaticResource TextMutedBrush}"
                               FontSize="12" />
                    <TextBlock Text="Task"
                               Width="220"
                               Margin="8,0,0,0"
                               Foreground="{StaticResource TextMutedBrush}"
                               FontSize="12" />
                    <TextBlock Text="Description"
                               Margin="8,0,0,0"
                               Foreground="{StaticResource TextMutedBrush}"
                               FontSize="12" />
                    <TextBlock Text="Status"
                               HorizontalAlignment="Right"
                               Foreground="{StaticResource TextMutedBrush}"
                               FontSize="12"
                               DockPanel.Dock="Right"
                               Width="90" />
                </DockPanel>

                <!-- List of tasks -->
                <ListView Grid.Row="1"
                          Name="TaskList"
                          Margin="0,0,0,0"
                          BorderThickness="0">
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Width="50">
                                <GridViewColumn.Header>
                                    <TextBlock Text="" />
                                </GridViewColumn.Header>
                                <GridViewColumn.CellTemplate>
                                    <DataTemplate>
                                        <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}"
                                                  HorizontalAlignment="Center"
                                                  VerticalAlignment="Center" />
                                    </DataTemplate>
                                </GridViewColumn.CellTemplate>
                            </GridViewColumn>

                            <GridViewColumn Header="Task"
                                            DisplayMemberBinding="{Binding Name}"
                                            Width="230" />

                            <GridViewColumn Header="Description"
                                            DisplayMemberBinding="{Binding Description}"
                                            Width="380" />

                            <GridViewColumn Header="Status"
                                            DisplayMemberBinding="{Binding Status}"
                                            Width="90" />
                        </GridView>
                    </ListView.View>
                </ListView>
            </Grid>
        </Border>

        <!-- Footer -->
        <DockPanel Grid.Row="2"
                   Margin="16,0,16,12"
                   LastChildFill="False">
            <TextBlock Name="StatusText"
                       Style="{StaticResource StatusTextStyle}"
                       VerticalAlignment="Center"
                       DockPanel.Dock="Left" />

            <StackPanel Orientation="Horizontal"
                        HorizontalAlignment="Right"
                        DockPanel.Dock="Right">
                <Button Name="RunButton" Content="Run Selected" Width="130" />
                <Button Name="CloseButton" Content="Close" Width="90" />
            </StackPanel>
        </DockPanel>
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

