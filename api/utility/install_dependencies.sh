#!/bin/bash
#
# Common utility functions for installing software dependencies on supported operating systems.

#######################################
# Checks Whether the given command is installed or not.
# Globals:
#   None
# Arguments:
#   The command to check for.
# Outputs:
#   Returns zero if the command is installed and 1 if not.
#######################################
check_command_installed() {
    if command -v "$1" > /dev/null 2>&1; then
        echo 0
    else
        echo 1
    fi
}

#######################################
# Installs a missing command to the machine. If the OS is not supported it exits.
# Globals:
#   None
# Arguments:
#   The command to be installed.
#######################################
install_command() {
  if [[ $(is_macOS) -eq 1 ]] && [[ $(linux_distro) -eq 1 ]]; then
    echo "Unsupported OS. Cannot install missing dependencies. Exiting..."
    exit 1
  fi


  if [[ $(is_macOS) -eq 0 ]]; then
    if command -v brew > /dev/null 2>&1; then
      brew install "$1"
    else
      echo "Homebrew is not installed. Please install Homebrew first."
      exit 1
    fi
  else
    distro=$(linux_distro)
    printf "Detected Linux distribution: %s.\n" "$(distro)"

    case "$distro" in
      ubuntu|debian)
        sudo apt update && sudo apt install -y "$1"
        ;;
      fedora)
        sudo dnf install -y "$1"
        ;;
      centos|rhel)
        sudo yum install -y "$1"
        ;;
      alpine)
        sudo apk add --no-cache "$1"
        ;;
      arch)
        sudo pacman -Sy "$1"
        ;;
    esac
  fi
}

#######################################
# Checks whether the script is running on MacOS or not.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Returns zero if MacOS found, 1 otherwise.
#######################################
is_macOS() {
  if [ "$(uname)" == "Darwin" ]; then
    echo 0
  else
    echo 1
  fi
}

#######################################
# Checks the Linux distribution the script is running on.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Returns the id of the OS distribution and zero if a supported distribution is found. Returns 1 if not a Linux.
#######################################
linux_distro() {
  if [ -f /etc/os-release ]; then
    id=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    case "$id" in ubuntu|debian|fedora|centos|rhel|alpine|arch)
      echo "$id"
      ;;
    *)
      echo "Unsupported Linux distribution. Exiting..."
      exit 1
      ;;
    esac
  else
    echo 1
  fi
}
