#!/bin/bash

# Enable verbose DRM logging
echo "Enabling verbose DRM logging..."
echo 0x19F | sudo tee /sys/module/drm/parameters/debug

# Clear existing kernel debug logs
echo "Clearing existing kernel debug logs..."
sudo dmesg -C

# Start writing kernel logs to a file in the background
echo "Logging kernel messages to ~/dmesg.log..."
sudo dmesg -w > ~/dmesg.log &

# Store the background job's PID
DMESG_PID=$!

# Start Hyprland
echo "Starting Hyprland..."
Hyprland &

# Wait for Hyprland to exit
HYPRLAND_PID=$!
wait $HYPRLAND_PID

# After Hyprland exits, bring the background job to the foreground
echo "Hyprland exited. Stopping log capture process."
kill $DMESG_PID

# Disable verbose DRM logging
echo "Disabling verbose DRM logging..."
echo 0 | sudo tee /sys/module/drm/parameters/debug

echo "All done. Logs have been saved to ~/dmesg.log."
