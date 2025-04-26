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

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "$osFamily Edition Selection"
$form.Size = New-Object System.Drawing.Size(400, 250)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

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
$form.Controls.Add($comboBox)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Top = 90
$okButton.Left = 200
$okButton.Enabled = $false
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
    $selectedShortName = $editionOptions[$selectedDisplayName]
    Write-TSLog -Message "Set osEdition = $selectedShortName (Manual selection)" -Type "Info"

    try {
        $tsenv.Value("osEdition") = $selectedShortName
        Write-TSLog -Message "Set osEdition = $selectedShortName" -Type "Info"
    } catch {
        Write-TSLog -Message "Could not set Task Sequence variable (not running in TS?)" -Type "Error"
        exit 1
    }
}

exit 0
