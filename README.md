# Linux Patch and Package Compliance Checker

A Linux support toolkit for auditing package compliance and repairing package-manager or update problems on APT, DNF and YUM systems.

## Audit script

```bash
chmod +x src/linux_patch_compliance.sh
sudo ./src/linux_patch_compliance.sh
```

Refresh metadata during an audit:

```bash
sudo ./src/linux_patch_compliance.sh --refresh-metadata
```

## Repair script

Preview package-manager repair:

```bash
chmod +x src/linux_patch_repair.sh
sudo ./src/linux_patch_repair.sh --repair-manager --dry-run
```

Repair package-manager state and refresh metadata:

```bash
sudo ./src/linux_patch_repair.sh --repair-manager --refresh
```

Install security updates or all updates:

```bash
sudo ./src/linux_patch_repair.sh --install-security
sudo ./src/linux_patch_repair.sh --install-all
```

Clean package-manager caches:

```bash
sudo ./src/linux_patch_repair.sh --clean-cache
```

## What the repair does

- Detects APT, DNF or YUM.
- Repairs interrupted dpkg configuration and broken APT dependencies.
- Checks DNF or YUM package state and refreshes metadata.
- Installs security-only updates where the platform provides a supported mechanism.
- Can install all available package updates.
- Can clean package-manager caches.
- Records package state before and after repair and returns clear exit codes.

## Safety and limitations

Update installation can restart services and may require a system reboot. The script never reboots automatically. APT security-only mode requires the distribution's unattended-upgrade tooling. Review package removals, held packages and application compatibility before broad upgrades.

## Author

Dewald Pretorius — L2 IT Support Engineer
