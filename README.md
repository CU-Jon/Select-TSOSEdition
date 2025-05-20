# Select-TSOSEdition Toolset

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Language: PowerShell](https://img.shields.io/badge/Language-PowerShell-blue.svg)](https://learn.microsoft.com/en-us/powershell/)
[![Built With: PowerShell 5+](https://img.shields.io/badge/Built%20With-PowerShell%205+-blueviolet.svg)](https://learn.microsoft.com/en-us/powershell/)

---

A single, flexible PowerShell script to assist with selecting and detecting the correct Windows edition during SCCM Task Sequences.

The script dynamically sets SCCM Task Sequence variables (such as `osEdition`) based on user selection, automatic detection using BIOS-embedded product keys (via ShowKeyPlus), or a combination—depending on parameters and environment.

Compatible with Windows 8, Windows 8.1, Windows 10, and Windows 11 deployments.

---

## 📦 Contents

- **Select-TSOSEdition.ps1**  
  All-in-one script for Windows edition selection:
  - **Manual mode:** Prompts user to select edition.
  - **Automatic mode:** Detects edition via ShowKeyPlus if available, otherwise prompts user.
  - **Testing mode:** Simulates actions without modifying Task Sequence variables or writing logs.

---

## 🛠 Requirements

- **ShowKeyPlus x64 Version 1.0.7060** is required for edition auto-detection.
- Download from the official GitHub release here:  
  [https://github.com/Superfly-Inc/ShowKeyPlus/releases/tag/ShowKeyPlus7060](https://github.com/Superfly-Inc/ShowKeyPlus/releases/tag/ShowKeyPlus7060)

- After downloading:
  - Create a folder named `ShowKeyPlus_x64_1.0.7060` next to the script.
  - Place the `ShowKeyPlus.exe` binary directly inside this folder.
  - The folder structure should look like this:

```
Select-TSOSEdition/
├── Select-TSOSEdition.ps1
├── ShowKeyPlus_x64_1.0.7060/
│   └── ShowKeyPlus.exe
```

⚠️ The folder name `ShowKeyPlus_x64_1.0.7060` is used by default in the script, but you can override this location by specifying the `-ShowKeyPlusPath` parameter.

---

## 🛠 How It Works

1. Place the script and the ShowKeyPlus_x64_1.0.7060 folder together.

2. Execute the script during your SCCM Task Sequence.  
   The script will automatically determine the mode of operation based on parameters and environment:
   - **Manual selection:** If no OEM key is detected or auto-detection is not possible.
   - **Automatic detection:** If ShowKeyPlus is present and an OEM key is found, the detected edition is offered as a default.
   - **Testing mode:** Use the `-Testing` parameter to simulate actions without affecting the Task Sequence.

⚡ **Important:**  
Because Task Sequences run under the SYSTEM account, you must use `ServiceUI.exe` to display the script's UI to the logged-in user.

Example command line inside your Task Sequence step:

```
ServiceUI.exe -process:TSProgressUI.exe powershell.exe -ExecutionPolicy Bypass -WindowStyle Minimized -File "Select-TSOSEdition.ps1" -Verbose
```

✅ Adjust the path as needed for your environment.

✅ ServiceUI.exe can be found inside the MDT Toolkit or ConfigMgr MDT integration package under `Tools\x64\` or `Tools\x86\`.

3. The script will set the Task Sequence variable **osEdition** to one of the following values:

| Windows Edition                | osEdition Value |
|:-------------------------------|:---------------|
| Windows 8/8.1/10/11 Home       | `home`         |
| Windows 8/8.1/10/11 Pro        | `pro`          |
| Windows 8/8.1/10/11 Enterprise | `ent`          |
| Windows 8/8.1/10/11 Education  | `edu`          |
| Windows 10/11 Pro for Workstations | `prows`     |
| Windows 10/11 Pro Education    | `proedu`       |

4. If the automatically detected edition is selected by the user, the Task Sequence variable **isAutoEdition** will be set to **true**. Otherwise, **false**.  
   If an OEM Product Key is found, it will be stored in the Task Sequence variable **oemKey**.

   Example usage in a Task Sequence step:
   ```
   cscript.exe "%windir%\System32\slmgr.vbs" /ipk %oemKey%
   cscript.exe "%windir%\System32\slmgr.vbs" /ato
   ```

5. In your Task Sequence:
   - Add **Install Operating System** steps for each edition you want to support.
   - Add a **Condition** on each step:
     - Example:  
       `Task Sequence Variable osEdition equals home`
     - For Pro Edition:  
       `osEdition equals pro`
     - For Enterprise Edition:  
       `osEdition equals ent`
     - And so on.

6. This allows a single Task Sequence to handle installing different Windows editions dynamically based on user input or automatic OEM detection.

---

## 📝 Parameters

The script supports several parameters for flexibility:

- `-Testing`  
  Run in testing mode (no Task Sequence variable changes or log writes).

- `-OsFamily`  
  Specify the OS family (e.g., "Windows 10", "Windows 11"). If omitted, the script will prompt or use Task Sequence variables.

- `-NoOsFamily`  
  Skip OS family selection.

- `-ShowKeyPlusPath`  
  Override the default path to ShowKeyPlus.exe.

- `-LogPath`  
  Override the default log file path.

- `-KeyInfoPath`  
  Override the temporary key info file path.

- `-OsFamilyVariableName`, `-OsEditionVariableName`, `-IsAutoEditionVariableName`, `-OemKeyVariableName`  
  Override the names of Task Sequence variables set by the script.

- `-DefaultOsFamily`  
  If `-OsFamily` is not specified and the Task Sequence variable `osFamily` is not set, this sets the default selection in the OS Family combo box (must match a key name in the `$familyOptions` table). Defaults to `"Windows 11"`.

- `-OsFamilyFallback`  
  Sets the fallback display name for OS Family in the GUI if `-OsFamily` is not specified and the Task Sequence variable `osFamily` is not set. Defaults to `"Windows"`.

See the script’s help (`Get-Help .\Select-TSOSEdition.ps1 -Full`) for full parameter details.

---

## 📋 Logging and Verbose Output

- By default, logs are written to the Task Sequence log folder (`%_SMSTSLogPath%`), with the log file name matching the script name.
- Use `-Verbose` for detailed output.
- In testing mode, logging is disabled.

---

## ⚡ Quick Summary

- Single script for dynamic Windows edition selection at deployment time.
- Unified SCCM Task Sequence to support multiple editions.
- Manual or automatic edition selection.
- Supports Windows 8, 8.1, 10, and 11 deployments.
- ServiceUI.exe required for UI presentation during Task Sequence.
- Logs written to Task Sequence log path for production use.

---

## ⚠️ Legal Notice

This toolset is intended for **testing and educational purposes only**.  
Use responsibly.  
ShowKeyPlus is a third-party tool. Respect its licensing and usage terms as published by its author at [Superfly-Inc GitHub](https://github.com/Superfly-Inc).

---

✅ Enjoy smarter and more flexible SCCM deployments!