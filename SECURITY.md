# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Scope

Lantern is a **local** menu bar utility:

- Binds a reverse proxy on your Mac (default port 80 or 8787)
- Advertises Bonjour / mDNS names on your LAN
- Exposes a **loopback-only** control API on `127.0.0.1:19247`

It is intended for trusted home/office LANs, not hostile public networks.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Email or privately message the maintainer with:

- Description and impact
- Steps to reproduce
- Affected version / commit

We will acknowledge receipt as soon as practical and work on a fix before any disclosure.
