# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of Windsurf Trial Reset Tool
- Windows PowerShell scripts for trial period reset
- Automatic backup creation and restoration
- Simple reset tool (`windsurf_reset.ps1`) for easy use
- Comprehensive documentation and disclaimers
- GitHub issue templates and contributing guidelines

### Changed
- Converted from go-cursor-help to work with Windsurf editor
- Updated all references from Cursor to Windsurf
- Modified directory paths for Windsurf configuration
- Updated telemetry keys to match Windsurf's data structure
- Cleaned up codebase to be Windows-focused

### Removed
- macOS and Linux specific scripts (Windows-only release)
- Commercial content and pricing information
- Unnecessary platform-specific files

## [1.0.0] - 2024-04-29

### Added
- Complete conversion from Cursor to Windsurf compatibility
- Simple and advanced reset options
- Automatic backup system
- Comprehensive error handling
- Cross-platform architecture (currently Windows-only)

### Technical Details
- Modified telemetry keys: `machineId`, `devDeviceId`, `macMachineId`, `sqmId`
- Updated configuration paths for Windsurf
- Added safety checks and validation
- Implemented progress tracking and logging

---

## Development Notes

This tool is based on community research and is provided for educational purposes only. Users should understand the risks of modifying application data and accept full responsibility for usage.

For more information, see [README.md](README.md).