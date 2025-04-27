# Get-TSOSEdition Toolset

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Language: PowerShell](https://img.shields.io/badge/Language-PowerShell-blue.svg)](https://learn.microsoft.com/en-us/powershell/)
[![Built With: PowerShell 5+](https://img.shields.io/badge/Built%20With-PowerShell%205+-blueviolet.svg)](https://learn.microsoft.com/en-us/powershell/)

---

A set of PowerShell scripts to assist with selecting and detecting the correct Windows edition during SCCM Task Sequences.

These scripts are designed to dynamically set an SCCM Task Sequence variable (`osEdition`) based on user selection or automatic detection using BIOS-embedded product keys (via ShowKeyPlus).

The goal is to allow a single SCCM Task Sequence to intelligently branch and install the correct Windows edition automatically.

These scripts are compatible with Windows 8, Windows 8.1, Windows 10, and Windows 11 deployments.

---

## 📦 Contents

- **Select-TSOSEdition.ps1**  
  Script to manually prompt the user to select the Windows edition.

- **Select-TSOSEdition_withAuto.ps1**  
  Script to automatically detect the Windows edition via BIOS OEM key if available, otherwise prompt the user.

- **Select-TSOSEdition_withAuto_TESTING.ps1**  
  Same as Select-TSOSEdition_withAuto.ps1 but with destructive actions (like setting SCCM Task Sequence variables) commented out for testing purposes.

---

## 🛠 Requirements

- **ShowKeyPlus x64 Version 1.0.7060** is required for edition auto-detection.
- Download from the official GitHub release here:
  [https://github.com/Superfly-Inc/ShowKeyPlus/releases/tag/ShowKeyPlus7060](https://github.com/Superfly-Inc/ShowKeyPlus/releases/tag/ShowKeyPlus7060)

- After downloading:
  - Create a folder named `ShowKeyPlus_x64_1.0.7060` next to the scripts.
  - Place the `ShowKeyPlus.exe` binary directly inside this folder.
  - The folder structure should look like this:

```
Get-TSOSEdition/
├── Select-TSOSEdition.ps1
├── Select-TSOSEdition_withAuto.ps1
├── Select-TSOSEdition_withAuto_TESTING.ps1
├── ShowKeyPlus_x64_1.0.7060/
│   └── ShowKeyPlus.exe
```

⚠️ The folder name `ShowKeyPlus_x64_1.0.7060` is **hardcoded** in the scripts and must match exactly.

---

## 🛠 How It Works

1. Place the three scripts and the ShowKeyPlus_x64_1.0.7060 folder together.

2. Execute the appropriate script during your SCCM Task Sequence:
   - **Select-TSOSEdition.ps1** for manual selection.
   - **Select-TSOSEdition_withAuto.ps1** for automatic detection and fallback to manual selection if needed.

3. The script will set the Task Sequence variable **osEdition** to one of the following values:

| Windows Edition | osEdition Value |
|:---|:---|
| Windows 8/8.1/10/11 Home (Core) | `home` |
| Windows 8/8.1/10/11 Pro | `pro` |
| Windows 8/8.1/10/11 Enterprise | `enterprise` |
| Windows 8/8.1/10/11 Education | `education` |
| Windows 10/11 Pro for Workstations | `prows` |
| Windows 10/11 Pro Education | `proedu` |

4. In your Task Sequence:
   - Add **Install Operating System** steps for each edition you want to support.
   - Add a **Condition** on each step:
     - Example:  
       `Task Sequence Variable osEdition equals home`
     - For Pro Edition:  
       `osEdition equals pro`
     - For Enterprise Edition:  
       `osEdition equals enterprise`
     - And so on.

5. This allows a single Task Sequence to handle installing different Windows editions dynamically based on user input or automatic OEM detection.

---

## ⚡ Quick Summary

- Dynamic Windows edition selection at deployment time.
- Unified single SCCM Task Sequence to support multiple editions.
- Manual or automatic edition selection.
- Supports Windows 8, 8.1, 10, and 11 deployments.
- Small footprint — no heavy dependencies beyond ShowKeyPlus.

---

## ⚠️ Legal Notice

This toolset is intended for **testing and educational purposes only**.  
Use responsibly.  
ShowKeyPlus is a third-party tool. Respect its licensing and usage terms as published by its author at [Superfly-Inc GitHub](https://github.com/Superfly-Inc).

---

✅ Enjoy smarter and more flexible SCCM deployments!
