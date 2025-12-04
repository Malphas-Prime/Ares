Ares PrepUtility

A modular, automated Windows onboarding tool for MSPs, IT departments, and system builders.

Ares PrepUtility is designed to streamline preparing new computers for clients by providing a centralized PowerShell-based GUI with selectable tasks. Each task is defined as a standalone script, allowing you to build repeatable workflows for software installation, debloating, configuration, domain setup, and more.

This project follows the same bootstrap philosophy as Chris Titus Tech’s Windows Utility, but customized for MSP workflows.

✨ Features

One-liner deployment with PowerShell (iex bootstrapper)

Modular task system (each step is its own script under /modules)

Graphical interface built using WPF

Remote script loading from GitHub using Invoke-WebRequest

Silent installations via Winget

OEM bloatware removal

Standardized Windows settings & hardening

Support for client-specific modules (RMM installer, AV installer, domain join, naming convention, etc.)

Repeatable, consistent workstation setup for any client environment

🚀 Quick Start

Run this command on a fresh Windows machine to launch the tool:

iwr -useb "https://raw.githubusercontent.com/Malphas-Prime/Ares/main/PrepUtility/main.ps1" | iex


This will:

Download the main orchestrator script

Load the GUI

Dynamically load modules from the GitHub repository

Allow the user to run tasks interactively

📁 Project Structure
PrepUtility/
│
├── main.ps1                # Main GUI + orchestration script
│
└── modules/                # Individual automation modules
     ├── 01-Install-BaseApps.ps1
     ├── 02-Remove-Bloat.ps1
     ├── 03-Set-Defaults.ps1
     ├── 10-Join-Domain.ps1
     └── 20-Install-RMM.ps1

main.ps1

Loads the GUI (WPF)

Displays available tasks

Downloads and runs module scripts dynamically

Tracks task status

Basic error handling

Modules

Each module should be:

A standalone PowerShell script

Safe to run individually

Focused on one job (Single-Responsibility Principle)

This makes tasks easy to maintain and customize per client.

🛠 Creating New Modules

To add a new step:

Create a new .ps1 file under /modules/

Add the script logic (winget installs, registry changes, domain joins, etc.)

Register it in main.ps1 inside the $PrepTasks array:

Example:

[pscustomobject]@{
    Name        = "Install Office"
    Description = "Installs Microsoft 365 applications"
    ScriptPath  = "modules/30-Install-Office.ps1"
}


The GUI will detect it automatically.

🔐 Security Notes

This utility is read-only for the public; scripts cannot be modified by users unless you grant permissions.

Only trusted administrators should run iex scripts.

Consider pinning versions to specific commits for production stability.

Always review code before running remote scripts in sensitive environments.

📦 Packaging & Deployment

The utility is designed to be portable and requires no installation.
Recommended usage scenarios:

MSP workstation setup

Internal IT provisioning

Automated rebuilds

Tech onboarding scripts

Lab/workshop environments

🤝 Contributions

This project is intended for private use, but collaboration is welcome if approved.
Open an issue or submit a pull request for:

Module improvements

New automation ideas

Bug fixes

GUI enhancements

📜 License

This project may be used, modified, and adapted freely within your organization.
Redistribution or commercial resale without permission is not allowed.

📧 Contact

Created and maintained by Malphas-Prime (Olumpa).

If you'd like help adding more modules or expanding the GUI, open an issue or request enhancements.
