# 🚀 Windsurf Trial Reset Tool

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Windows](https://img.shields.io/badge/platform-Windows-blue.svg)](https://github.com/topics/windows)
[![PowerShell](https://img.shields.io/badge/shell-PowerShell-blue.svg)](https://github.com/topics/powershell)
[![GitHub stars](https://img.shields.io/github/stars/abushaidislam/windsurf-trial-reset)](https://github.com/abushaidislam/windsurf-trial-reset/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/abushaidislam/windsurf-trial-reset)](https://github.com/abushaidislam/windsurf-trial-reset/issues)

**⚠️ EDUCATIONAL PURPOSES ONLY - USE AT YOUR OWN RISK**

[📖 How It Works](#-how-it-works) • [🚀 Quick Start](#-quick-start) • [🔧 Technical Details](#-technical-details) • [📋 Troubleshooting](#-troubleshooting)

<img src="https://raw.githubusercontent.com/windsurf-ai/windsurf/main/assets/windsurf-logo.png" alt="Windsurf Logo" width="120" height="120"/>

*Multi-layered device identification reset tool with JavaScript runtime hook injection*

</div>

---

## ⚠️ **Important Disclaimer**

<div align="center">

### **This tool is for educational purposes only!**

**By using this tool, you acknowledge that:**
- You understand the risks of modifying application data and system registry
- You accept full responsibility for any consequences including account suspension
- This tool may violate Windsurf's Terms of Service
- The authors are not responsible for any issues, data loss, or bans that may arise

**Use at your own risk. The authors assume no liability.**

</div>

---

## 🔬 How It Works

This tool implements a **6-layer device identification modification system** to completely reset Windsurf's machine fingerprinting:

### Layer 1: Configuration File Modification
Modifies `storage.json` telemetry identifiers:
- `telemetry.machineId` — Main machine identifier (64-char hex)
- `telemetry.macMachineId` — MAC-based machine identifier
- `telemetry.devDeviceId` — Device UUID
- `telemetry.sqmId` — Windows SQM (Software Quality Metrics) ID
- `storage.serviceMachineId` — Service-specific machine ID
- `telemetry.firstSessionDate` — Resets first session timestamp

### Layer 2: Windows Registry Modification
Changes system-level machine identifier:
- **Path**: `HKLM\SOFTWARE\Microsoft\Cryptography`
- **Key**: `MachineGuid`
- Creates automatic registry backups before modification

### Layer 3: Auxiliary File Modification
Updates additional identifier files:
- `machineid` — Windsurf's machine ID file (set to read-only)
- `.updaterId` — Updater device identifier (set to read-only)

### Layer 4: JavaScript Kernel Injection (Advanced)
**Triple-method approach** for deep device identification interception:

| Method | Target | Technique |
|--------|--------|-----------|
| **A** | Placeholder Replacement | Replaces `someValue` anchors in minified JS |
| **B** | Function Rewrite | Directly patches machine code source functions (b6) |
| **C** | Loader Stub + External Hook | Injects `windsurf_hook.js` into main process |

### Layer 5: Runtime Hook Module (`windsurf_hook.js`)
Intercepts device identifier generation at runtime via:
- `child_process.execSync` — Intercepts REG.exe MachineGuid queries
- `crypto.createHash` — Intercepts SHA256 hash calculations for machineId
- `@vscode/deviceid` — Intercepts devDeviceId retrieval
- `@vscode/windows-registry` — Intercepts registry reads
- `os.networkInterfaces` — Returns virtual MAC addresses
- `fs.writeFileSync/writeFile` — Protects telemetry fields from being overwritten

### Layer 6: File Protection & Persistence
- Sets modified files to **read-only** to prevent Windsurf from overwriting
- Disables auto-update to prevent ID regeneration
- Creates timestamped backups with automatic retry logic

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔁 **Dual Execution Modes** | "Modify Only" (keep data) or "Reset + Modify" (clean slate) |
| 🪟 **Windows Only** | Full PowerShell support with UAC elevation, registry modification |
| 🛡️ **Atomic Operations** | 3-retry mechanism with automatic backup restoration on failure |
| 🪝 **JS Runtime Hooking** | Injects persistent hooks into Windsurf's Node.js runtime |
| 🔒 **Write Protection** | Sets config files to read-only to prevent overwriting |
| 🚫 **Update Disable** | Optional auto-update blocker |
| 🔧 **Automatic Backups** | Timestamped backups to `%APPDATA%\Windsurf\User\globalStorage\backups\` |
| 🌐 **Multi-Domain Download** | Automatic mirror fallback for script downloads |

---

## 🚀 Quick Start

### Windows (PowerShell - Admin)
```powershell
# Quick one-liner (downloads and executes automatically)
irm https://raw.githubusercontent.com/abushaidislam/windsurf-trial-reset/main/scripts/run/windsurf_win_id_modifier.ps1 | iex

# Or download and run locally
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/abushaidislam/windsurf-trial-reset/main/windsurf_reset.ps1" -OutFile "windsurf_reset.ps1"
powershell -ExecutionPolicy Bypass -File "windsurf_reset.ps1"
```

> **Note**: The script will automatically detect your Windsurf installation path. If detection fails, you'll be prompted to manually select the installation directory.

---

## 🌐 Remote Execution

You can run this tool **without downloading** using PowerShell:

```powershell
irm https://raw.githubusercontent.com/abushaidislam/windsurf-trial-reset/main/scripts/run/windsurf_win_id_modifier.ps1 | iex
```

**How it works:**
- Downloads the script directly from GitHub (raw content)
- Pipes it to PowerShell (`| iex` = Invoke-Expression)
- Executes immediately in memory
- No local file left behind

---

## 🔧 Technical Details

### Modified Files

| File | Location | Purpose |
|------|----------|---------|
| `storage.json` | `%APPDATA%\Windsurf\User\globalStorage\` | Main telemetry configuration |
| `machineid` | `%APPDATA%\Windsurf\` | Service machine identifier |
| `.updaterId` | `%APPDATA%\Windsurf\` | Updater device identifier |
| `MachineGuid` | Registry `HKLM\SOFTWARE\Microsoft\Cryptography` | System machine GUID |

### Execution Modes

When running the PowerShell script, you'll be presented with two options:

| Mode | Description | Use Case |
|------|-------------|----------|
| **1 - Modify Only** | Updates IDs without deleting any data | Preserve settings, just reset trial |
| **2 - Reset + Modify** | Deletes Windsurf folders, restarts app, then modifies IDs | Clean slate, fixes "lost Pro status" issues |

### ID Configuration Methods

The tool generates device identifiers using the following priority:

1. **Environment Variables** (if set):
   - `WINDSURF_MACHINE_ID`
   - `WINDSURF_MAC_MACHINE_ID`
   - `WINDSURF_DEV_DEVICE_ID`
   - `WINDSURF_SQM_ID`
   - `WINDSURF_MACHINE_GUID`

2. **Config File** (`~/.windsurf_ids.json`):
   ```json
   {
     "machineId": "64-char-hex-string",
     "macMachineId": "64-char-hex-string",
     "devDeviceId": "uuid-v4",
     "sqmId": "{UUID-UPPERCASE}",
     "machineGuid": "uuid-v4"
   }
   ```

3. **Auto-Generation** (default): Cryptographically secure random values

### Backup & Safety

- Automatic backups created at: `%APPDATA%\Windsurf\User\globalStorage\backups\`
- Backup naming: `storage.json.backup_YYYYMMDD_HHMMSS`
- Registry backup: `MachineGuid.backup_YYYYMMDD_HHMMSS`
- **3-retry mechanism**: If modification fails, automatically restores from backup and retries
- All modified files are set to read-only after successful operation

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Quick Contribution Guide
1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Development Setup
```bash
# Clone and setup
git clone https://github.com/abushaidislam/windsurf-trial-reset.git
cd windsurf-trial-reset

# Make your changes
# Test on your system
# Submit PR
```

## 📋 Issues and Support

- 🐛 **Bug Reports**: [Create an issue](.github/ISSUE_TEMPLATE/bug-report.md)
- 💡 **Feature Requests**: [Create an issue](https://github.com/abushaidislam/windsurf-trial-reset/issues)
- 🤔 **Questions**: Check [existing issues](https://github.com/abushaidislam/windsurf-trial-reset/issues) first

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note**: While the code is open source, the tool's purpose may conflict with Windsurf's Terms of Service. Use responsibly.

## ⚖️ Legal Disclaimer

This tool is provided "as is" without warranty of any kind. The authors are not responsible for:

- Any damages or data loss
- Violation of Windsurf's terms of service
- Account suspension or termination
- Any other consequences of use

**By using this tool, you accept all risks and responsibilities.**

## 🙏 Acknowledgments

- Original work based on community research
- Thanks to contributors and testers
- Built for educational purposes

---

<div align="center">

**Made with ❤️ for the developer community**

[⭐ Star this repo](https://github.com/abushaidislam/windsurf-trial-reset) • [🐛 Report Issues](https://github.com/abushaidislam/windsurf-trial-reset/issues) • [📧 Contact](mailto:abushaidislam@gmail.com)

</div>

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Script cannot be loaded" | Run PowerShell as Administrator |
| "Windsurf not found" | Manually specify installation path when prompted |
| Registry modification fails | Ensure you're running with admin privileges |
| IDs reset but trial still expired | Use "Reset + Modify" mode for clean slate |

### Running as Administrator

**Method 1: Win + X**
1. Press `Win + X`
2. Select "Terminal (Administrator)" or "PowerShell (Administrator)"

**Method 2: Search**
1. Press `Win`, type `powershell` or `pwsh`
2. Right-click → "Run as administrator"

---


