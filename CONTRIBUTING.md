# Contributing to Windsurf Trial Reset Tool

Thank you for your interest in contributing to this project! We welcome contributions from the community.

## 📋 Table of Contents
- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Reporting Issues](#reporting-issues)

## 🤝 Code of Conduct

This project follows a simple code of conduct:
- Be respectful and inclusive
- Focus on constructive feedback
- Respect the educational purpose of this tool
- Do not encourage misuse or illegal activities

## 🚀 How to Contribute

### Types of Contributions
- 🐛 **Bug fixes**
- ✨ **New features**
- 📚 **Documentation improvements**
- 🧪 **Testing improvements**
- 🔧 **Code quality improvements**

### Getting Started
1. Fork the repository
2. Clone your fork: `git clone https://github.com/abushaidislam/windsurf-trial-reset.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test thoroughly
6. Submit a pull request

## 🛠️ Development Setup

### Prerequisites
- Windows 10/11
- PowerShell 5.1 or higher
- Windsurf editor installed
- Git

### Local Development
```powershell
# Clone the repository
git clone https://github.com/abushaidislam/windsurf-trial-reset.git
cd windsurf-trial-reset

# Make your changes to the scripts
# Test on your local machine
# Ensure backups are created automatically
```

## 🧪 Testing

### Manual Testing Checklist
- [ ] Tool runs without errors on Windows 10/11
- [ ] Backup files are created successfully
- [ ] Original files can be restored from backups
- [ ] Windsurf restarts normally after modification
- [ ] No data loss occurs
- [ ] Tool handles edge cases gracefully

### Testing Commands
```powershell
# Test the simple reset tool
.\windsurf_reset.ps1

# Test with skip backup option
.\windsurf_reset.ps1 -SkipBackup

# Verify backup restoration
# (Manually check backup files are created)
```

## 📝 Submitting Changes

### Pull Request Process
1. **Update documentation** if needed
2. **Add tests** for new functionality
3. **Ensure code quality** and consistency
4. **Test on multiple Windows versions** if possible
5. **Update CHANGELOG.md** if applicable

### Commit Message Format
```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Testing
- `chore`: Maintenance

Examples:
```
feat: add automatic backup verification
fix: resolve PowerShell execution policy issues
docs: update installation instructions
```

## 🐛 Reporting Issues

### Bug Reports
Please use the [bug report template](.github/ISSUE_TEMPLATE/bug-report.md) when reporting issues.

### Feature Requests
Use GitHub issues to request new features. Please:
- Check existing issues first
- Provide clear description
- Explain the use case
- Suggest implementation if possible

## 🔒 Security Considerations

- Never commit sensitive data
- Test all changes thoroughly
- Consider the impact on user data
- Maintain user privacy and security

## 📞 Getting Help

- 📧 **Email**: your-email@example.com
- 💬 **Issues**: [GitHub Issues](https://github.com/abushaidislam/windsurf-trial-reset/issues)
- 📖 **Documentation**: [README.md](README.md)

## 🙏 Recognition

Contributors will be acknowledged in the README and potentially added to a contributors file.

Thank you for contributing to this educational project! 🎉