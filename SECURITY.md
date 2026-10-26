# Security Policy

## Supported versions

Only the latest release of LidBlur receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems. Instead, use GitHub's [private vulnerability reporting](https://github.com/Pallavrai/LidBlur/security/advisories/new) for this repository.

Include the LidBlur version, your macOS version, and steps to reproduce. You can expect an initial response within seven days.

## Scope

LidBlur requests no entitlements, runs with the hardened runtime, makes no network connections, and asks for no privacy permissions. Reports are especially welcome if LidBlur:

- triggers a permission prompt
- reads more than the lid-angle sensor and input idle time
- can leave the screen obscured with no way to recover
