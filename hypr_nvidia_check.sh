#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Define function to check and print results
check_step() {
    STEP_NAME=$1
    COMMAND=$2
    INFO=$3

    if eval "$COMMAND"; then
        echo -e "${STEP_NAME} ${GREEN}{PASS}${NC} - ${INFO}"
    else
        echo -e "${STEP_NAME} ${RED}{FAIL}${NC} - ${INFO}"
    fi
}

# Function to check environment variables
check_env_variable() {
    VAR_NAME=$1
    EXPECTED_VALUE=$2
    CURRENT_VALUE=$(eval echo \$$VAR_NAME)

    if [[ "$CURRENT_VALUE" == "$EXPECTED_VALUE" ]]; then
        echo -e "Environment variable $VAR_NAME ${GREEN}{PASS}${NC} - Expected: $EXPECTED_VALUE, Current: $CURRENT_VALUE"
    else
        echo -e "Environment variable $VAR_NAME ${RED}{FAIL}${NC} - Expected: $EXPECTED_VALUE, Current: ${CURRENT_VALUE:-Not Set}"
    fi
}

# Function to check OpenGL ES version
check_opengl_es_version() {
    if command -v glxinfo >/dev/null 2>&1; then
        OPENGL_ES_VERSION=$(glxinfo | grep "OpenGL ES profile version string" | awk '{print $8}')
        OPENGL_ES_VERSION=3.1
    else
        echo -e "OpenGL ES version check: ${RED}{FAIL}${NC} - glxinfo not found."
        return
    fi

    if [[ -n "$OPENGL_ES_VERSION" ]]; then
        VERSION_MAJOR=$(echo "$OPENGL_ES_VERSION" | cut -d'.' -f1)
        VERSION_MINOR=$(echo "$OPENGL_ES_VERSION" | cut -d'.' -f2)

        if [[ "$VERSION_MAJOR" -gt 3 || ("$VERSION_MAJOR" -eq 3 && "$VERSION_MINOR" -ge 2) ]]; then
            echo -e "OpenGL ES version: ${GREEN}{PASS}${NC} - Version: ${OPENGL_ES_VERSION}"
        elif [[ "$VERSION_MAJOR" -eq 3 && "$VERSION_MINOR" -ge 0 ]]; then
            echo -e "OpenGL ES version: ${YELLOW}{WARN}${NC} - Version: ${OPENGL_ES_VERSION} - Hyprland can work with OpenGL ES lower than 3.2, but is not officially supported. If you have issues, install the legacy renderer version."
        else
            echo -e "OpenGL ES version: ${RED}{FAIL}${NC} - Version: ${OPENGL_ES_VERSION} - Install legacy renderer version."
        fi
    else
        echo -e "OpenGL ES version: ${RED}{FAIL}${NC} - Unable to determine OpenGL ES version."
    fi
}

# Check the installed Hyprland version
HYPRCTL_OUTPUT=$(hyprctl version 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo -e "Hyprland version check: ${RED}{FAIL}${NC} - Hyprland is not installed or hyprctl command not found."
else
    CURRENT_HYPRLAND_VERSION=$(echo "$HYPRCTL_OUTPUT" | grep "Tag:" | awk '{print $2}' | cut -d'-' -f1)

    # Fetch the latest version from GitHub releases
    LATEST_HYPRLAND_VERSION=$(curl -s https://github.com/hyprwm/Hyprland/releases | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [[ "$CURRENT_HYPRLAND_VERSION" == "$LATEST_HYPRLAND_VERSION" ]]; then
        echo -e "Latest Hyprland version: ${GREEN}{PASS}${NC} - Current version ($CURRENT_HYPRLAND_VERSION) is up-to-date."
    else
        echo -e "Latest Hyprland version: ${RED}{FAIL}${NC} - Current version ($CURRENT_HYPRLAND_VERSION), Latest available version: $LATEST_HYPRLAND_VERSION"
    fi
fi

echo
# Check if the correct version of the NVIDIA driver is installed (example: 495+ required)
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
MIN_REQUIRED_VERSION=495
DRIVER_VERSION_NUMBER=$(echo $DRIVER_VERSION | cut -d. -f1)
check_step "Correct NVIDIA driver version:" "[[ \"$DRIVER_VERSION_NUMBER\" -ge \"$MIN_REQUIRED_VERSION\" ]]" "Required version: $MIN_REQUIRED_VERSION+, Installed version: ${DRIVER_VERSION:-Not Installed}"

# Check if the NVIDIA DRM kernel module is enabled
check_step "NVIDIA DRM kernel module enabled:" "lsmod | grep -q 'nvidia_drm'" "Module: nvidia_drm"

# Check OpenGL ES version
check_opengl_es_version

echo
# Check for required modules in /etc/mkinitcpio.conf
MODULES=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
if [ -f "$MKINITCPIO_CONF" ]; then
    MODULES_LINE=$(grep "^MODULES=" "$MKINITCPIO_CONF")
    MISSING_MODULES=()
    for MODULE in "${MODULES[@]}"; do
        if [[ "$MODULES_LINE" != *"$MODULE"* ]]; then
            MISSING_MODULES+=("$MODULE")
        fi
    done

    if [ ${#MISSING_MODULES[@]} -eq 0 ]; then
        echo -e "MODULES in $MKINITCPIO_CONF ${GREEN}{PASS}${NC} - All required modules are present."
    else
        echo -e "MODULES in $MKINITCPIO_CONF ${RED}{FAIL}${NC} - Missing modules: ${MISSING_MODULES[*]}"
    fi
else
    echo -e "/etc/mkinitcpio.conf ${RED}{FAIL}${NC} - File not found."
fi

# Check for /etc/modprobe.d/nvidia.conf
MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
if [ -f "$MODPROBE_CONF" ]; then
    EXPECTED_CONTENT="options nvidia_drm modeset=1 fbdev=1"
    ACTUAL_CONTENT=$(cat "$MODPROBE_CONF")

    if [[ "$ACTUAL_CONTENT" == "$EXPECTED_CONTENT" ]]; then
        echo -e "$MODPROBE_CONF ${GREEN}{PASS}${NC} - Content matches expected."
    else
        echo -e "$MODPROBE_CONF ${RED}{FAIL}${NC} - Content does not match expected (options nvidia_drm modeset=1 fbdev=1)."
    fi
else
    echo -e "$MODPROBE_CONF ${RED}{FAIL}${NC} - File not found."
fi

echo
# Check the specified environment variables with expected values
check_env_variable "LIBVA_DRIVER_NAME" "nvidia"
check_env_variable "XDG_SESSION_TYPE" "wayland"
check_env_variable "GBM_BACKEND" "nvidia-drm"
check_env_variable "__GLX_VENDOR_LIBRARY_NAME" "nvidia"
check_env_variable "EGL_PLATFORM" "wayland"

echo
# Check if the compositor is running on Wayland
SESSION_TYPE=$(loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p Type | cut -d= -f2 | xargs)

# Check if the session type contains 'wayland'
if [[ "$SESSION_TYPE" == *"wayland"* ]]; then
    echo -e "Compositor running on Wayland: ${GREEN}{PASS}${NC} - Current session type: ${SESSION_TYPE}"
else
    echo -e "Compositor running on Wayland: ${RED}{FAIL}${NC} - Current session type: ${SESSION_TYPE}"
fi

# Function to check if 'no_hardware_cursors' is set to true in the cursor block
CONFIG_FILE="$HOME/.config/hypr/hyprland.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "Hyprland config: ${RED}{FAIL}${NC} - Config file not found at $CONFIG_FILE"
    return
fi

# Extract the cursor block
CURSOR_BLOCK=$(awk '/cursor *{/,/}/' "$CONFIG_FILE")

if [[ -z "$CURSOR_BLOCK" ]]; then
    echo -e "Cursor block: ${BLUE}{INFO}${NC} - Cursor block not found in the config. Enable no_hardware_cursors if you have issues."
    return
fi

# Check if 'no_hardware_cursors = true' is present and not commented out
if echo "$CURSOR_BLOCK" | grep -q "^[^#]*no_hardware_cursors *= *true"; then
    echo -e "Cursor config: ${GREEN}{PASS}${NC} - 'no_hardware_cursors = true' is set and active."
elif echo "$CURSOR_BLOCK" | grep -q "# *no_hardware_cursors *= *true"; then
    echo -e "Cursor config: ${BLUE}{INFO}${NC} - 'no_hardware_cursors = true' is set but commented out. Enable it if you have issues."
else
    echo -e "Cursor config: ${BLUE}{INFO}${NC} - 'no_hardware_cursors = true' is not set. It is recommended to enable it if you have issues."
fi
