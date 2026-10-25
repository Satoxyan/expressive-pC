#!/usr/bin/env bash
# install_droidcam.sh — Detects distro and installs the Phone tab's streaming
# stack + deps.
#
# Supports:
#   • Arch Linux (scrcpy and v4l2loopback-dkms from [extra], droidcam from the AUR)
#   • Fedora (RPMFusion for v4l2loopback + official DroidCam client installer)
#   • Debian/Ubuntu (official DroidCam installer zip)
#
# Installs: scrcpy (the webcam's engine and the preferred microphone backend),
#           adb (android-tools), v4l2loopback (kernel module, and loads it),
#           v4l-utils, mpv, droidcam-cli (the microphone's fallback),
#           pactl (audio routing), ffmpeg, alsa-lib.
#
# The name predates the webcam moving to scrcpy; DroidCam CLI is what is left
# of it, and the mic still uses it as a fallback.

set -u
IFS=$'\n\t'

# ─── Distro detection ─────────────────────────────────
detect_distro() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/debian_version ] || grep -qiE "ubuntu|debian" /etc/os-release 2>/dev/null; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Common pause helper
press_enter_to_close() {
    echo ""
    echo "Press Enter to close..."
    # `read` answers 1 at EOF, and this is the last command on the success
    # path, so without the guard a completed install exits non-zero whenever
    # stdin is not a terminal.
    read -r || true
}

# The device DroidCam writes to, and what an install used to get wrong: a
# module that is INSTALLED is not a module that is LOADED. It takes a
# modprobe before any /dev/videoN exists and a modules-load.d line before it
# survives the next boot, and only the Fedora branch did either — so an Arch
# or Debian run could print "✓ installed" and leave the webcam with nowhere
# to stream, a session that never starts and a preview that then complains
# about mpv.
load_v4l2loopback() {
    echo "▸ Loading v4l2loopback kernel module..."
    if ! sudo modprobe v4l2loopback; then
        echo "  ! modprobe failed. After a kernel update the dkms module is"
        echo "    rebuilt for the new kernel; reboot and run this again."
        return 1
    fi
    echo "  ✓ Loaded."
    if [ ! -f /etc/modules-load.d/v4l2loopback.conf ]; then
        echo "▸ Loading it on every boot..."
        echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf >/dev/null \
            || echo "  ! Could not write /etc/modules-load.d/v4l2loopback.conf."
    fi
    return 0
}

# URL of the official DroidCam Linux client zip.
# Changed from .com to .net — the .com host stopped resolving in 2025-2026.
# And switched from droidcam_latest.zip to versioned droidcam_2.1.5.zip.
DROIDCAM_URL="https://files.dev47apps.net/linux/droidcam_2.1.5.zip"
DROIDCAM_SHA1="ce44abefbadec0a2183837605df23643ca13fb02"

download_droidcam() {
    local outpath="$1"
    echo "▸ Downloading DroidCam client from $DROIDCAM_URL"
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL --connect-timeout 15 --retry 3 --retry-delay 2 \
                -o "$outpath" "$DROIDCAM_URL"; then
            echo "  ✓ Downloaded successfully."
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --tries=3 --timeout=15 \
                -O "$outpath" "$DROIDCAM_URL"; then
            echo "  ✓ Downloaded successfully."
            return 0
        fi
    else
        echo "✗ Neither curl nor wget is installed."
        return 1
    fi
    echo "✗ Failed to download. The DroidCam site may be unreachable."
    echo "  Try manually from: https://www.dev47apps.com/droidcam/linux/"
    return 1
}

verify_droidcam() {
    local outpath="$1"
    if ! command -v sha1sum >/dev/null 2>&1; then
        echo "  ! sha1sum not available — skipping verification."
        return 0
    fi
    local actual
    actual="$(sha1sum "$outpath" | awk '{print $1}')"
    if [ "$actual" = "$DROIDCAM_SHA1" ]; then
        echo "  ✓ SHA1 verified."
        return 0
    fi
    echo "  ✗ SHA1 mismatch (got $actual, expected $DROIDCAM_SHA1)"
    echo "  The downloaded file may be corrupt. Aborting."
    return 1
}

install_from_official_zip() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local zpath="$tmpdir/droidcam.zip"

    download_droidcam "$zpath" || { rm -rf "$tmpdir"; return 1; }
    verify_droidcam "$zpath" || { rm -rf "$tmpdir"; return 1; }

    # The extract was unchecked and so was the `cd` after it, so a corrupt or
    # truncated download left `sudo ./install-client` running in whatever
    # directory the caller happened to be in — as root.
    echo "▸ Extracting..."
    local clientdir="$tmpdir/droidcam"
    if ! unzip -q -o "$zpath" -d "$clientdir"; then
        echo "✗ Could not extract the DroidCam archive."
        rm -rf "$tmpdir"
        return 1
    fi
    if [ ! -f "$clientdir/install-client" ]; then
        echo "✗ The archive did not contain install-client."
        rm -rf "$tmpdir"
        return 1
    fi

    # Each step runs in a subshell, so the directory is this function's
    # business and never the caller's, and a failed `cd` cannot leak into the
    # next command.
    echo "▸ Running install-client (sudo required)..."
    if ! ( cd "$clientdir" && sudo ./install-client ); then
        echo "✗ install-client failed."
        rm -rf "$tmpdir"
        return 1
    fi

    echo ""
    echo "▸ Compiling video module (v4l2loopback-dc) ..."
    ( cd "$clientdir" && sudo ./install-video ) || {
        echo "  ! install-video failed (this may be expected if you already have v4l2loopback from your distro)."
    }

    echo ""
    echo "▸ Loading audio loopback module ..."
    ( cd "$clientdir" && sudo ./install-sound ) || {
        echo "  ! install-sound failed (optional — you may already have pipe wire/PulseAudio working)."
    }

    rm -rf "$tmpdir"
    echo ""
    echo "✓ DroidCam installed (official installer)."
    return 0
}

main() {
    local DISTRO="${1:-$(detect_distro)}"

    echo "╔═══════════════════════════════════════════════╗"
    echo "║    Phone camera & microphone installer for ImI   ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""

case "$DISTRO" in
    arch)
        echo "▸ Detected: Arch Linux"
        echo ""

        # The webcam's whole stack is in [extra] and [community] now that
        # scrcpy writes /dev/videoN itself, so this first command is the one
        # that decides whether the cards can work. `droidcam` is AUR-only and
        # is NOT in it: it is the microphone's fallback backend, so it is
        # attempted afterwards and a missing AUR helper is a warning rather
        # than a refusal — it used to abort the install before a single
        # package was fetched, on the branch where none of it was needed.
        echo "▸ Installing scrcpy, mpv, v4l-utils, android-tools and v4l2loopback-dkms..."
        if ! sudo pacman -S --needed --noconfirm scrcpy mpv v4l-utils android-tools v4l2loopback-dkms; then
            echo ""
            echo "✗ Could not install the camera stack."
            press_enter_to_close
            return 1
        fi

        # Also install pactl (in pulseaudio-utils) for microphone routing.
        if ! command -v pactl >/dev/null 2>&1; then
            echo ""
            echo "▸ Installing pactl (for microphone routing)..."
            if ! sudo pacman -S --needed --noconfirm pulseaudio-utils \
                && ! sudo pacman -S --needed --noconfirm pipewire-pulse; then
                echo ""
                echo "✗ Could not install a PulseAudio client (pactl)."
                press_enter_to_close
                return 1
            fi
        fi

        # Installed is not loaded: until this runs there is no /dev/videoN for
        # scrcpy to write to, and the webcam's own start refuses.
        echo ""
        load_v4l2loopback || echo "  (continuing; load it by hand before using the webcam)"

        AUR_HELPER=""
        for helper in yay paru; do
            if command -v "$helper" >/dev/null 2>&1; then
                AUR_HELPER="$helper"
                break
            fi
        done

        echo ""
        if [ -z "$AUR_HELPER" ]; then
            echo "▸ Skipping the DroidCam CLI: no AUR helper (yay/paru) found."
            echo "  The webcam does not need it. Only the microphone's fallback backend does,"
            echo "  and scrcpy is that backend's preferred half and is installed."
        elif ! "$AUR_HELPER" -S --needed droidcam; then
            echo ""
            echo "  ! $AUR_HELPER could not install droidcam — continuing without the"
            echo "    microphone's fallback backend."
        else
            echo "✓ DroidCam CLI installed (Arch/AUR), for the microphone's fallback."
        fi
        ;;

    fedora)
        echo "▸ Detected: Fedora"
        echo ""

        # Enable RPM Fusion free repo (provides akmod-v4l2loopback and
        # other multimedia packages we need).
        if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
            fedora_ver="$(rpm -E %fedora 2>/dev/null || echo '')"
            if [ -n "$fedora_ver" ]; then
                echo "▸ Enabling RPM Fusion free repo (Fedora $fedora_ver)..."
                sudo dnf install -y \
                    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" || {
                    echo "  ! Could not enable RPM Fusion. Continuing anyway..."
                }
            fi
        else
            echo "▸ RPM Fusion already enabled."
        fi
        echo ""

        # Install build/runtime deps.
        #   • scrcpy is the webcam's engine (and the preferred mic backend);
        #     mpv is the preview player.
        #   • v4l2loopback-dkms does NOT exist on Fedora — use akmod-v4l2loopback
        #     from RPM Fusion (auto-builds for any kernel).
        #   • android-tools = adb
        #   • libappindicator-gtk3 = systray icon (Ubuntu 21+/Fedora 33+ removed it pre-installed)
        echo "▸ Installing runtime dependencies..."
        sudo dnf install -y --skip-broken \
            scrcpy \
            mpv \
            akmod-v4l2loopback \
            v4l-utils \
            pulseaudio-utils \
            android-tools \
            ffmpeg \
            alsa-lib \
            libappindicator-gtk3 \
            kernel-devel \
            kernel-headers \
            gcc \
            make \
            curl \
            unzip \
            2>&1 || echo "  ! Some deps failed to install (continuing)."
        echo ""

        # Load the v4l2loopback kernel module now (akmod should have built it
        # against the running kernel during the dnf install above).
        echo ""
        load_v4l2loopback || echo "  (continuing; load it by hand before using the webcam)"
        echo ""

        # Install the DroidCam client binary from official zip.
        # Optional now: the webcam is scrcpy, and droidcam-cli is only the
        # microphone's fallback backend, so a failed download is reported and
        # the run still ends successfully on the packages that matter.
        install_from_official_zip || {
            echo ""
            echo "  ! The DroidCam CLI could not be installed. The microphone will"
            echo "    use scrcpy, which needs nothing on this machine beyond what is"
            echo "    already installed; nothing else is affected."
        }
        ;;

    debian)
        echo "▸ Detected: Debian/Ubuntu"
        echo ""

        # `apt install` refuses the ENTIRE transaction when one name is
        # unknown, and `scrcpy` is unknown to Ubuntu before 23.04 — so it gets
        # its own command, where failing costs only scrcpy.
        echo "▸ Installing scrcpy (the webcam's engine)..."
        sudo apt install -y scrcpy 2>&1 || {
            echo "  ! scrcpy is not in this release's repositories."
            echo "    The Phone tab's webcam needs it: install it from"
            echo "    https://github.com/genymobile/scrcpy or a newer release."
        }
        echo ""

        echo "▸ Installing build deps, mpv and pactl..."
        sudo apt update
        sudo apt install -y \
            mpv \
            v4l2loopback-dkms \
            v4l-utils \
            pulseaudio-utils \
            adb \
            ffmpeg \
            libappindicator3-1 \
            libappindicator-gtk3-1 \
            linux-headers-"$(uname -r)" \
            build-essential \
            curl \
            unzip \
            2>&1 || echo "  ! Some deps failed to install (continuing)."
        echo ""

        load_v4l2loopback || echo "  (continuing; load it by hand before using the webcam)"
        echo ""

        install_from_official_zip || {
            echo ""
            echo "  ! The DroidCam CLI could not be installed. The microphone will"
            echo "    use scrcpy, which needs nothing on this machine beyond what is"
            echo "    already installed; nothing else is affected."
        }
        ;;

    *)
        echo "✗ Unsupported distribution."
        echo ""
        echo "Install manually following the docs below:"
        echo "  Arch:    sudo pacman -S scrcpy mpv v4l2loopback-dkms v4l-utils android-tools pulseaudio-utils"
        echo "           sudo modprobe v4l2loopback"
        echo "           (optional, mic fallback) yay -S droidcam"
        echo "  Fedora:  sudo dnf install scrcpy mpv akmod-v4l2loopback v4l-utils pulseaudio-utils android-tools"
        echo "           Enable RPM Fusion free first, for akmod-v4l2loopback."
        echo "  Debian:  sudo apt install scrcpy mpv v4l2loopback-dkms v4l-utils pulseaudio-utils adb"
        echo "           (optional, mic fallback) download from https://www.dev47apps.com/droidcam/linux/"
        press_enter_to_close
        return 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════"
echo " Next steps:"
echo "   1. Enable USB debugging on the phone (or wireless"
echo "      debugging) so adb can see it — the webcam is"
echo "      scrcpy over adb and needs no app on the phone."
echo "   2. Re-open the Phone tab in ImI — cards should"
echo "      now show 'Ready' instead of 'Install'."
echo "   3. Only for the microphone's DroidCam fallback:"
echo "      install the DroidCam app on the phone."
echo "═══════════════════════════════════════════════"
    press_enter_to_close
}

# The dispatch lives in a function so that the file can be SOURCED without
# installing anything: nothing had ever run these scripts, and a test that
# has to pick the branch (the maintainer is on Arch, CI is on Ubuntu, and the
# Arch branch is the one with the defects) cannot do it through
# `detect_distro`, which reads /etc.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
