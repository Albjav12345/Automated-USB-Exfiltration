# Secure USB Vault Agents (Cloud & Air-Gapped Editions)

An automated, headless Windows agent suite designed for secure, ephemeral data capture and vaulting from physical USB media. 

This repository contains two specialized tools designed to operate silently in the background without relying on third-party software installations. 

---

## 🧰 The Suite

### 1. `USB_Vault_Agent_Cloud.bat` (Cloud Edition)
Designed for connected environments. It automatically detects any inserted USB, stages the data locally, compresses it using Zip64, encrypts it in transit (TLS), and exfiltrates the payload to a Backblaze B2 S3 bucket. It aggressively sanitizes the local staging environment immediately after upload.

### 2. `USB_Vault_Agent_Local.bat` (Air-Gapped / Master Sync Edition)
Designed for strictly offline or forensic environments. It operates in a dual-phase mode:
* **Standard Acquisition:** Rapidly mirrors inserted USBs to a hidden local vault on the host machine (`%USERPROFILE%\Secure_Local_Vault`).
* **Master Consolidation:** When a pre-configured "Master Pendrive" is detected, the agent automatically triggers a multi-threaded transfer of all accumulated local vaults into the Master Drive for physical extraction.

---

## 🛡️ Architecture & OPSEC Highlights

Built with a security-first mindset, focusing on minimizing the attack surface, evading detection, and ensuring robust headless execution:

* **Living off the Land (LotL):** Uses zero unauthorized third-party binaries. The core engine relies entirely on native `CIM/WMI` instances for hardware polling, `Robocopy` for robust I/O operations, and native `PowerShell` runspaces.
* **File-Lock Evasion (Zero-Wait Policy):** Standard I/O operations stall when encountering locked files (e.g., an open document). Bypassing this via Volume Shadow Copies (VSS) requires UAC elevation (breaking OPSEC) and fails on FAT32/exFAT formatted drives. To maintain stealth, the Air-Gapped agent utilizes a `/R:0 /W:0` policy to intelligently bypass locked files, log the omission for auditing, and successfully extract the remaining payload without stalling the execution thread.
* **Secure Credential Handling:** API keys for the Cloud Edition are **never** hardcoded or stored in plaintext files. The wizard prompts for inputs dynamically and leverages the AWS module's secure credential store (`Set-AWSCredential -StoreAs default`).
* **Race-Condition Mitigation:** Implements a 10-second *Boot Buffer* to allow the OS hardware stack to initialize before polling, preventing WMI read failures during rapid boot sequences. Mutex file-locking (`.lock`) prevents multi-instance execution conflicts.

---

## ⚙️ Technical Workflow

1. **Hardware Polling:** Monitors `Win32_LogicalDisk` via CIM instances for state changes (DriveType=2).
2. **Execution Context:** Injects a VBScript launcher into the `CurrentUser` Run registry key for persistence. This ensures headless, windowless execution across reboots without requiring Administrator privileges (adhering to the Principle of Least Privilege).
3. **Data Acquisition:** * *Cloud:* Copies data to `%TEMP%` and compresses the payload using the `System.IO.Compression.FileSystem` namespace before pushing to S3 via `ForcePathStyle`.
   * *Local:* Direct I/O uncompressed mirroring to the secure local vault to minimize CPU footprint and maximize disk write speeds.
4. **Multi-Threaded Consolidation (Local Only):** Utilizes Robocopy's `/MT:8` flag to hyper-thread the transfer from the local host to the physical Master Drive.

---

## 🚀 Quick Start & Deployment

Run from an elevated or standard context. No dependencies required.

1. Download the version you need (`Cloud` or `Local`).
2. Execute the `.bat` file to open the CLI Wizard.
3. Select **[1] Install / Configure Agent**.
4. Follow the interactive prompts:
   * *Cloud Edition:* Input your Backblaze B2 API credentials.
   * *Local Edition:* Input the exact Volume Label of your designated "Master Pendrive".
5. The agent will establish persistence and begin headless monitoring immediately.

*Note: To completely sanitize the deployment from the host, run the script again and select **[3] Uninstall Complete Agent**. This terminates active runspaces, deletes registry persistence, and removes the local execution directory.*

---

## 🧪 Testing Environment & Performance

The multi-threaded background processing has been stress-tested to ensure it does not bottleneck host system resources or trigger anomalous CPU usage alerts during standard user operations.

* **Test Bench:** AMD Ryzen 5 7600X, 32GB RAM DDR5 @ 6000MHz.
* **Payloads:** Successfully vaulted 6GB+ mixed-file physical drives.
* **Impact:** Imperceptible CPU overhead during the background monitoring phase; highly efficient multi-thread utilization during the Zip64 compression and Master Consolidation phases.

---

## 📄 License
MIT License. Provided for educational, portfolio demonstration, and authorized operational use.
