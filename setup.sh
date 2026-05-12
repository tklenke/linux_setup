#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — Debian machine setup (WSL, homelab, dev, or AWS)
# Safe to rerun — all steps check before acting.
# ─────────────────────────────────────────────────────────────────────────────

# ── helpers ───────────────────────────────────────────────────────────────────

log() { echo "[setup] $*"; }
ok()  { echo "[ok]    $*"; }
ask() { read -rp "$1 " "$2"; }

# Append a block to a file only if a unique marker line isn't already present.
# This makes every .bashrc addition idempotent — safe to rerun.
append_once() {
    local file="$1" marker="$2" content="$3"
    if grep -qF "$marker" "$file" 2>/dev/null; then
        ok "already present in $file: $marker"
    else
        printf '\n%s\n' "$content" >> "$file"
        log "added to $file: $marker"
    fi
}

# ── detect WSL automatically ──────────────────────────────────────────────────

if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
else
    IS_WSL=false
fi

# ── gather all inputs upfront ─────────────────────────────────────────────────

echo ""
echo "Which type of machine is this?"
echo "  1) Base only"
echo "  2) Dev server"
echo "  3) Homelab server"
echo "  4) AWS / cloud server"
echo ""
ask "Enter number (default 1):" MACHINE_TYPE
MACHINE_TYPE="${MACHINE_TYPE:-1}"

# If WSL, resolve the Windows Downloads path before showing the summary
WIN_DOWNLOADS=""
if $IS_WSL; then
    # Try to detect the Windows username — filter out built-in system folders
    DETECTED_WIN_USER=$(ls /mnt/c/Users/ 2>/dev/null \
        | grep -vE "^(Public|Default|Default User|All Users|desktop\.ini)$" \
        | head -1 || true)

    if [ -n "$DETECTED_WIN_USER" ]; then
        ask "Windows username [$DETECTED_WIN_USER]:" WIN_USER
        WIN_USER="${WIN_USER:-$DETECTED_WIN_USER}"
    else
        ask "Windows username:" WIN_USER
    fi

    DEFAULT_DOWNLOADS="/mnt/c/Users/$WIN_USER/Downloads"
    ask "Windows Downloads path [$DEFAULT_DOWNLOADS]:" WIN_DOWNLOADS
    WIN_DOWNLOADS="${WIN_DOWNLOADS:-$DEFAULT_DOWNLOADS}"
fi

# ── show summary and confirm ──────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════"
echo " Setup plan"
echo "══════════════════════════════════════════"
echo " Environment : $([ "$IS_WSL" = true ] && echo WSL || echo baremetal/server)"
echo ""
echo " Base (all machines):"
echo "   - Packages: curl, git, python3, python3-pip"
echo "   - Bash aliases: ll, la, .., ..., grep"
echo "   - Prompt: dir + git branch"
echo "   - Git config: name/email (prompt if unset), editor, defaults"
echo "   - Login banner: hostname + last 10 logins"

if $IS_WSL; then
    echo ""
    echo " WSL:"
    echo "   - Symlink ~/Downloads -> $WIN_DOWNLOADS"
fi

case "$MACHINE_TYPE" in
    2) echo ""; echo " Dev server:"; echo "   - Claude Code" ;;
    3) echo ""; echo " Homelab server:"; echo "   - docker, docker-compose" ;;
    4) echo ""; echo " AWS / cloud server:"; echo "   - docker, docker-compose, nginx, AWS CLI v2" ;;
esac

echo "══════════════════════════════════════════"
echo ""
ask "Proceed? (y/N):" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# BASE — runs on every machine type
# ══════════════════════════════════════════════════════════════════════════════

# ── packages ──────────────────────────────────────────────────────────────────

log "Updating package lists..."
sudo apt-get update -qq

# apt-get install is idempotent — safe to rerun
log "Installing base packages..."
sudo apt-get install -y curl git python3 python3-pip

# ── aliases ───────────────────────────────────────────────────────────────────

BASHRC="$HOME/.bashrc"

# Debian's default .bashrc often has ll/la commented out — we add our own
# block so they're always present and consistent regardless of distro defaults
append_once "$BASHRC" "# linux_setup: aliases" \
'# linux_setup: aliases
alias ll="ls -lhF --color=auto"
alias la="ls -lhAF --color=auto"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"'

# ── prompt ────────────────────────────────────────────────────────────────────

# Shows: ~/current/dir (git-branch) $
# No hostname — the terminal tab/title already shows which machine you're on.
# \[\e[...m\] wrappers are required by bash to correctly calculate line length.
append_once "$BASHRC" "# linux_setup: prompt" \
'# linux_setup: prompt
_git_branch() {
    git branch 2>/dev/null | grep "^\*" | sed "s/\* //"
}
_ps1_branch() {
    local b; b=$(_git_branch)
    [ -n "$b" ] && echo " ($b)"
}
PS1="\[\e[32m\]\w\[\e[33m\]\$(_ps1_branch)\[\e[0m\] \$ "'

# ── git config ────────────────────────────────────────────────────────────────

# Only prompt for name/email if not already set
GIT_NAME=$(git config --global user.name 2>/dev/null || true)
GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [ -z "$GIT_NAME" ]; then
    ask "Git user.name:" GIT_NAME
    git config --global user.name "$GIT_NAME"
else
    ok "git user.name already set: $GIT_NAME"
fi

if [ -z "$GIT_EMAIL" ]; then
    ask "Git user.email:" GIT_EMAIL
    git config --global user.email "$GIT_EMAIL"
else
    ok "git user.email already set: $GIT_EMAIL"
fi

# These are safe to set unconditionally — they're sensible defaults
git config --global core.editor "${EDITOR:-nano}"
git config --global init.defaultBranch main
git config --global pull.rebase false

# ── login banner ──────────────────────────────────────────────────────────────

# On every interactive login: show hostname, date, and the last 10 logins
# (who logged in, from where, and when). Useful on shared or remote machines.
append_once "$BASHRC" "# linux_setup: login banner" \
'# linux_setup: login banner
if [ -n "$PS1" ]; then
    echo ""
    echo "  Host : $(hostname)"
    echo "  Date : $(date)"
    echo ""
    echo "Recent logins:"
    last -n 10 --time-format iso 2>/dev/null || last -n 10
    echo ""
fi'

# ══════════════════════════════════════════════════════════════════════════════
# WSL — applied automatically when WSL is detected, regardless of machine type
# ══════════════════════════════════════════════════════════════════════════════

if $IS_WSL; then
    log "Applying WSL tweaks..."

    LINK="$HOME/Downloads"

    if [ -L "$LINK" ]; then
        ok "~/Downloads symlink already exists"
    elif [ -d "$LINK" ]; then
        log "~/Downloads is a real directory — skipping symlink to avoid clobbering"
    elif [ -d "$WIN_DOWNLOADS" ]; then
        ln -s "$WIN_DOWNLOADS" "$LINK"
        log "symlinked ~/Downloads -> $WIN_DOWNLOADS"
    else
        log "Path not found: $WIN_DOWNLOADS — skipping symlink"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# DEV SERVER module
# ══════════════════════════════════════════════════════════════════════════════

if [ "$MACHINE_TYPE" = "2" ]; then
    log "Installing dev tools..."

    if command -v claude &>/dev/null; then
        ok "claude already installed: $(command -v claude)"
    else
        log "Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# HOMELAB SERVER module
# ══════════════════════════════════════════════════════════════════════════════

if [ "$MACHINE_TYPE" = "3" ]; then
    log "Installing homelab tools..."

    sudo apt-get install -y docker.io docker-compose

    # Add current user to docker group so docker runs without sudo.
    # Takes effect on next login, not immediately.
    sudo usermod -aG docker "$USER"
    log "Added $USER to docker group — log out and back in for this to take effect"
fi

# ══════════════════════════════════════════════════════════════════════════════
# AWS / CLOUD SERVER module
# ══════════════════════════════════════════════════════════════════════════════

if [ "$MACHINE_TYPE" = "4" ]; then
    log "Installing AWS / cloud tools..."

    sudo apt-get install -y docker.io docker-compose nginx

    sudo usermod -aG docker "$USER"
    log "Added $USER to docker group — log out and back in for this to take effect"

    if command -v aws &>/dev/null; then
        ok "aws cli already installed: $(aws --version)"
    else
        log "Installing AWS CLI v2..."
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
        unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
        sudo /tmp/awscliv2/aws/install
        rm -rf /tmp/awscliv2.zip /tmp/awscliv2
        log "AWS CLI installed — run 'aws configure' or attach an IAM role to set credentials"
    fi
fi

# ── done ──────────────────────────────────────────────────────────────────────

echo ""
log "Done. Run: source ~/.bashrc"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# NOTES
# ─────────────────────────────────────────────────────────────────────────────
#
# Idempotency strategy:
#   - apt-get install is safe to rerun by nature
#   - .bashrc additions use append_once() with a unique marker comment as guard
#   - git config only prompts if the value isn't already set
#   - symlinks check for existing link, real dir, and missing source path
#   - binary installs check command -v before running the installer
#
# Prompt design:
#   No hostname in PS1 — terminal tabs/titles already show the machine name.
#   Git branch only appears when inside a git repo.
#
# WSL Downloads symlink:
#   Username is detected from /mnt/c/Users/ at runtime (filters out system
#   folders like Public, Default). User can override the detected name and path.
#
# Docker group:
#   usermod -aG docker takes effect on next login. Until then, prefix docker
#   commands with sudo or run: newgrp docker
#
# AWS CLI:
#   Installs the official v2 binary. Does not configure credentials.
#   On EC2, prefer IAM instance roles over stored keys.
#   On non-EC2, run: aws configure
#
# Claude Code:
#   Installed via: curl -fsSL https://claude.ai/install.sh | bash
#   No node/npm dependency as of 2025-05.
