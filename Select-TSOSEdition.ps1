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
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoSize      = $true
$form.AutoSizeMode  = 'GrowAndShrink'
$form.Text = "$osFamily Edition Selection"
#$form.Size = New-Object System.Drawing.Size(400, 250)  # Increased size for better visibility
$form.StartPosition = "CenterScreen"
$form.TopMost = $true  # Keep the form on top of other windows
# ensure a reasonable default size even if content is small
$form.MinimumSize = New-Object System.Drawing.Size(300,200)
$form.Padding     = New-Object System.Windows.Forms.Padding(10)

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select the edition of $osFamily to install:"
$label.AutoSize = $true

# ComboBox (Dropdown)
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.DropDownStyle = 'DropDownList'

# Add blank item first, then edition names
$comboBox.Items.Add("") | Out-Null
$comboBox.Items.AddRange($editionOptions.Keys)
$comboBox.Width = 200

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
