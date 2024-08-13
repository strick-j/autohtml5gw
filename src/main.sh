#!/usr/bin/env bash

set -e

# Logging
VAR_INSTALL_LOG_F=$PWD/autohtml5gw.log
SHOULD_SHOW_LOGS=1
CYBR_DEBUG=0
DEBUG=0

# Generic Variables
AUTOHTML5GW_VERSION="0.0.1"
ENABLE_JWT=0
TOMCAT_HOME="/opt/tomcat"

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

pushd () {
  command pushd "$@" > /dev/null
}

popd () {
  command popd "$@" > /dev/null
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
      Yes ) export ENABLE_JWT=1; write_to_terminal "JWT secured authentication disabled, proceeding..."; break;;
      No ) write_to_terminal "JWT secured authentication remains enabled, proceeding..."; break;;
    esac
  done
  printf "\n"
}

function package_verification() {
  write_to_terminal "Validating required rpm and GPG Key is present..."
  psmgwrpm=`ls $PWD | grep CARKpsmgw*`
  if [[ -f $psmgwrpm ]] ; then
    write_to_terminal "Installation rpm is present, proceeding..."
  else
    write_error "Installation rpm is not present, please add it to the installation folder. Exiting..."
    exit 1
  fi
}

function preinstall_gpgkey() {
  if [[ -f $PWD/RPM-GPG-KEY-CyberArk ]] ; then
    write_to_terminal "GPG Key is present, proceeding..."
  else
    write_error "GPG Key is not present, please add it to the installation folder. Exiting..."
    exit 1
  fi
}

function library_prereqs() {
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

tomcat_user_check() {
  local username="tomcat"
  local membership=$(getent group wheel | awk -F: '{print $4}' | grep -w $username > /dev/null 2>&1)
  local homedir=$(getent passwd $username | awk -F: '{print $6}')

  # Check for tomcat group and create if not found
  getent group tomcat > /dev/null 2>&1 || groupadd tomcat

  # Check if tomcat user exists
  write_to_terminal "Checking for tomcat user..."
  if id -u $username > /dev/null 2>&1 ; then
    write_to_terminal "Tomcat user exists, checking group membership..."
    if $membership; then
      write_to_terminal "$username is a member of the tomcat group, proceeding..."
    else
      write_to_terminal "$username is not a member of the tomcat group, adding..."
      usermod -aG tomcat $username
      if $membership; then
        write_to_terminal "$username added to tomcat group successfully."
      else
        write_error "$username could not be added to tomcat group. Exiting..."
        exit 1
      fi
    fi
  else
    write_to_terminal "Tomcat user does not exist, creating..."
    useradd -s /bin/nologin -g tomcat -d $TOMCAT_HOME tomcat
    if id -u $username > /dev/null 2>&1 ; then
      write_to_terminal "Tomcat user created successfully."
    else
      write_error "Tomcat user could not be created. Exiting..."
      exit 1
    fi
  fi

  # Check for tomcat home directory
  write_to_terminal "Checking for tomcat home directory..."
  export TOMCAT_HOME=$homedir
  write_to_terminal "Tomcat home directory set to $TOMCAT_HOME, proceeding..."
}

function tomcat_install() {
  write_to_terminal "Finding latest version of Tomcat (v9)..."
   # Specify major version of Tomcat desired
  local wanted_ver=9
  # Use curl to search for latest minor version of specified major version
  local tomcat_ver=`curl --silent https://downloads.apache.org/tomcat/tomcat-${wanted_ver}/ | grep v${wanted_ver} | awk '{split($5,c,">v") ; split(c[2],d,"/") ; print d[1]}' | tail -n 1`
  write_to_terminal "Latest version of Tomcat v${wanted_ver} is ${tomcat_ver}, downloading..."
  # Create URL based on curl
  local apache_url="https://downloads.apache.org/tomcat/tomcat-${wanted_ver}/v${tomcat_ver}/bin/apache-tomcat-${tomcat_ver}.tar.gz"
  # Create URL based on curl
  if [[ `curl -Is ${apache_url}` == *200* ]] ; then
    write_to_terminal "URL Found: ${apache_url}"
    wget $apache_url >> $VAR_INSTALL_LOG_F 2>&1
    if [[ $? -eq 0 ]] ; then
      write_to_terminal "Apache Tomcat downloaded successfully. Extracting..."
      tar -xvf apache-tomcat-${tomcat_ver}.tar.gz -C /opt/tomcat --strip-components=1 >> $VAR_INSTALL_LOG_F 2>&1
    else
      write_error "Apache Tomcat could not be downloaded. Exiting now..."
      exit 1
    fi
  else 
    print_error "Apache Tomcat could not be downloaded. Exiting now..."
    exit 1
  fi
}

function tomcat_permissions() {
  # Set Tomcat Permissions
  print_info "Setting Tomcat folder permissions"
  pushd /opt/tomcat
  sudo chgrp -R tomcat conf
  sudo chmod g+rwx conf
  sudo chmod g+r conf/*
  sudo chown -R tomcat logs/ temp/ webapps/ work/
  sudo chgrp -R tomcat bin
  sudo chgrp -R tomcat lib
  sudo chmod g+rwx bin
  sudo chmod g+r bin/*
  popd
}

function tomcat_service() {
  # Create and enable Tomcat Service
  print_info "Creating Tomcat Service"
  cp tomcat.service /etc/systemd/system/tomcat.service >> $VAR_INSTALL_LOG_F
  systemctl daemon-reload >> $VAR_INSTALL_LOG_F
  systemctl enable tomcat >> $VAR_INSTALL_LOG_F 2>&1
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

function testkey(){
  # Function to list certificates in the keystore and verify keytool imports
  # List keytool and export to file
  print_info "Checking $1 keystore for $2 alias"
  keytool -list -v -keystore $1 -alias $2 -storepass $3 > temp.log 2>&1

  # Read in first line from file
  line=$(head -n 1 temp.log)
  verify="Alias name: $2"

  # Compare log file and expected key alias
  if [[ $line == $verify ]]; then
    print_success "$2 successfully imported into $1 keystore"
  else
    print_error "$2 not present in $1 keystore. Exiting now..."
    exit 1
  fi
 
  # Concatenate temp log and cleanup
  cat temp.log >> html5gw.log
  rm temp.log
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
  write_header "Step 3: Installation preperation"

  package_verification

  preinstall_gpgkey

  library_prereqs

  ### Install Tomcat

  write_header "Step 4: Installing Tomcat"

  # Check for Tomcat User
  tomcat_user_check

  tomcat_install

  tomcat_permissions

  #tomcat_certificate

  #tomcat_config

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