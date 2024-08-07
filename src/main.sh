#!/usr/bin/env bash

set -e

# Logging
VAR_INSTALL_LOG_F=$PWD/regextest.log
SHOULD_SHOW_LOGS=1
CYBR_DEBUG=0
DEBUG=0

# Generic Variables
AUTOHTML5GW_VERSION="0.0.1"
ENABLE_JWT=0

# Generic output functions (logging, terminal, etc..)
function write_log() {
  if [ ${SHOULD_SHOW_LOGS} -eq 1 ] ; then
    echo "$(date) | INFO  | $1" >> $VAR_INSTALL_LOG_F
    [ ${CYBR_DEBUG} -eq 1 ] && printf 'DEBUG: %s\n' "$1"
  fi
}

function write_error() {
  echo "$(date) | ERROR | $1" >> $VAR_INSTALL_LOG_F
  printf 'ERROR: %s\n' "$1"
}
function write_to_terminal() {
  echo "$(date) | INFO  | $1" >> $VAR_INSTALL_LOG_F
  printf 'INFO: %s\n' "$1"
}

function write_header() {
  echo ""
  echo "======================================================================="
  echo "$1"
  echo "======================================================================="
  echo ""
}

function gather_facts() {
  write_to_terminal "Gathering installation system facts..."
  # Check if system is being installed in docker container and warn end user
  if [[ -f /.dockerenv ]] ; then
    write_to_terminal "Detected Docker Container".
    write_to_terminal "To ensure proper installation, please run this script on the host machine."
    write_to_terminal "Exiting..."
  fi

  write_to_terminal "Validating Operating System Requirements..."
  # Check Operating System
  if [[ -f $PWD/rhel8 ]] ; then
    # Valid OS ID = rhel / rocky
    local os
    os=$(awk '{ FS = "="} /^ID=/ {print $2}' "$PWD/rhel8" | sed -e 's/^"//' -e 's/"$//' )
    if [[ -z "$os" ]] ; then
      write_to_terminal "Unable to determine system OS, exiting..."
      exit 1
    fi
    local res=0
    res=$(valid_os "$os")
    if [[ $res -eq 0 ]] ; then
      write_to_terminal "Valid OS detected ($os), proceeding..."
    else
      write_to_terminal "Invalid OS detected, exiting..."
      exit 1
    fi
    # Valid OS Version = rhel 8 or 9 / rocky 8
    osversion=$(awk '{ FS = "="} /^VERSION_ID=/ {print $2}' "$PWD/rhel8" | sed -e 's/^"//' -e 's/"$//' )
    if [[ -z "$osversion" ]] ; then
      write_to_terminal "Unable to determine system OS version, exiting..."
      exit 1
    fi
    res=$(valid_osversion "$os" "$osversion")
    if [[ $res -eq 0 ]] ; then
      write_to_terminal "Valid OS Version detected ($osversion), proceeding..."
    else
      write_to_terminal "Invalid OS Version detected, exiting..."
      exit 1
    fi
  else
    write_to_terminal "Unable to determine system OS and version, exiting..."
    exit 1
  fi
}

function accept_eula() {
  # Prompt for EULA Acceptance
  write_to_terminal "Have you read and accepted the CyberArk EULA?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes ) write_to_terminal "EULA Accepted, proceeding..."; break;;
      No ) write_to_terminal "EULA not accepted, exiting now..."; exit 1;;
    esac
  done
  printf "\n"
}

function psmgw_hostname_prompt() {
  local psmgw_hostname
  write_to_terminal "Requesting PSGMW Hostname for installation:"
  read -erp 'Please enter PSGMW Hostname Username (e.g. psmgw.domain.com): ' psmgw_hostname
  local res=0
  # Check hostname validity
  res=$(valid_hostname "$psmgw_hostname")
  if [[ $res -eq 0 ]] ; then
    write_to_terminal "Valid hostname provided, proceeding..."
    confirm_input "$psmgw_hostname" "psmgw"
    export PSMGW_HOSTNAME=$psmgw_hostname
  else
    case $res in
      1) write_to_terminal "Invalid Hostname: Hostname cannot be empty.";;
      2) write_to_terminal "Invalid Hostname: Hostname contains invalid characters, or is to long.";;
      *) write_to_terminal "Invalid Hostname: Invalid Hostname provided."
    esac
    write_to_terminal "Would you like to try again?"
    select yn in "Yes" "No"; do
      case $yn in 
        Yes ) psmgw_hostname_prompt; break;;
        No ) write_to_terminal "Invalid hostname provided, exiting..."; exit 1;;
      esac
    done
  fi
  printf "\n"
}

function disable_jwt() {
  # Prompt for EULA Acceptance
  write_to_terminal "Would you like to disable JWT secured authentication? Note: JWT \
secured authentication is required starting with version 14.2?"
  select yn in "No" "Yes"; do
    case $yn in
      Yes ) export ENABLE_JWT=1; write_to_terminal "JWT secured authentication disabled."; break;;
      No ) write_to_terminal "JWT secured authentication remains enabled."; break;;
    esac
  done
  printf "\n"
}

package_verification() {
  write_to_terminal "Validaitng required rpm and GPG Key is present..."
  psmgwrpm=`ls $PWD | grep CARKpsmgw*`
  if [[ -f $psmgwrpm ]] ; then
    write_to_terminal "Installation rpm is present, proceeding..."
  else
    write_error "Installation rpm is not present, please add it to the installation folder. Exiting..."
    exit 1
  fi

  if [[ -f $PWD/RPM-GPG-KEY-CyberArk ]] ; then
    write_to_terminal "GPG Key is present, proceeding..."
  else
    write_error "GPG Key is not present, please add it to the installation folder. Exiting..."
    exit 1
  fi
}

library_prereqs() {
  # Validate Firewalld service is installed
  local firewalldservice=firewalld
  write_to_terminal "Verifying $firewalldservice is installed"
  dnf list installed $firewalldservice > /dev/null 2>&1
  if [[ $? -eq 1 ]]; then
    write_to_terminal "$firewalldservice is not installed. Adding to list of packages to install." 
    pkgarray=(firewalld openssl cairo libpng15 libjpeg-turbo java-1.8.0-openjdk-headless openssl initscripts)
  else 
    write_to_terminal "$firewalldservice is installed. Proceeding..."
    pkgarray=(openssl cairo libpng15 libjpeg-turbo java-1.8.0-openjdk-headless openssl initscripts)
  fi 

  write_to_terminal "Installing New Packages - This may take some time"
  for pkg in  ${pkgarray[@]}
  do
    pkg="$pkg"
    dnf list $pkg > /dev/null
    if [[ $? -eq 0 ]]; then
      write_to_terminal "Installing $pkg"
      dnf -y install $pkg >> html5gw.log 2>&1
      dnf list installed $pkg > /dev/null
      # Check if packages installed correctly, if not - Exit
      if [[ $? -eq 0 ]]; then
        write_to_terminal "$pkg installed."
      else
        write_error "$pkg could not be installed. Exiting...."
        exit 1
      fi
    else
      write_error "Required package - $pkg - not found. Exiting..."
      exit 1
    fi
  done
}

function confirm_input() {
  local userinput=$1
  local inputfield=$2
  write_to_terminal "You entered ${userinput} for ${inputfield} hostname. Proceed or enter again?"
  select pc in "Proceed" "Change"; do
    case $pc in
      Proceed ) write_to_terminal "Input confirmed, proceeding..."; break;;
      Change ) 
        case $inputfield in
          pvwa ) pvwa_hostname_prompt; break;;
          psmgw ) psmgw_hostname_prompt; break;;
        esac
    esac
  done
}

function valid_os() {
  # Valid OS ID are rhel and rocky
  local os=$1
  stat=1

  local validate="^(rhel|rocky)$"
  if [[ $os =~ $validate ]] ; then
    stat=0
  else
    stat=1
  fi

  echo $stat
}

function valid_osversion() {
  # Valid OS ID are rhel and rocky
  local os=$1
  local osversion=$2
  stat=1

  if [[ $os == "rhel" ]] ; then
    local validate="^([8-9]\.[0-9])$"
    if [[ $osversion =~ $validate ]] ; then
      stat=0
    else
      stat=1
    fi
  elif [[ $os == "rocky" ]] ; then
    local validate="^([8]\.[0-9])$"
    if [[ $osversion =~ $validate ]] ; then
      stat=0
    else
      stat=1
    fi
  fi

  echo $stat
}

function valid_hostname() {
  # Valid Hostnames have the following requirements
  # - No larger than 128 Characters
  # - Cannot start or end with a period or space
  # - Can only contain letters, numbers, and hyphens
  local hostname=$1
  local stat=1

  local validate="^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.)+[a-zA-Z]{3,}$"
  
  # Compare hostname with regex
  if [[ $hostname =~ $validate ]] ; then
    stat=0
  else
    stat=2
  fi

  echo $stat
}

function _start_test() {
  ### Begin System Validation
  write_header "Step 1: Validating installation requirements"

  gather_facts

  ### Begin User Prompts
  write_header "Step 2: Gathering Information"

  accept_eula

  psmgw_hostname_prompt

  disable_jwt

  ### Begin System Prep
  write_header "Step 3: System preperation"

  package_verification

  #library_prereqs

  ### Install Tomcat



  ### Install 

  exit 0
}

function _show_help {
  printf "%s" "$(<help.txt)"  
  exit 0
}

function _show_version {
  echo "$AUTOHTML5GW_VERSION"
  exit 0
}

function main {
  if [[ $# == 0 ]] ; then
    _start_test
  fi

  while [[ $# -gt 0 ]]; do
    local opt="$1"

    case "$opt" in
      # Options for quick-exit strategy:
      --debug) export CYBR_DEBUG=1; _start_test;;
      --help) _show_help;;
      --version) _show_version;;
      *) break;;  # do nothing
    esac
  done
}

if [ "${BASH_SOURCE[0]}" -ef "$0" ]
then
  main "$@" # To pass the argument list
fi