# Security

Do not include credentials, subscription URLs, private configurations, partition images or packet captures in issues.

The editor listens on loopback and has no authentication for network access. Keep it bound to localhost. Generated files under `local/` may contain credentials and are excluded from Git.

Reference router scripts require integration and can interrupt connectivity. Review their dependencies and keep a recovery path before running them.

Report vulnerabilities through GitHub private vulnerability reporting when available. Otherwise, open an issue requesting a private contact without posting exploit details or secrets.
