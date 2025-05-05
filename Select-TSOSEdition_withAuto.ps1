###############################################################################
#                                                                             #
#          OS Edition Selections for SCCM OS Deployment Task Sequences        #
#                                                                             #
#      Allows a user to select their desired Windows edition to install       #
#                              on the machine.                                #
#                                                                             #
#       Script author: Jon Agramonte, Clemson University CCIT                 #
#                     Contact: jagramo@clemson.edu                            #
#                                                                             #
###############################################################################

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OsFamily, # Windows 11, Windows 10.... # Will do more with this later. For now, just for display to the user.
    [Parameter(Mandatory=$false)]
    [string]$OsEdition, # home, edu, ent, prows, proedu, pro ## To be used in a future version of this script.
    [Parameter(Mandatory=$false)]
    [string]$OsVersion, # 24H2, 23H2, 22H2.... (only if you actually use this value somewhere in your TS) ## To be used in a future version of this script.
    [Parameter(Mandatory=$false)]
    [string]$ShowKeyPlusPath = $(Join-Path "$PSScriptRoot\ShowKeyPlus_x64_1.0.7060" "ShowKeyPlus.exe"), # Must be version 1.0.7060, no greater, no less.
    [Parameter(Mandatory=$false)]
    [string]$KeyInfoPath = $(Join-Path $PSScriptRoot "keyinfo.txt") # Path where the key info will be temporarily saved to from SKP
)

# Display name to short name mapping
$editionOptions = @{
    "Home"                  = "home"
    "Education"             = "edu"
    "Enterprise"            = "ent"
    "Pro for Workstations"  = "prows"
    "Pro Education"         = "proedu"
    "Pro"                   = "pro"
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
try {
    $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
} catch {
    Write-Verbose "Could not create Task Sequence environment object (not running in TS?)"
    [System.Windows.Forms.MessageBox]::Show("The task sequence environment could not be loaded. The computer will reboot now.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly)
    Restart-Computer -Force
}

# Define the script name
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)

# Function to log messages to the Task Sequence log
function Write-TSLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Type = "Info"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $fullMessage = "$timestamp [$Type][$scriptName] $Message"

    try {
        $logFolder = $tsenv.Value("_SMSTSLogPath")
        $logPath = Join-Path -Path $logFolder -ChildPath ("$scriptName.log")  # <--- Here we use scriptName dynamically

        # Only try to write if folder exists
        if (Test-Path $logFolder) {
            Add-Content -Path $logPath -Value $fullMessage
        } else {
            Write-Verbose "Log folder does not exist, skipping file write."
        }
    } catch {
        Write-Verbose "Failed to write to custom log: $($_.Exception.Message)"
    }

    # Always write to Verbose
    Write-Verbose $fullMessage
}

# Log that we're running the script
Write-TSLog -Message "Running $scriptName" -Type "Info"

# OS Family
if (-not ($OsFamily)) {
    Write-TSLog -Message "OS Family argument not specified, falling back to checking the TS Environment variable..." -Type "Info"
    $tsOsFamily = $tsenv.Value("osFamily") # Get OS family from Task Sequence variable, if set
    if ($tsOsFamily) {
        $OsFamily = $tsOsFamily
        Write-TSLog -Message "Got osFamily variable from TS Environment: $OsFamily"
    } else {
        Write-TSLog -Message "OS Family argument not specified and not set as a TS Environment variable. Falling back to 'Windows'" -Type "Warning"
        $OsFamily = "Windows"
    }
} else {
    Write-TSLog -Message "OS Family specified via argument: $OsFamily" -Type "Info"
    try {
        $tsenv.Value("osFamily") = $OsFamily
        Write-TSLog -Message "Set TS variable 'osFamily' to the specified `"$OsFamily`"" -Type "Info"
    } catch {
        Write-TSLog -Message "Could not set Task Sequence variable (not running in TS?)" -Type "Error"
    }
}

# If ShowKeyPlus exists at the defined path, run it
if ((Test-Path $ShowKeyPlusPath)) {
    Write-TSLog -Message "ShowKeyPlus path: $ShowKeyPlusPath" -Type "Info"
    Write-TSLog -Message "Key info path: $KeyInfoPath" -Type "Info"

    # Run ShowKeyPlus and wait for it to finish
    Write-TSLog -Message "Running ShowKeyPlus to detect OEM edition..." -Type "Info"
    #Start-Process -FilePath $ShowKeyPlusPath -ArgumentList "`"$KeyInfoPath`"" -Wait -ErrorAction SilentlyContinue ### This doesn't work as intended for logging purposes. Leaving this here just as reference.
    # Configure start‐info
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $ShowKeyPlusPath
    $psi.Arguments              = $KeyInfoPath
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
if (Test-Path $KeyInfoPath) {
    # Read the contents of the file
    $keyInfo = Get-Content $KeyInfoPath

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
    Remove-Item $KeyInfoPath -Force
} else {
    Write-TSLog -Message "keyinfo.txt not found. Auto edition detection will be skipped." -Type "Warning"
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoSize      = $true
$form.AutoSizeMode  = 'GrowAndShrink'
$form.Text = "$OsFamily Edition Selection"
#$form.Size = New-Object System.Drawing.Size(400, 250)  # Increased size for better visibility
$form.StartPosition = "CenterScreen"
$form.TopMost = $true  # Keep the form on top of other windows
# ensure a reasonable default size even if content is small
$form.MinimumSize = New-Object System.Drawing.Size(300,200)
$form.Padding     = New-Object System.Windows.Forms.Padding(10)

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select the edition of $OsFamily to install:"
$label.AutoSize = $true

# ComboBox (Dropdown)
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.DropDownStyle = 'DropDownList'

# Add blank item first, then edition names
$comboBox.Items.Add("") | Out-Null
$comboBox.Items.AddRange($editionOptions.Keys)
$comboBox.Width = 200

# Only add "Auto" option if a valid edition was detected
if ($autoOptionEnabled) {
    $autoEditionComboBoxItem = "Auto (Detected: $autoEditionDisplayName)"
    $comboBox.Items.Add($autoEditionComboBoxItem) | Out-Null
    # Set the default selection to $autoEditionComboBoxItem if auto edition is available
    $comboBox.SelectedItem = $autoEditionComboBoxItem
}

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Enabled = $false  # Disabled by default

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"

# Enable OK only if a valid edition is selected
$comboBox.Add_SelectedIndexChanged({
    $okButton.Enabled = ($comboBox.SelectedIndex -gt 0)
})

# Automatically enable the OK button if auto edition is selected by default
if ($autoOptionEnabled -and $comboBox.SelectedItem -eq $autoEditionComboBoxItem) {
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
    [System.Windows.Forms.MessageBox]::Show($form, "You have cancelled the edition selection. The task sequence will stop now.", "Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information, [System.Windows.Forms.MessageBoxDefaultButton]::Button1)

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
$table.ColumnCount   = 1
$table.RowCount      = 3
$table.Dock          = 'Fill'
$table.Padding       = New-Object System.Windows.Forms.Padding(10)
$table.AutoSize      = $true
$table.AutoSizeMode  = 'GrowAndShrink'

# Row styles: each row autosizes to its content
1..3 | ForEach-Object {
  $table.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle(
       [System.Windows.Forms.SizeType]::AutoSize, 0
    ))
  ) | Out-Null
}

# Add your controls in order
$table.Controls.Add($label,       0, 0)
$table.Controls.Add($comboBox,    0, 1)
$table.Controls.Add($buttonsPanel,0, 2)

# Make the ComboBox fill the width
$comboBox.Dock = 'Fill'

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
  $comboBox.Focus()
})

# Show form
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    # Log that the user cancelled the selection
    Write-TSLog -Message "User cancelled the edition selection." -Type "Warning"
    # now exit cleanly from the script
    exit 1
}

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedDisplayName = $comboBox.SelectedItem.ToString()

    if ($selectedDisplayName -eq $autoEditionComboBoxItem -and $autoOptionEnabled) {
        # If "Auto" is selected, use the detected edition from ShowKeyPlus
        $selectedShortName = $autoEdition
        Write-TSLog -Message "Set osEdition = $selectedShortName (Auto selected)" -Type "Info"
        $isAutoEdition = $true
    } else {
        # Get the short name for selected edition
        $selectedShortName = $editionOptions[$selectedDisplayName]
        Write-TSLog -Message "Set osEdition = $selectedShortName (Manual selection)" -Type "Info"
    }

    try {
        $tsenv.Value("osEdition") = $selectedShortName
        Write-TSLog -Message "Set osEdition = $selectedShortName" -Type "Info"
        if ($isAutoEdition) {
            $tsenv.Value("isAutoEdition") = "true"
            Write-TSLog -Message "Set isAutoEdition = true" -Type "Info"
            if ($oemKey) {
                $tsenv.Value("oemKey") = $oemKey
                Write-TSLog -Message "Set oemKey = $oemKey" -Type "Info"
            } else {
                Write-TSLog -Message "No OEM key found to set." -Type "Warning"
            }
        } else {
            $tsenv.Value("isAutoEdition") = "false"
            Write-TSLog -Message "Set isAutoEdition = false" -Type "Info"
        }
    } catch {
        Write-TSLog -Message "Could not set Task Sequence variable (not running in TS?)" -Type "Error"
        exit 1
    }
}

exit 0
