#!/bin/sh
# Installer for acc. Fetch, verify, drop on PATH.
#
#   curl -fsSL https://raw.githubusercontent.com/qassurance408-ui/alet-cli/main/install.sh | sh
#
# Everything is wrapped in functions and main is called on the very last line,
# so a download that gets cut off part way through cannot run half a script.
#
# Environment:
#   ACC_VERSION      tag or branch to install       (default: main)
#   ACC_INSTALL_DIR  where the file goes            (default: ~/.local/bin)
#   ACC_BASE_URL     where to fetch from            (default: raw.githubusercontent.com)
#   ACC_MODIFY_PATH  set to 1 to edit your shell rc (default: just print the line)

set -eu

REPO="qassurance408-ui/alet-cli"
VERSION="${ACC_VERSION:-main}"
INSTALL_DIR="${ACC_INSTALL_DIR:-$HOME/.local/bin}"
BASE_URL="${ACC_BASE_URL:-https://raw.githubusercontent.com/$REPO/$VERSION}"
MIN_PYTHON="3.10"

BOLD=''; RED=''; GREEN=''; GREY=''; RESET=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD='\033[1m'; RED='\033[38;5;196m'; GREEN='\033[38;5;83m'
    GREY='\033[38;5;245m'; RESET='\033[0m'
fi

say()  { printf '  %b\n' "$*"; }
info() { printf '  %b%s%b\n' "$GREY" "$*" "$RESET"; }
die()  { printf '\n  %b✗  %s%b\n\n' "$RED" "$*" "$RESET" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── Prerequisites ─────────────────────────────────────────────────────────────

find_downloader() {
    if have curl; then DL="curl"
    elif have wget; then DL="wget"
    else die "Need curl or wget to download anything. Install one and try again."
    fi
}

find_hasher() {
    if have sha256sum; then HASH="sha256sum"
    elif have shasum; then HASH="shasum -a 256"
    else die "Need sha256sum or shasum to verify the download."
    fi
}

# The one real dependency. acc uses 'str | None' syntax, so 3.10 is the floor.
find_python() {
    for candidate in python3 python; do
        if have "$candidate" && "$candidate" -c \
            'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
            >/dev/null 2>&1; then
            PYTHON="$candidate"
            return 0
        fi
    done

    printf '\n  %b✗  acc needs Python %s or newer.%b\n\n' "$RED" "$MIN_PYTHON" "$RESET" >&2
    if have python3; then
        info "Found $(python3 -V 2>&1), which is too old."
    else
        info "No python3 on PATH."
    fi
    printf '\n' >&2
    info "Debian / Ubuntu:  sudo apt install python3"
    info "Fedora / RHEL:    sudo dnf install python3"
    info "Arch:             sudo pacman -S python"
    printf '\n' >&2
    exit 1
}

# ── Download ──────────────────────────────────────────────────────────────────

fetch() {
    # fetch <url> <dest>
    # Their error text is swallowed because the caller prints a better one.
    if [ "$DL" = "curl" ]; then
        curl -fsSL "$1" -o "$2" 2>/dev/null || return 1
    else
        wget -qO "$2" "$1" 2>/dev/null || return 1
    fi
}

download() {
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT INT TERM

    info "Fetching acc ($VERSION)..."
    fetch "$BASE_URL/acc" "$TMP/acc" \
        || die "Could not download acc from $BASE_URL/acc"
    fetch "$BASE_URL/SHA256SUMS" "$TMP/SHA256SUMS" \
        || die "Could not download the checksum file from $BASE_URL/SHA256SUMS"
}

verify() {
    info "Verifying checksum..."
    expected="$(awk '$2 == "acc" || $2 == "*acc" { print $1 }' "$TMP/SHA256SUMS")"
    [ -n "$expected" ] || die "The checksum file has no entry for acc."

    actual="$(cd "$TMP" && $HASH acc | awk '{print $1}')"
    if [ "$expected" != "$actual" ]; then
        printf '\n  %b✗  Checksum mismatch. Not installing.%b\n\n' "$RED" "$RESET" >&2
        info "expected  $expected"
        info "got       $actual"
        printf '\n' >&2
        exit 1
    fi

    # A captive portal or proxy can answer 200 with an HTML page, which would
    # sail past a checksum built from that same page. These two catch it.
    case "$(head -n 1 "$TMP/acc")" in
        '#!/usr/bin/env python3') ;;
        *) die "That download does not look like acc. Check your network." ;;
    esac
    "$PYTHON" -m py_compile "$TMP/acc" 2>/dev/null \
        || die "The downloaded file is not valid Python. Refusing to install it."
    rm -rf "$TMP/__pycache__"
}

# ── Install ───────────────────────────────────────────────────────────────────

install_it() {
    mkdir -p "$INSTALL_DIR" || die "Could not create $INSTALL_DIR"
    [ -w "$INSTALL_DIR" ] || die "$INSTALL_DIR is not writable. Set ACC_INSTALL_DIR to somewhere you own."

    DEST="$INSTALL_DIR/acc"
    chmod 755 "$TMP/acc"
    mv -f "$TMP/acc" "$DEST" || die "Could not write $DEST"
    info "Installed to $DEST"
}

# ── PATH ──────────────────────────────────────────────────────────────────────

on_path() {
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) return 0 ;;
        *) return 1 ;;
    esac
}

rc_file() {
    case "${SHELL:-}" in
        */zsh)  printf '%s' "$HOME/.zshrc" ;;
        */bash) printf '%s' "$HOME/.bashrc" ;;
        *)      printf '%s' "$HOME/.profile" ;;
    esac
}

handle_path() {
    on_path && return 0

    line="export PATH=\"$INSTALL_DIR:\$PATH\""
    rc="$(rc_file)"

    if [ "${ACC_MODIFY_PATH:-}" = "1" ]; then
        printf '\n%s\n' "$line" >> "$rc"
        info "Added $INSTALL_DIR to PATH in $rc"
        say "${GREY}Open a new shell, or run:${RESET}  . $rc"
    else
        printf '\n'
        say "${BOLD}$INSTALL_DIR is not on your PATH.${RESET}"
        say "${GREY}Add this to $rc:${RESET}"
        printf '\n      %s\n' "$line"
        say "${GREY}Or re-run this installer with ACC_MODIFY_PATH=1 to do it for you.${RESET}"
    fi
}

# Already hit once in practice: a stale copy at /usr/bin/acc winning on PATH,
# with the shell's hash table still pointing at it even after the PATH was fine.
check_shadowing() {
    on_path || return 0
    resolved="$(command -v acc 2>/dev/null || true)"
    [ -n "$resolved" ] || return 0
    [ "$resolved" = "$DEST" ] && return 0

    printf '\n'
    say "${BOLD}Heads up:${RESET} typing 'acc' currently runs $resolved"
    say "${GREY}Another copy is earlier on your PATH, or your shell cached the old one.${RESET}"
    say "${GREY}Try 'hash -r' (or 'rehash' in zsh), then 'command -v acc' to check.${RESET}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    printf '\n  %bacc installer%b\n\n' "$BOLD" "$RESET"

    find_downloader
    find_hasher
    find_python
    info "Using $("$PYTHON" -V 2>&1)"

    download
    verify
    install_it

    installed="$("$DEST" version 2>/dev/null || printf 'unknown')"
    printf '\n  %b✓%b  %s is ready\n' "$GREEN" "$RESET" "$installed"

    handle_path
    check_shadowing

    printf '\n  %bRun "acc" to get started. It asks for a token on first run.%b\n\n' "$GREY" "$RESET"
}

main "$@"
