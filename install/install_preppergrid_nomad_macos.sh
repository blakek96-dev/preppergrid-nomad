#!/bin/bash

# Project N.O.M.A.D. macOS Apple Silicon Installation Script

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m'
GRAY_R='\033[39m'
RED='\033[1;31m'
GREEN='\033[1;32m'

WHIPTAIL_TITLE="Project N.O.M.A.D Installation"
DEFAULT_NOMAD_DIR="/Users/$USER/.preppergrid-nomad"
NOMAD_DIR="${NOMAD_DIR:-$DEFAULT_NOMAD_DIR}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_COMPOSE_SOURCE="${SCRIPT_DIR}/compose.macos.yml"
MACOS_START_SOURCE="${SCRIPT_DIR}/start_preppergrid_nomad_macos.sh"
MACOS_STOP_SOURCE="${SCRIPT_DIR}/stop_preppergrid_nomad_macos.sh"
MACOS_UPDATE_SOURCE="${SCRIPT_DIR}/update_preppergrid_nomad_macos.sh"
MACOS_PLIST_SOURCE="${SCRIPT_DIR}/com.preppergrid.nomad.agent.plist"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''
generated_app_key=''
generated_db_root_password=''
generated_db_user_password=''

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_is_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script is designed to run on macOS only.\\n"
    echo -e "${RED}#${RESET} Please run this script on macOS and try again."
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running on macOS.\\n"
}

ensure_dependencies_installed() {
  if ! which brew > /dev/null 2>&1; then
    echo "Homebrew is required. Install it from https://brew.sh and re-run this script."
    exit 1
  fi

  if ! command -v curl > /dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} curl not found. Installing curl with Homebrew...\\n"
    brew install curl
  fi

  if ! command -v curl > /dev/null 2>&1; then
    echo -e "${RED}#${RESET} curl is required. Please install it and try again."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} All required dependencies are available.\\n"
}

check_is_debug_mode(){
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local password
  
  password=$(openssl rand -hex 16)
  if [[ -z "$password" ]] || [[ ${#password} -lt 16 ]]; then
    echo "ERROR: Failed to generate secure password. Aborting."
    exit 1
  fi
  
  echo "$password"
}

ensure_docker_installed() {
  if ! docker info > /dev/null 2>&1; then
    echo "Docker Desktop is required. Install it from https://www.docker.com/products/docker-desktop"
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Docker Desktop is running.\\n"
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Please read the Docker documentation at https://docs.docker.com/compose/install/ for instructions on how to install Docker Compose v2."
    exit 1
  fi
}

substitute_compose_env_value() {
  local compose_file="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$value" ]]; then
    echo "ERROR: $key value is empty. Aborting."
    exit 1
  fi

  python3 -c "
import re, sys
key = sys.argv[1]
value = sys.argv[2]
path = sys.argv[3]
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r'(' + re.escape(key) + r'=)\\S*', lambda match: match.group(1) + value, content)
with open(path, 'w') as f:
    f.write(content)
" "$key" "$value" "$compose_file"
}

validate_env_values() {
  local compose_file="$1"
  local required_keys=("APP_KEY" "DB_PASSWORD" "MYSQL_PASSWORD" "MYSQL_ROOT_PASSWORD")
  local key
  local value

  for key in "${required_keys[@]}"; do
    value=$(grep "^      - ${key}=" "$compose_file" | cut -d= -f2)
    if [[ -z "$value" ]] || [[ "$value" == "replaceme" ]]; then
      echo "ERROR: $key is empty or not substituted in $compose_file. Aborting."
      exit 1
    fi
  done
  echo "# All required environment values validated successfully."
}

wait_for_mariadb_health() {
  local max_attempts=12
  local attempt=0
  local health_status=''

  echo "# Waiting for MariaDB healthcheck..."
  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))
    health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' nomad_mysql 2>/dev/null || echo "missing")
    if [[ "$health_status" == "healthy" ]]; then
      echo "# MariaDB is ${health_status}."
      return 0
    fi
    echo "# MariaDB healthcheck attempt ${attempt}/${max_attempts}: ${health_status}"
    sleep 5
  done

  echo "ERROR: MariaDB did not become healthy. Aborting."
  exit 1
}

verify_database_user() {
  local root_password="$1"
  local db_password="$2"
  local max_attempts=12
  local attempt=0
  local user_exists

  echo "# Verifying database user..."
  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))
    user_exists=$(docker exec nomad_mysql mariadb -u root -p"${root_password}" \
      -e "SELECT COUNT(*) FROM mysql.user WHERE user='nomad_user';" \
      --skip-column-names 2>/dev/null || echo "0")
    user_exists="${user_exists//[[:space:]]/}"
    if [[ "$user_exists" == "1" ]]; then
      echo "# Database user nomad_user verified."
      return 0
    fi
    sleep 5
  done

  echo "# nomad_user not found. Creating manually..."
  docker exec nomad_mysql mariadb -u root -p"${root_password}" -e "
    CREATE DATABASE IF NOT EXISTS nomad;
    CREATE USER IF NOT EXISTS 'nomad_user'@'%' IDENTIFIED BY '${db_password}';
    GRANT ALL PRIVILEGES ON nomad.* TO 'nomad_user'@'%';
    FLUSH PRIVILEGES;
  "
  echo "# Database user created successfully."
}

setup_metal_notice() {
  echo -e "${YELLOW}#${RESET} Apple Silicon GPU (Metal) detected. For best AI performance, install Ollama natively: https://ollama.com/download\\n"
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your machine."
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

needs_sudo_for_nomad_dir() {
  [[ "$NOMAD_DIR" != "/Users/$USER"* ]]
}

run_with_optional_sudo() {
  if needs_sudo_for_nomad_dir; then
    sudo "$@"
  else
    "$@"
  fi
}

create_nomad_directory(){
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    run_with_optional_sudo mkdir -p "$NOMAD_DIR"
    if needs_sudo_for_nomad_dir; then
      sudo chown "$(whoami):$(id -gn)" "$NOMAD_DIR"
    fi

    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  run_with_optional_sudo mkdir -p "${NOMAD_DIR}/storage/logs"
  run_with_optional_sudo touch "${NOMAD_DIR}/storage/logs/admin.log"
}

generate_compose_env_file() {
  cat > "${SCRIPT_DIR}/compose.macos.env" << EOF
NOMAD_DIR=${NOMAD_DIR}
NOMAD_IMAGE=ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest
EOF

  run_with_optional_sudo cp "${SCRIPT_DIR}/compose.macos.env" "${NOMAD_DIR}/compose.macos.env"
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Installing docker-compose file for management...\\n"
  if [[ ! -f "$MACOS_COMPOSE_SOURCE" ]]; then
    echo -e "${RED}#${RESET} Missing macOS compose source at $MACOS_COMPOSE_SOURCE."
    exit 1
  fi
  run_with_optional_sudo cp "$MACOS_COMPOSE_SOURCE" "$compose_file_path"
  echo -e "${GREEN}#${RESET} Docker compose file installed successfully to $compose_file_path.\\n"

  generated_app_key=$(generateRandomPass)
  generated_db_root_password=$(generateRandomPass)
  generated_db_user_password=$(generateRandomPass)

  if [[ -d "${NOMAD_DIR}/mysql" ]]; then
    echo -e "${YELLOW}#${RESET} Removing existing MySQL data directory to ensure credentials match...\\n"
    run_with_optional_sudo rm -rf "${NOMAD_DIR}/mysql"
  fi

  echo -e "${YELLOW}#${RESET} Configuring docker-compose file env variables...\\n"
  substitute_compose_env_value "$compose_file_path" "URL" "http://${local_ip_address}:8080"
  substitute_compose_env_value "$compose_file_path" "APP_KEY" "$generated_app_key"
  substitute_compose_env_value "$compose_file_path" "DB_PASSWORD" "$generated_db_user_password"
  substitute_compose_env_value "$compose_file_path" "MYSQL_ROOT_PASSWORD" "$generated_db_root_password"
  substitute_compose_env_value "$compose_file_path" "MYSQL_PASSWORD" "$generated_db_user_password"
  validate_env_values "$compose_file_path"
  
  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_preppergrid_nomad_macos.sh"
  local stop_script_path="${NOMAD_DIR}/stop_preppergrid_nomad_macos.sh"
  local update_script_path="${NOMAD_DIR}/update_preppergrid_nomad_macos.sh"
  local plist_path="${NOMAD_DIR}/com.preppergrid.nomad.agent.plist"
  local launch_agents_dir="/Users/$USER/Library/LaunchAgents"
  local launch_agent_path="${launch_agents_dir}/com.preppergrid.nomad.agent.plist"

  echo -e "${YELLOW}#${RESET} Installing helper scripts...\\n"
  for required_file in "$MACOS_START_SOURCE" "$MACOS_STOP_SOURCE" "$MACOS_UPDATE_SOURCE" "$MACOS_PLIST_SOURCE"; do
    if [[ ! -f "$required_file" ]]; then
      echo -e "${RED}#${RESET} Missing helper source at $required_file."
      exit 1
    fi
  done

  run_with_optional_sudo cp "$MACOS_START_SOURCE" "$start_script_path"
  run_with_optional_sudo chmod +x "$start_script_path"

  run_with_optional_sudo cp "$MACOS_STOP_SOURCE" "$stop_script_path"
  run_with_optional_sudo chmod +x "$stop_script_path"

  run_with_optional_sudo cp "$MACOS_UPDATE_SOURCE" "$update_script_path"
  run_with_optional_sudo chmod +x "$update_script_path"

  sed "s|REPLACE_WITH_USERNAME|$USER|g" "$MACOS_PLIST_SOURCE" > "$plist_path"
  mkdir -p "$launch_agents_dir"
  sed "s|REPLACE_WITH_USERNAME|$USER|g" "$MACOS_PLIST_SOURCE" > "$launch_agent_path"

  echo -e "${GREEN}#${RESET} Helper scripts installed successfully to $NOMAD_DIR.\\n"
  echo -e "${GREEN}#${RESET} launchd agent installed to $launch_agent_path.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"
  if ! docker compose -p preppergrid-nomad -f "${NOMAD_DIR}/compose.yml" --env-file "${NOMAD_DIR}/compose.macos.env" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

get_local_ip() {
  local_ip_address=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    exit 1
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\n"
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D's Command Center should automatically start whenever your device reboots if you install the launchd agent. To start manually, run: ${WHITE_R}${NOMAD_DIR}/start_preppergrid_nomad_macos.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

check_is_macos
check_is_bash
ensure_dependencies_installed
check_is_debug_mode

get_install_confirmation
accept_terms
ensure_docker_installed
check_docker_compose
setup_metal_notice
get_local_ip
create_nomad_directory
generate_compose_env_file
download_helper_scripts
download_management_compose_file
start_management_containers
wait_for_mariadb_health
verify_database_user "$generated_db_root_password" "$generated_db_user_password"
success_message
