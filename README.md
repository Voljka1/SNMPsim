# SNMP Simulation Manager

A PowerShell-based automation tool to capture and replay SNMP device configurations using `snmpsim` and `pysnmp`. This manager handles the "Golden Ratio" environment setup automatically, ensuring compatibility even on systems with multiple Python versions (like Python 3.14).

## 🚀 Features

- **Smart Environment Detection**: Automatically scans your system `PATH` for Python 3.11 or 3.12.
- **Auto-VENV Creation**: Builds an isolated environment with validated library versions.
- **SNMP Capture**: Record live device configurations with real-time OID peeking.
- **SNMP Replay**: Host a local SNMP agent on port 1161.
- **Integrated Shell**: Quick access to the managed virtual environment.
- **SNMPv1/v2c/v3 capture**: little patch enabled support for SNMPv3

## ⚠️ Version Stability & Conflict Warning

This project is pinned to specific versions to avoid common "Library Hell" in the SNMP ecosystem:
* **SNMPsim (1.1.7)** & **PySNMP (6.2.6)**: These versions are verified to work together.
* **The Conflict**: Using newer versions of `pysnmp` or `snmpsim` on Python 3.14+ currently triggers fatal `asyncio` loop errors (e.g., `AttributeError: 'ProactorEventLoop' object has no attribute 'add_reader'`).
* **The Solution**: This script enforces a "Safe Haven" environment using Python 3.12 logic to bypass these architectural conflicts.

## 🛡️ Execution Policy (Important)

Windows may block the execution of downloaded scripts. If you receive a "script execution is disabled" error, use one of the following methods:

**Method A: Bypass for current session (Recommended)**
Execute this command in your terminal:
`powershell -ExecutionPolicy Bypass -File .\snmpsim.ps1`

**Method B: Unblock the file manually**
1. Right-click `snmpsim.ps1`.
2. Select **Properties**.
3. Check the **Unblock** checkbox at the bottom.
4. Click **Apply**.

## 📋 Prerequisites

* **Windows 10/11**
* **PowerShell 5.1+**
* **Python 3.12** (Installed and added to your System PATH).

## 🛠️ Usage

1. **Download**: Place `snmpsim.ps1` in your work directory.
2. **Run**: Execute the script using one of the methods in the Execution Policy section.
3. **Initial Setup**: The script will auto-detect Python 3.12 and build the `snmp_env_stable` folder.
4. **Options**:
    - **[1] Capture**: Record from a physical IP. (SNMP v1/v2c/v3)
          -**SNMP v3**: SNMPv3 user and other stuff stored in json file. See example.
    - **[2] Replay**: Start a simulation from a `.snmprec` file.
    - **[3] Shell**: Enter the venv. Type `exit` to return to the menu.

## 🤖 Credits

This script was developed in collaboration with **Gemini**, an AI collaborator from Google. It was designed to bridge the gap between modern Python environments and stable legacy SNMP simulation requirements, ensuring a seamless "one-click" setup.

## 📜 License
MIT License.
