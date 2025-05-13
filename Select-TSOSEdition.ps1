<#
.SYNOPSIS
This script facilitates the selection of a Windows operating system edition for SCCM OS Deployment Task Sequences.

.DESCRIPTION
The script provides a graphical user interface (GUI) to allow users to select the desired Windows OS family and edition to install on a machine during an SCCM task sequence. It supports automatic detection of OEM editions using ShowKeyPlus and logs all actions for troubleshooting purposes. The selected values are stored as Task Sequence variables for use in the deployment process.

.PARAMETER OsFamily
Specifies the OS family (e.g., "Windows 10", "Windows 11"). If not provided, the script attempts to retrieve it from the Task Sequence environment variable "osFamily" or defaults to "Windows".

.PARAMETER ShowKeyPlusPath
Specifies the path to the ShowKeyPlus executable for detecting OEM editions. Defaults to a predefined path if not provided.

.PARAMETER KeyInfoPath
Specifies the path to temporarily save key information from ShowKeyPlus. Must end with `.txt`. Defaults to a predefined path if not provided.

.PARAMETER LogPath
Specifies the path for the log file. Defaults to the Task Sequence environment log path if not provided. If in testing mode, and no log path is specified, logging will not occur.

.PARAMETER Testing
Enables testing mode, bypassing Task Sequence environment dependencies.

.PARAMETER NoOsFamily
Skips the OS family selection step if specified and will not attempt to set the osFamily variable in the Task Sequence environment.

.PARAMETER OsFamilyVariableName
Specifies the name of the Task Sequence variable to set for OS family. Defaults to "osFamily".

.PARAMETER OsEditionVariableName
Specifies the name of the Task Sequence variable to set for OS edition. Defaults to "osEdition".

.PARAMETER IsAutoEditionVariableName
Specifies the name of the Task Sequence variable to set for auto edition detection. Defaults to "isAutoEdition".

.PARAMETER OemKeyVariableName
Specifies the name of the Task Sequence variable to set for the detected OEM key. Defaults to "oemKey".

.PARAMETER DefaultOsFamily
If -OsFamily is not specified and TS Var "osFamily" is not set, default the combo box selection for the OS to this (must match a key name in the below $familyOptions).
This doesn't matter if you set -NoOsFamily, as it will skip the OS Family selection altogether.
Defaults to "Windows 11" if not specified.

.PARAMETER OsFamilyFallback
Set the $OsFamily fallback name (just for display to the user in the GUI) if -OsFamily is not specified and TS Var "osFamily" is not set.
You really shouldn't need to change this unless you have a specific reason to do so.

.NOTES
Author: Jon Agramonte, Clemson University CCIT
Contact: jagramo@clemson.edu

.EXAMPLE
.\Select-TSOSEdition.ps1 -OsFamily "Windows 11" -Verbose
Launches the script with "Windows 11" as the OS family and enables verbose logging.

.EXAMPLE
.\Select-TSOSEdition.ps1 -Testing
Runs the script in testing mode, bypassing Task Sequence environment dependencies.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OsFamily, # Windows 11, Windows 10....
    [Parameter(Mandatory=$false)]
    [string]$ShowKeyPlusPath, # Must be version 1.0.7060, no greater, no less.
    [Parameter(Mandatory=$false)]
    [ValidatePattern('\.txt$')] # must end in .txt  (case‑insensitive by default)
    [string]$KeyInfoPath, # Path where the key info will be temporarily saved to from SKP
    [Parameter(Mandatory=$false)]
    [ValidatePattern('\.log$')] # must end in .log  (case‑insensitive by default)
    [string]$LogPath, # Defaults to the TS Envrionment log path location later on, unless otherwise specified here
    [Parameter(Mandatory=$false)]
    [switch]$Testing, # Specify this if you're testing outside of a task sequence environment
    [Parameter(Mandatory=$false)]
    [switch]$NoOsFamily, # Specify this if you want to skip the OS Family selection (e.g. if you know it already)
    [Parameter(Mandatory=$false)]
    [string]$OsFamilyVariableName = "osFamily", # The name of the Task Sequence variable to set for OS Family
    [Parameter(Mandatory=$false)]
    [string]$OsEditionVariableName = "osEdition", # The name of the Task Sequence variable to set for OS Edition
    [Parameter(Mandatory=$false)]
    [string]$IsAutoEditionVariableName = "isAutoEdition", # The name of the Task Sequence variable to set for Auto Edition
    [Parameter(Mandatory=$false)]
    [string]$OemKeyVariableName = "oemKey", # The name of the Task Sequence variable to set for OEM Key
    [Parameter(Mandatory=$false)]
    [string]$DefaultOsFamily = "Windows 11", # If -OsFamily is not specified and TS Var "osFamily" is not set, default the combo box selection for the OS to this (must match a key name in the below $familyOptions). This doesn't matter if you set -NoOsFamily, as it will skip the OS Family selection altogether.
    [Parameter(Mandatory=$false)]
    [string]$OsFamilyFallback = "Windows" # Set the $OsFamily fallback name (just for display to the user in the GUI) if -OsFamily is not specified and TS Var "osFamily" is not set. You really shouldn't need to change this unless you have a specific reason to do so.
)

# Set default directories if not specified in arguments (this is because WinPE doesn't know what $PSScriptRoot is inside the param block, otherwise we'd just define it there)
if (-not($ShowKeyPlusPath)) {
    $ShowKeyPlusPath = Join-Path "$PSScriptRoot" "ShowKeyPlus_x64_1.0.7060\ShowKeyPlus.exe"
}
if (-not($KeyInfoPath)) {
    $KeyInfoPath = Join-Path "$PSScriptRoot" "keyinfo.txt"
}

# Set up verbose output
if ($($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) -or $Testing) {
    $PSDefaultParameterValues['*:Verbose'] = $true   # turns verbose on
    $VerbosePreference = "Continue"                 # show verbose output
    Write-Verbose "Verbose output enabled."
}

# Display name to short name mapping
$editionOptions = @{
    "Home"                  = "home"
    "Education"             = "edu"
    "Enterprise"            = "ent"
    "Pro for Workstations"  = "prows"
    "Pro Education"         = "proedu"
    "Pro"                   = "pro"
}
$familyOptions = @{
    "Windows 10"            = "Windows 10"
    "Windows 11"            = "Windows 11"
}

# --- DPI Helpers: System + Per-Monitor awareness (Win7 → Win10/WinPE) ---
Add-Type -TypeDefinition @"
  using System;
  using System.Runtime.InteropServices;
  public enum PROCESS_DPI_AWARENESS {
    Process_DPI_Unaware           = 0,
    Process_System_DPI_Aware      = 1,
    Process_Per_Monitor_DPI_Aware = 2
  }
  public class DpiHelper {
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(PROCESS_DPI_AWARENESS value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
  }
"@ -PassThru | Out-Null

# --- Helpers to bring the GUI to the front while running a task sequence ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class User32Ex {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -PassThru | Out-Null

try {
  [DpiHelper]::SetProcessDpiAwareness([PROCESS_DPI_AWARENESS]::Process_Per_Monitor_DPI_Aware) | Out-Null
} catch {
  [DpiHelper]::SetProcessDPIAware() | Out-Null
}

# Load the required assembly for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
# Only set text-rendering once; ignore if it’s too late
try {
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
} catch {
    # already been set in this process, so just ignore
}

# Load the COM object for the Task Sequence environment
if (-not($Testing)) {
    try {
        $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
        Write-Verbose "Task Sequence environment object created successfully."
    } catch {
        Write-Verbose "Could not create Task Sequence environment object (not running in TS?)"
        [void][System.Windows.Forms.MessageBox]::Show("The task sequence environment could not be loaded. Exiting...", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop, [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
        throw "The task sequence environment could not be loaded."
    }
} elseif ($Testing) {
    Write-Verbose "We're in testing mode. Not loading the TS Environment."
}

# Set up the logging function
Write-Verbose "Setting up for logging..."
# If we're in a TS Environment, get the log path
if ($tsenv) {
    $tsLogPath = $tsenv.Value("_SMSTSLogPath")
} else {
    Write-Verbose "We're not in a TS Environment!"
}

# Define the script name
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)

# Set the appropriate full log path
if (-not($LogPath) -and $tsLogPath) {
    Write-Verbose "LogPath not specified. Defaulting to _SMSTSLogPath"
    $LogPath = Join-Path "$tsLogPath" "$scriptName.log"
    Write-Verbose "Full log path: $LogPath"
} elseif ($LogPath) {
    Write-Verbose "-LogPath specified via argument: $LogPath"
} else {
    Write-Verbose "No LogPath specified and not in TS Environment. No logging will occur."
}

# Test to make sure the log folder exists, if we have a LogPath
if ($LogPath) {
    $logFolder = Split-Path "$LogPath" -Parent
    if (Test-Path "$logFolder") {
        Write-Verbose "$logFolder found, will proceed with logging."
    } else {
        Write-Verbose "$logFolder not found. Cannot proceed with logging to here."
        $LogPath = $null
    }
}

# Function to log messages to the log
function Write-TSLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Type = "Info"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $fullMessage = "$timestamp [$Type][$scriptName] $Message"

    # Log to file
    if ($LogPath) {
        try {
            Add-Content -Path "$LogPath" -Value $fullMessage -ErrorAction Stop
        } catch {
            Write-Verbose "Failed to write to custom log: $($_.Exception.Message)"
        }
    }

    # Always write to Verbose
    Write-Verbose $fullMessage
}

# Log that we're running the script
Write-TSLog -Message "Running $scriptName" -Type "Info"

# Functions to get and set variables in the Task Sequence environment
function Get-TSVariable {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VariableName
    )

    if ($Testing -and -not($tsenv)) { # If we're in testing mode, just output what we'd be doing
        Write-TSLog -Message "In testing mode. Would get TS Variable '$VariableName'" -Type "Info"
        return $null
    } elseif (-not($tsenv)) { # Check if the Task Sequence environment object is available
        Write-TSLog -Message "Task Sequence environment object not available. Cannot get variable $VariableName" -Type "Error"
        return $null
    }
    $variableValue = $tsenv.Value("$VariableName")
    if ($variableValue) {
        Write-TSLog -Message "TS Variable '$VariableName' found: $variableValue" -Type "Info"
        return $variableValue
    } else {
        Write-TSLog -Message "TS Variable '$VariableName' not found." -Type "Error"
        return $null
    }
}
function Set-TSVariable {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VariableName,
        [Parameter(Mandatory=$true)]
        [string]$Value
    )

    if ($Testing -and -not($tsenv)) { # If we're in testing mode, just output what we'd be doing
        Write-TSLog -Message "In testing mode. Would set TS Variable '$VariableName' to '$Value'" -Type "Info"
        return $true
    } elseif (-not($tsenv)) { # Check if the Task Sequence environment object is available
        Write-TSLog -Message "Task Sequence environment object not available. Cannot set variable $VariableName" -Type "Error"
        return $false
    }

    try {
        $tsenv.Value("$VariableName") = $Value
        Write-TSLog -Message "Set TS Variable '$VariableName' to '$Value'" -Type "Info"
        return $true
    } catch {
        Write-TSLog -Message "Failed to set TS Variable '$VariableName': $($_.Exception.Message)" -Type "Error"
        throw "Failed to set TS Variable '$VariableName': $($_.Exception.Message)"
    }
}

# OS Family
if (-not($OsFamily) -and $tsenv -and -not($NoOsFamily)) {
    Write-TSLog -Message "OsFamily argument not specified, falling back to checking the TS Environment variable..." -Type "Info"
    $tsOsFamily = Get-TSVariable -VariableName "osFamily" # Get OS family from Task Sequence variable, if set
    if ($tsOsFamily) {
        $OsFamily = $tsOsFamily
        Write-TSLog -Message "Got osFamily variable from TS Environment: $OsFamily"
    } else {
        Write-TSLog -Message "OsFamily argument not specified and not set as a TS Environment variable. Falling back to '$OsFamilyFallback'" -Type "Warning"
        $OsFamily = $OsFamilyFallback
        $osFamilyNotSpecified = $true
    }
} elseif ($OsFamily) {
    Write-TSLog -Message "OS Family specified via argument: $OsFamily" -Type "Info"
} else {
    Write-TSLog -Message "OsFamily argument not specified and not running in TS Environment. Falling back to '$OsFamilyFallback'"
    $OsFamily = $OsFamilyFallback
    if (-not($NoOsFamily)) {
        $osFamilyNotSpecified = $true
    }
}

# If ShowKeyPlus exists at the defined path, run it
if (Test-Path "$ShowKeyPlusPath") {
    Write-TSLog -Message "ShowKeyPlus path: $ShowKeyPlusPath" -Type "Info"
    Write-TSLog -Message "Key info path: $KeyInfoPath" -Type "Info"

    # Run ShowKeyPlus and wait for it to finish
    Write-TSLog -Message "Running ShowKeyPlus to detect OEM edition..." -Type "Info"
    #Start-Process -FilePath $ShowKeyPlusPath -ArgumentList "`"$KeyInfoPath`"" -Wait -ErrorAction SilentlyContinue ### This doesn't work as intended for logging purposes. Leaving this here just as reference.
    # Configure start‐info
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "$ShowKeyPlusPath"
    $psi.Arguments              = "$KeyInfoPath"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden

    # Launch and capture
    $proc = [System.Diagnostics.Process]::Start($psi)
    # read everything (this blocks until EOF)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    # wait for real exit
    $proc.WaitForExit()

    # strip off any final CR/LF so nothing sneaks into the output afterwards
    $stdout = $stdout.TrimEnd("`r","`n")
    $stderr = $stderr.TrimEnd("`r","`n")

    # Log the output of ShowKeyPlus
    if ($stdout) {
        Write-TSLog -Message "ShowKeyPlus output:`n$stdout" -Type "Info"
    } else {
        Write-TSLog -Message "No output from ShowKeyPlus." -Type "Warning"
    }
    if ($stderr) {
        Write-TSLog -Message "ShowKeyPlus error output:`n$stderr" -Type "Error"
    } else {
        Write-TSLog -Message "No error output from ShowKeyPlus." -Type "Info"
    }
} else {
    Write-TSLog -Message "ShowKeyPlus.exe not found at $ShowKeyPlusPath. Auto edition detection will be skipped." -Type "Warning"
}

# Default values, don't change these unless you want weirdness
$autoOptionEnabled = $false
$autoEdition = "Unknown"  # Default to Unknown
$autoEditionDisplayName = "Unknown"  # For displaying to user

# Check if the keyinfo.txt file exists
if (Test-Path "$KeyInfoPath") {
    # Read the contents of the file
    $keyInfo = Get-Content "$KeyInfoPath"

    # Log contents of keyInfo.txt
    Write-TSLog -Message "keyInfo.txt content:`n$keyInfo" -Type "Info"

    # Search for the line that contains "OEM Edition" using regex to extract only the edition name
    $editionLine = $keyInfo | Where-Object { $_ -match "OEM Edition:\s*(.*)" }

    if ($editionLine) {
        # Log the found OEM Edition line
        Write-TSLog -Message "editionLine = $editionLine" -Type "Info"

        # Extract the edition name (cleaning any unwanted suffix)
        $null = $editionLine -match "OEM Edition:\s*(.*)"
        $editionText = $matches[1].Trim()
        Write-TSLog -Message "editionText = $editionText" -Type "Info"

        # Now map the edition name to a short form edition (matching values in $editionOptions), but with the special case of "Core"
        if ($editionText -like "*Core*") {
            $autoEdition = $editionOptions["Home"]
            $autoEditionDisplayName = "Home"
        } else {
            foreach ($displayName in $editionOptions.Keys) {
                if ($editionText -like "*$displayName*") {
                    $autoEdition = $editionOptions[$displayName]
                    $autoEditionDisplayName = $displayName
                    break
                }
            }
        }
        
        # Enable Auto option if the edition is detected
        if ($autoEdition -ne "Unknown") {
            $autoOptionEnabled = $true
            Write-TSLog -Message "Auto edition detected: $autoEditionDisplayName" -Type "Info"
            # We have an auto edition availabe, now store the OEM key value in case the admin/user wants to use it later
            $oemKeyLine = $keyInfo | Where-Object { $_ -match "OEM Key:\s*(.*)" }
            if ($oemKeyLine) {
                Write-TSLog -Message "OEM Key line found: $oemKeyLine" -Type "Info"
                $null = $oemKeyLine -match "OEM Key:\s*(.*)"
                $oemKey = $matches[1].Trim()
                Write-TSLog -Message "OEM Key: $oemKey" -Type "Info"
            } else {
                Write-TSLog -Message "No OEM Key line found in keyinfo.txt." -Type "Warning"
            }
        } else {
            Write-TSLog -Message "No valid OEM edition detected." -Type "Warning"
        }
    } else {
        Write-TSLog -Message "No OEM Edition line found in keyinfo.txt." -Type "Warning"
    }

    # Delete the keyinfo.txt file after reading its content, as it's no longer needed
    Remove-Item "$KeyInfoPath" -Force
} else {
    Write-TSLog -Message "keyinfo.txt not found. Auto edition detection will be skipped." -Type "Warning"
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoSize      = $true
$form.AutoSizeMode  = 'GrowAndShrink'
$form.StartPosition = "CenterScreen"
$form.TopMost = $true  # Keep the form on top of other windows
# ensure a reasonable default size even if content is small
if ($osFamilyNotSpecified) {
    $form.Text = "OS and Edition Selection"
    $form.MinimumSize = New-Object System.Drawing.Size(300,250)
} else {
    $form.Text = "$OsFamily Edition Selection"
    $form.MinimumSize = New-Object System.Drawing.Size(300,200)
}
$form.Padding     = New-Object System.Windows.Forms.Padding(10)

# Label
if ($osFamilyNotSpecified) {
    $labelFamily = New-Object System.Windows.Forms.Label
    $labelFamily.Text = "Select the operating system to install:"
    $labelFamily.AutoSize = $true
}
$labelEdition = New-Object System.Windows.Forms.Label
$labelEdition.Text = "Select the edition of $OsFamily to install:"
$labelEdition.AutoSize = $true

# ComboBox (Dropdown)
if ($osFamilyNotSpecified) {
    $comboBoxFamily = New-Object System.Windows.Forms.ComboBox
    $comboBoxFamily.DropDownStyle = 'DropDownList'
    $comboBoxFamily.Items.AddRange($familyOptions.Keys)
    $comboBoxFamily.Width = 200
    # Set the default OS Family combo box selection to $DefaultOsFamily
    $comboBoxFamily.SelectedItem = $DefaultOsFamily
    $comboBoxFamily.Dock = 'Fill'
}
$comboBoxEdition = New-Object System.Windows.Forms.ComboBox
$comboBoxEdition.DropDownStyle = 'DropDownList'
# Add blank item first, then edition names
$comboBoxEdition.Items.Add("") | Out-Null
$comboBoxEdition.Items.AddRange($editionOptions.Keys)
$comboBoxEdition.Width = 200
$comboBoxEdition.Dock = 'Fill'

# Only add "Auto" option if a valid edition was detected
if ($autoOptionEnabled) {
    $autoEditionComboBoxItem = "Auto (Detected: $autoEditionDisplayName)"
    $comboBoxEdition.Items.Add($autoEditionComboBoxItem) | Out-Null
    # Set the default selection to $autoEditionComboBoxItem if auto edition is available
    $comboBoxEdition.SelectedItem = $autoEditionComboBoxItem
} else {
    $comboBoxEdition.SelectedIndex = 0  # Select the blank item by default
}

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Enabled = $false  # Disabled by default

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"

# Enable OK only if a valid edition is selected
$comboBoxEdition.Add_SelectedIndexChanged({
    $okButton.Enabled = ($comboBoxEdition.SelectedIndex -gt 0)
})

# Automatically enable the OK button if auto edition is selected by default
if ($autoOptionEnabled -and $comboBoxEdition.SelectedItem -eq $autoEditionComboBoxItem) {
    $okButton.Enabled = $true
}

# OK button logic
$okButton.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    
    # Close the form
    $form.Close()
})

# Cancel button logic
$cancelButton.Add_Click({
    # bring the form itself to the front first
    $form.Activate()
    # Show message dialog to notify the user
    [System.Windows.Forms.MessageBox]::Show($form, "You have cancelled the edition selection. The task sequence will stop now.", "Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop, [System.Windows.Forms.MessageBoxDefaultButton]::Button1)

    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    # Close the form
    $form.Close()
})

# make Enter hit the OK button (only fires if it’s enabled)
$form.AcceptButton = $okButton

# make ESC hit the Cancel button
$form.CancelButton = $cancelButton

# ——— Main layout: single-column TableLayoutPanel ———
# Build buttons row first (auto-sizes to their preferred height)
$cancelButton.AutoSize = $true
$okButton.AutoSize     = $true
$buttonsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonsPanel.FlowDirection = 'LeftToRight'
$buttonsPanel.AutoSize      = $true
$buttonsPanel.AutoSizeMode  = 'GrowAndShrink'
$buttonsPanel.WrapContents  = $false
$buttonsPanel.Margin        = New-Object System.Windows.Forms.Padding(0,20,0,0)
$buttonsPanel.Dock          = 'Right'
$buttonsPanel.Controls.Add($cancelButton)
$buttonsPanel.Controls.Add($okButton)

# Now build the 1-col table
$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.ColumnCount = 1
if ($osFamilyNotSpecified) {
    $table.RowCount = 5
} else {
    $table.RowCount = 3
}
$table.Dock          = 'Fill'
$table.Padding       = New-Object System.Windows.Forms.Padding(10)
$table.AutoSize      = $true
$table.AutoSizeMode  = 'GrowAndShrink'

# Row styles: each row autosizes to its content
if ($osFamilyNotSpecified) {
    1..5 | ForEach-Object {
    $table.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::AutoSize, 0
        ))
    ) | Out-Null
    }
} else {
    1..3 | ForEach-Object {
    $table.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::AutoSize, 0
        ))
    ) | Out-Null
    }
}

# Add your controls in order
if ($osFamilyNotSpecified) {
    $table.Controls.Add($labelFamily, 0, 0)
    $table.Controls.Add($comboBoxFamily, 0, 1)
    $table.Controls.Add($labelEdition, 0, 2)
    $table.Controls.Add($comboBoxEdition, 0, 3)
    $table.Controls.Add($buttonsPanel,0, 4)
} else {
    $table.Controls.Add($labelEdition, 0, 0)
    $table.Controls.Add($comboBoxEdition, 0, 1)
    $table.Controls.Add($buttonsPanel, 0, 2)
}

# Finally, add the table to the form
$form.Controls.Add($table)

# ensure the form grabs foreground focus and the dropdown is selected
$form.Add_Shown({
  # get the HWND & thread of whatever’s currently foreground (i.e. SCCM UI)
  $fgHwnd    = [User32Ex]::GetForegroundWindow()
  $null      = 0
  $fgThread  = [User32Ex]::GetWindowThreadProcessId($fgHwnd, [ref]$null)

  # get our current thread and attach to the SCCM thread
  $myThread  = [User32Ex]::GetCurrentThreadId()
  [User32Ex]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null

  # now we’re allowed to force our window to front
  [User32Ex]::BringWindowToTop($form.Handle)    | Out-Null
  [User32Ex]::SetForegroundWindow($form.Handle) | Out-Null

  # detach the input queues again
  [User32Ex]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null

  # finally, focus the combo
  # uncomment this if section AND comment out the following line to focus the "OS Family" combo box if it is not specified otherwise
<#   if ($osFamilyNotSpecified) {
    $comboBoxFamily.Focus()
  } else {
    $comboBoxEdition.Focus()
  } #>

  # focus the edition combo box by default. Comment this out and uncomment the above if section if you want to focus the OS Family combo box instead.
  $comboBoxEdition.Focus()
})

# Show form
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    # Log that the user cancelled the selection
    Write-TSLog -Message "User cancelled the edition selection." -Type "Warning"
    # now exit cleanly from the script
    throw "User cancelled the edition selection."
}

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    if ($osFamilyNotSpecified) {
        $selectedFamilyDisplayName = $comboBoxFamily.SelectedItem.ToString()
        $selectedFamilyShortName = $familyOptions[$selectedFamilyDisplayName]
        Write-TSLog -Message "Selected family: $selectedFamilyShortName" -Type "Info"
    }
    
    $selectedEditionDisplayName = $comboBoxEdition.SelectedItem.ToString()

    if ($selectedEditionDisplayName -eq $autoEditionComboBoxItem -and $autoOptionEnabled) {
        # If "Auto" is selected, use the detected edition from ShowKeyPlus
        $selectedEditionShortName = $autoEdition
        Write-TSLog -Message "Selected edition: $selectedEditionShortName (Auto)" -Type "Info"
        $isAutoEdition = $true
    } else {
        # Get the short name for selected edition
        $selectedEditionShortName = $editionOptions[$selectedEditionDisplayName]
        Write-TSLog -Message "Selected edition: $selectedEditionShortName (Manual)" -Type "Info"
    }

    # Set the OS Family variable in the Task Sequence environment specified by $OsFamilyVariableName
    if ($osFamilyNotSpecified) {
        Set-TSVariable -VariableName $OsFamilyVariableName -Value $selectedFamilyShortName | Out-Null
    } elseif ($OsFamily -and -not($NoOsFamily) -and ($OsFamily -ne $OsFamilyFallback)) {
        Set-TSVariable -VariableName $OsFamilyVariableName -Value $OsFamily | Out-Null
    } elseif ($NoOsFamily) {
        Write-TSLog -Message "-NoOsFamily Specified, so $OsFamilyVariableName will not be set in the TS Environment." -Type "Info"
    } else {
        Write-TSLog -Message "OsFamily not set, so it will not be set in the TS Environment." -Type "Info"
    }
    # Set the OS Edition variable in the Task Sequence environment specified by $OsEditionVariableName
    Set-TSVariable -VariableName $OsEditionVariableName -Value $selectedEditionShortName | Out-Null
    # Set the auto edition variable in the Task Sequence environment specified by $IsAutoEditionVariableName
    if ($isAutoEdition) {
        Set-TSVariable -VariableName $IsAutoEditionVariableName -Value "true" | Out-Null
        # Set the OEM Key variable in the Task Sequence environment specified by $OemKeyVariableName
        if ($oemKey) {
            Set-TSVariable -VariableName $OemKeyVariableName -Value $oemKey | Out-Null
        } else {
            Write-TSLog -Message "No OEM key found to set." -Type "Warning"
        }
    } else {
        # Set auto edition variable specified by $IsAutoEditionVariableName to false if not auto edition
        Set-TSVariable -VariableName $IsAutoEditionVariableName -Value "false" | Out-Null
    }
}

exit 0
