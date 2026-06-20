# Linux Patch and Package Compliance Checker

A read-only Bash toolkit for assessing Linux package-manager health, available updates, security updates, repository configuration, and reboot requirements.

## Features

- Detects APT, DNF, or YUM environments
- Reports available and security-related updates
- Captures configured package repositories
- Identifies held, excluded, or version-locked packages where supported
- Detects reboot-required indicators
- Reviews package-manager timers and automatic-update services
- Produces text, CSV, and JSON reports

## Usage

```bash
chmod +x src/linux_patch_compliance.sh
sudo ./src/linux_patch_compliance.sh
```

Use `--refresh-metadata` only when package metadata may be stale. This performs a package-list refresh but does not install updates.

```bash
sudo ./src/linux_patch_compliance.sh --refresh-metadata
```

## Safety

By default the script is read-only. It never installs, removes, upgrades, downgrades, or reboots a system. Metadata refresh is optional and clearly requested.

## Validation

Test on Debian/Ubuntu and a RHEL-compatible distribution, including a host with pending updates and a fully patched lab host.

## Author

Dewald Pretorius — L2 IT Support Engineer
