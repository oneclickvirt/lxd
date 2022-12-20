#!/bin/bash

# Check if lxd is installed
if ! command -v lxd > /dev/null 2>&1; then
  echo "Error: lxd is not installed."
  exit 1
fi

# Check if the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run with root privileges."
  exit 1
fi

# Get a list of all containers
containers=$(lxc list --format csv -c n)

# Iterate over the list of containers
while read -r container; do
  # Enable docker virtualization in the container
  lxc config set "$container" security.nesting true

  # Set security prevention settings
  lxc config set "$container" security.syscalls.intercept.mknod true
  lxc config set "$container" security.syscalls.intercept.setxattr true

  # Restart the container
  lxc restart "$container"
done <<< "$containers"
