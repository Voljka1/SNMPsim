# SNMP Manager

A PowerShell-based automation tool for managing `snmpsim` environments. This script handles the heavy lifting of creating a stable Python virtual environment, applying necessary patches for SNMPv3 support, and providing a streamlined menu for recording and replaying SNMP simulations.

---

## 🚀 Features

*   **Automated Environment Setup**: Automatically creates a virtual environment using Python 3.11 or 3.12 via the Python Launcher (`py`).
*   **Dependency Management**: Installs pinned, stable versions of `snmpsim`, `pysnmp`, and required libraries.
*   **SNMPv3 Patching**: Includes a built-in Python-driven patch to unlock SNMPv3 recording capabilities in `snmpsim`.
*   **Capture Mode**: Interactive UI to record SNMP data from a target device (v1, v2c, or v3).
*   **Replay Mode**: Quickly launch a simulation server using recorded `.snmprec` files.
*   **Venv Shell**: Easily drop into a pre-configured shell with all SNMP tools in your path.

---

## 🛠 Prerequisites

*   **Windows PowerShell** (Run as Administrator if necessary for file permissions).
*   **Python Launcher (`py.exe`)**: Ensure you have Python **3.11** or **3.12** installed. 
    *   *Note: Python 3.13+ is currently not supported for these dependencies.*
    *   [Download Python for Windows](https://www.python.org/downloads/windows/)

---

## 📖 How to Use

1.  **Download** sim.ps1 to your local machine.
2.  **Run the script**:
    ```powershell
    .\sim.ps1
    ```
3.  **Environment Setup**: On the first run, the script will automatically build the `snmp_env_stable` folder and install all dependencies.

### Main Menu Options

| Option | Name | Description |
| :--- | :--- | :--- |
| **[1]** | **Capture** | Record a real device. Enter the IP and credentials (v1/v2c community or v3 JSON). |
| **[2]** | **Replay** | Start a simulator. It listens on port `1161`. The community string matches the filename. |
| **[3]** | **Shell** | Opens a sub-shell with the virtual environment activated for manual CLI work. |
| **[0]** | **Exit** | Close the manager. |

---

## 📂 SNMPv3 Configuration
When capturing via SNMPv3, the script will ask for a path to a JSON file. Use the following format:
```json
{
    "user": "myUser",
    "auth_protocol": "md5",
    "auth_key": "authpass",
    "priv_protocol": "des",
    "priv_key": "privpass"
}
```

---

## 🔧 Technical Details

*   **Pinned Versions**:
    *   `snmpsim`: 1.1.7
    *   `pysnmp`: 6.2.6

---

## 📝 Notes
*   **Author**: Voljka + Copilot.
*   **Version**: 1.2.1
*   The script uses a "Silent Operator" approach for the environment; once configured, it simply works without manual intervention.
```
