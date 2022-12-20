#!/bin/bash

# Update the package manager's package list
apt-get update

# Install packages needed to add the Docker GPG key
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common

# Add the Docker GPG key
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -

# Add the Docker repository to the package manager
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

# Update the package manager's package list (again)
apt-get update

# Install Docker
apt-get install -y docker-ce

# Add the current user to the "docker" group, so that we don't have to use "sudo" to run Docker commands
usermod -aG docker $USER
