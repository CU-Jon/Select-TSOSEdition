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
param()

# Load the required assembly for Windows Forms
Add-Type -AssemblyName System.Windows.Forms

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
$osFamily = $tsenv.Value("osFamily")  # Get OS family from Task Sequence variable
if (-not $osFamily) {
    Write-TSLog -Message "osFamily variable not set. Defaulting to 'Windows 11'." -Type "Warning"
    $osFamily = "Windows 11"  # Default value if not set
} else {
    Write-TSLog -Message "Got osFamily variable: $osFamily" -Type "Info"
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

# Define paths for ShowKeyPlus
$showKeyPlusPath = "$PSScriptRoot\ShowKeyPlus_x64_1.0.7060\ShowKeyPlus.exe"
Write-TSLog -Message "ShowKeyPlus path: $showKeyPlusPath" -Type "Info"
$keyInfoPath = "$PSScriptRoot\keyinfo.txt"
Write-TSLog -Message "Key info path: $keyInfoPath" -Type "Info"

# Run ShowKeyPlus and wait for it to finish
Write-TSLog -Message "Running ShowKeyPlus to detect OEM edition..." -Type "Info"
Start-Process -FilePath $showKeyPlusPath -ArgumentList "`"$keyInfoPath`"" -Wait -ErrorAction SilentlyContinue

# Check if the keyinfo.txt file exists
$autoOptionEnabled = $false
$autoEdition = "Unknown"  # Default to Unknown
$autoEditionDisplayName = "Unknown"  # For displaying to user

if (Test-Path $keyInfoPath) {
    # Read the contents of the file
    $keyInfo = Get-Content $keyInfoPath

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
    Remove-Item $keyInfoPath -Force
} else {
    Write-TSLog -Message "keyinfo.txt not found. Auto edition detection will be skipped." -Type "Warning"
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "$osFamily Edition Selection"
$form.Size = New-Object System.Drawing.Size(400, 250)  # Increased size for better visibility
$form.StartPosition = "CenterScreen"
$form.TopMost = $true  # Keep the form on top of other windows

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select the edition of $osFamily to install:"
$label.AutoSize = $true
$label.Top = 20
$label.Left = 10
$form.Controls.Add($label)

# ComboBox (Dropdown)
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Top = 50
$comboBox.Left = 10
$comboBox.Width = 280
$comboBox.DropDownStyle = 'DropDownList'

# Add blank item first, then edition names
$comboBox.Items.Add("") | Out-Null
$comboBox.Items.AddRange($editionOptions.Keys)

# Only add "Auto" option if a valid edition was detected
if ($autoOptionEnabled) {
    $comboBox.Items.Add("Auto (Detected: $autoEditionDisplayName)") | Out-Null
    # Set the default selection to "Auto (Detected: $autoEditionDisplayName)" if auto edition is available
    $comboBox.SelectedItem = "Auto (Detected: $autoEditionDisplayName)"
}

$form.Controls.Add($comboBox)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Top = 90
$okButton.Left = 200
$okButton.Enabled = $false  # Disabled by default
$form.Controls.Add($okButton)

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Top = 90
$cancelButton.Left = 100
$form.Controls.Add($cancelButton)

# Enable OK only if a valid edition is selected
$comboBox.Add_SelectedIndexChanged({
    $okButton.Enabled = ($comboBox.SelectedIndex -gt 0)
})

# Automatically enable the OK button if auto edition is selected by default
if ($autoOptionEnabled -and $comboBox.SelectedItem -eq "Auto (Detected: $autoEditionDisplayName)") {
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
    # Log that the user cancelled the selection
    Write-TSLog -Message "User cancelled the edition selection." -Type "Warning"

    # Show message dialog to notify the user
    [System.Windows.Forms.MessageBox]::Show("You have cancelled the edition selection. The task sequence will stop now.", "Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly)

    # Close the form
    $form.Close()

    # Exit with error code
    exit 1
})

# Show form
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedDisplayName = $comboBox.SelectedItem.ToString()

    if ($selectedDisplayName -eq "Auto (Detected: $autoEditionDisplayName)" -and $autoOptionEnabled) {
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
