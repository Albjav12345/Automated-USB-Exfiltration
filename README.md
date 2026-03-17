# Secure USB Vault Agent

An automated, headless Windows agent designed for secure, ephemeral data capture and cloud vaulting from physical USB media. 

This project was developed to demonstrate secure automation, background process management (OPSEC), and safe credential handling using native Windows APIs and AWS S3 architecture.

## 🛡️ Security & Architecture Highlights

This tool is built with a security-first mindset, focusing on minimizing the attack surface and leaving zero residual data:

* **Living off the Land (LotL):** Uses zero unauthorized third-party binaries. The core engine relies entirely on native `CIM/WMI` instances for hardware polling, `Robocopy` for robust I/O operations, and native `PowerShell` runspaces.
* **Secure Credential Handling:** API keys are **never** hardcoded or stored in plaintext files. The installation wizard prompts for inputs dynamically and leverages the AWS module's secure credential store (`Set-AWSCredential -StoreAs default`).
* **Ephemeral Processing & OPSEC:** Data is staged locally, compressed via Zip64, encrypted in transit (TLS to Backblaze B2), and immediately purged. Robust `finally` blocks and lock-file mechanisms ensure no residual artifacts or zombie processes remain on the host disk, even in the event of a critical failure.
* **Concurrency & Mutex Locks:** Implements file-based locking (`.lock`) to prevent race conditions and multi-instance execution conflicts during rapid USB insertion/removal cycles.

## ⚙️ Technical Workflow

1. **Hardware Polling:** Monitors `Win32_LogicalDisk` via CIM instances for state changes (DriveType=2).
2. **Data Acquisition:** Triggers isolated background jobs for data staging, validating exit codes to detect physical sector read errors.
3. **Packaging:** Compresses the payload using the `System.IO.Compression.FileSystem` namespace.
4. **Cloud Exfiltration:** Pushes the payload to a designated S3-compatible bucket (Backblaze B2) enforcing `ForcePathStyle`.
5. **Sanitization:** Aggressive cleanup of the temporary staging environment `%TEMP%\USBBackupTemp`.

## 🧪 Testing Environment & Performance

The multi-threaded background processing has been stress-tested to ensure it does not bottleneck host system resources or trigger anomalous CPU usage alerts. 

* **Test Bench:** AMD Ryzen 5 7600X, 32GB RAM DDR5 @ 6000MHz.
* **Payloads:** Successfully vaulted 6GB+ mixed-file physical drives.
* **Impact:** Imperceptible CPU overhead during the background monitoring phase; efficient multi-thread utilization during the Zip64 compression phase.

## 🚀 Deployment (For Authorized Use)

*Run from an elevated or standard context (Execution policies are scoped to `CurrentUser` to adhere to the Principle of Least Privilege).*

1. Execute `USB_Backup_Agent.bat`.
2. Select **[1] Install / Configure Agent**.
3. Provide the required B2 Vault endpoint and API keys when prompted.
4. The agent will inject a launcher into the CurrentUser Run registry key for persistence and begin headless monitoring.

To completely sanitize the deployment from the host, select **[3] Uninstall Complete Agent** from the CLI menu. This terminates active runspaces, deletes registry persistence, and removes the local execution directory.

## 📄 License
MIT License. Provided for educational and authorized operational use.
