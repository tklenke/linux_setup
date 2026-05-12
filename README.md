# linux_setup

Interactive Debian setup script for WSL, dev servers, homelab servers, and AWS instances.

## Usage

```bash
bash setup.sh
```

Safe to rerun on a partially configured machine — all steps check before acting.

## What it does

**Base (all machine types)**
- Installs: `curl`, `git`, `python3`, `python3-pip`
- Adds bash aliases: `ll`, `la`, `..`, `...`, colored `grep`
- Sets a minimal prompt showing current directory and git branch
- Configures global git settings (prompts for name/email if not already set)
- Adds a login banner showing hostname, date, and last 10 logins

**WSL** (auto-detected)
- Symlinks `~/Downloads` to your Windows Downloads folder
- Detects your Windows username from `/mnt/c/Users/` — you can override the path at runtime

**Dev server**
- Installs [Claude Code](https://claude.ai/code)

**Homelab server**
- Installs `docker`, `docker-compose`

**AWS / cloud server**
- Installs `docker`, `docker-compose`, `nginx`, AWS CLI v2

## Notes

- Docker group membership takes effect on next login (`newgrp docker` to apply immediately)
- AWS CLI is installed but not configured — run `aws configure` or use an IAM instance role
