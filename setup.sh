#!/bin/bash

# --- Styling ---
TITLE_COLOR='\033[1;34m'
CHECK_COLOR='\033[1;32m'
UNCHECK_COLOR='\033[0;35m'
KEY_COLOR='\033[1;36m'
WARN_COLOR='\033[1;33m'
ERR_COLOR='\033[1;31m'
NC='\033[0m'

# --- Logging Functions ---
log_info()    { echo -e "${KEY_COLOR}[*]${NC} $1"; }
log_success() { echo -e "${CHECK_COLOR}[+]${NC} $1"; }
log_warn()    { echo -e "${WARN_COLOR}[!]${NC} $1"; }
log_error()   { echo -e "${ERR_COLOR}[!]${NC} $1"; }
log_sub()     { echo -e "${UNCHECK_COLOR}--> $1...${NC}"; }

# --- Global Registry ---
TOOLS=()
MENU_INDICES=()
MENU_SELECTED_INDICES=()
INSTALLED_ITEMS=()

# --- Help Function ---
show_help() {
  cat << EOF
Usage: ./setup.sh [options]

Options:
  -h                  Show this help message and exit
  --force-reinstall   Force a clean reinstall of all managed tools

This script manages the lifecycle of your development tools,
including SDKMAN versions, language servers, and Node.js utilities.
EOF
  exit 0
}

FORCE_REINSTALL=false

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      --force-reinstall)
        FORCE_REINSTALL=true
        shift
        ;;
    esac
  done
}

parse_args "$@"

# --- Force Reinstall Check ---
if [[ "$FORCE_REINSTALL" == "true" ]]; then
  echo -n "Are you sure you want to force reinstall of managed libraries? (y/N): "
  read -r confirm
  if [[ "$confirm" != "y" ]]; then
    log_info "Setup with reinstall aborted."
    exit 0
  fi
fi

# --- Registration Function ---
register_action() {
  local name="$1"
  local id="$2"
  local func_id="${id//-/_}"

  # Register name|flag|checker|installer|uninstaller
  TOOLS+=("$name|--install-$id|is_installed_$func_id|install_$func_id|uninstall_$func_id")
}

# --- UI Helpers ---
print_titled_header() {
  local title_text="$1"
  echo -e "${TITLE_COLOR}======================================${NC}"
  printf "${TITLE_COLOR}%b${NC}\n" "$title_text"
  echo -e "${TITLE_COLOR}======================================${NC}"
}

log_action() {
  local action="$1"
  local name="$2"
  echo -e "\n${TITLE_COLOR}--------------------------------------${NC}"
  echo -e "${TITLE_COLOR}[${NC} ${WARN_COLOR}${action}${NC} ${TITLE_COLOR}]${NC} ${KEY_COLOR}${name}${NC}"
  echo -e "${TITLE_COLOR}--------------------------------------${NC}"
}

log_installing() {
  local name="$1"
  log_action "INSTALLING" "$1"
}

log_uninstalling() {
  local name="$1"
  log_action "UNINSTALLING" "$1"
}

# --- Interactive Menu ---
menu_select_actions() {
  declare -n _indices=$1

  local selected=()
  local key_map=("1" "2" "3" "4" "5" "6" "7" "8" "9" "0" "q" "w" "e" "r" "t" "y" "u" "i" "o" "p")
  local menu_title="Select the actions to perform\n- Toggle with the key indicated\n- Press 'd' when done\n- Press 'a' to abort"

  local display_opts=()
  for idx in "${_indices[@]}"; do
    IFS='|' read -r name _ _ _ _ <<< "${TOOLS[$idx]}"
    display_opts+=("$name")
  done

  for i in "${!display_opts[@]}"; do
    selected[i]=0
  done

  while true; do
    clear
    print_titled_header "$menu_title"

    for i in "${!display_opts[@]}"; do
      local key="${key_map[$i]}"
      if [[ ${selected[$i]} -eq 1 ]]; then
        printf "${CHECK_COLOR}[✓]${NC} ${KEY_COLOR}(%s)${NC} %s\n" "$key" "${display_opts[$i]}"
      else
        printf "${UNCHECK_COLOR}[ ]${NC} ${KEY_COLOR}(%s)${NC} %s\n" "$key" "${display_opts[$i]}"
      fi
    done

    echo ""
    echo -n "Choose your option: "

    read -n 1 -r choice
    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
      echo -e "\n"
      log_error "Aborting setup."
      exit 1
    fi

    if [[ "$choice" == "d" || "$choice" == "D" ]]; then
      echo -e "\n"
      break
    fi

    for i in "${!key_map[@]}"; do
      if [[ "$choice" == "${key_map[$i]}" ]]; then
        if [[ -n "${display_opts[$i]}" ]]; then
          ((selected[i] ^= 1))
          break
        fi
      fi
    done
  done

  MENU_SELECTED_INDICES=()
  for i in "${!selected[@]}"; do
    if [[ ${selected[$i]} -eq 1 ]]; then
      MENU_SELECTED_INDICES+=("${_indices[$i]}")
    fi
  done
}

# --- Logic Functions ---
build_menu_lists() {
  MENU_INDICES=()
  INSTALLED_ITEMS=()
  for i in "${!TOOLS[@]}"; do
    IFS='|' read -r name _ checker _ _ <<< "${TOOLS[$i]}"
    if [[ "$FORCE_REINSTALL" == "false" ]] && "$checker"; then
      INSTALLED_ITEMS+=("$name")
    else
      MENU_INDICES+=("$i")
    fi
  done
}

display_installed_tools() {
  if [ ${#INSTALLED_ITEMS[@]} -gt 0 ]; then
    log_warn "The following items are already handled and will be skipped:"
    for item in "${INSTALLED_ITEMS[@]}"; do
      echo -e " - ${UNCHECK_COLOR}$item${NC}"
    done
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
  fi
}

run_menu() {
  if [ ${#MENU_INDICES[@]} -eq 0 ]; then
    log_success "All tools are already installed."
    exit 0
  fi
  menu_select_actions MENU_INDICES
}

install_system_packages() {
  local friendly_name="$1"
  shift
  local packages=("$@")

  # Detect System
  if [ -f /etc/debian_version ]; then
    log_info "Detected Debian/Ubuntu. Installing $friendly_name..."
    sudo apt update && sudo apt install -y "${packages[@]}"
  elif [ -f /etc/fedora-release ] || command -v dnf >/dev/null 2>&1; then
    log_info "Detected Fedora/RHEL. Installing $friendly_name..."
    sudo dnf install -y "${packages[@]}"
  else
    log_error "OS not supported for auto-installation. Please install $friendly_name manually."
    return 1
  fi
}

register_shell_path() {
  local line="$1"
  local shell_files=("$HOME/.zshrc" "$HOME/.bashrc")

  echo -e "\n${TITLE_COLOR}=== Configuring Shell Environment ===${NC}"
  for file in "${shell_files[@]}"; do
    if [ -f "$file" ]; then
      if ! grep -qF "$line" "$file"; then
        echo "$line" >> "$file"
        log_success "Added path to $file"
      else
        log_warn "Path already configured in $file"
      fi
    else
      log_warn "${file} not found, skipping."
    fi
  done
}

install_pipx() {
  if ! command -v pipx >/dev/null 2>&1; then
    log_installing "Pipx Package Manager for Python..."
    install_system_packages "pipx" "pipx"
    register_shell_path 'export PATH="$PATH:$HOME/.local/bin"'
  fi
}

ensure_pipx_available() {
  if command -v pipx >/dev/null 2>&1; then
    return 0
  fi

  log_warn "pipx not found in PATH. Initiating installation..."
  install_pipx

  # Refresh PATH for the current session immediately
  export PATH="$PATH:$HOME/.local/bin"

  # Final verification
  if command -v pipx >/dev/null 2>&1; then
    log_success "pipx is now ready to use."
    return 0
  else
    log_error "Critical error: pipx could not be found after installation."
    return 1
  fi
}

install_via_pipx() {
  local friendly_name="$1"
  local package="$2"

  if ensure_pipx_available; then
    log_installing "Installing $package via pipx"
    pipx install "$package"
  else
    log_error "Installation of $package skipped because pipx is unavailable."
    return 1
  fi
}

execute_uninstallers() {
  log_warn "Running uninstallers for selected tools..."
  for idx in "${MENU_SELECTED_INDICES[@]}"; do
    IFS='|' read -r name _ _ _ uninstaller <<< "${TOOLS[$idx]}"

    if declare -f "$uninstaller" > /dev/null; then
      log_sub "Cleaning up $name"
      $uninstaller
    fi
  done
}

execute_installers() {
  for idx in "${MENU_SELECTED_INDICES[@]}"; do
    IFS='|' read -r name flag _ installer _ <<< "${TOOLS[$idx]}"
    $installer
  done
  echo ""
}

# Set minimum Node.js version. It can be changed later if required by any tool:
REQUIRED_NODE_VERSION="20.19.2"
TOOLS_DIR="$HOME/.emacs.d/nodejs_tools"

check_node_version() {
  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js is not installed. Please install it before running this script."
    exit 1
  fi

  CURRENT_NODE_VERSION=$(node -v | sed 's/v//')

  # Version comparison logic: checks if current version is less than required version
  if [ ! "$(printf '%s\n' "$REQUIRED_NODE_VERSION" "$CURRENT_NODE_VERSION" | sort -V | head -n1)" = "$REQUIRED_NODE_VERSION" ]; then
    log_error "You have Node.js version $CURRENT_NODE_VERSION, but we require at least version $REQUIRED_NODE_VERSION to proceed."
    log_warn "Please update Node.js before proceeding."
    exit 1
  fi

  log_success "Node.js $CURRENT_NODE_VERSION meets the requirement ($REQUIRED_NODE_VERSION)."
}

install_nodejs_tools() {
  log_installing "Installing Node.js tools used by Emacs packages..."
  check_node_version

  if [ ! -d "$TOOLS_DIR" ]; then
    log_error "Directory $TOOLS_DIR not found. Skipping npm install."
    return 1
  fi

  cd "$TOOLS_DIR" || exit 1
  npm install
}

uninstall_nodejs_tools() {
  log_uninstalling "Uninstalling Node.js tools used by Emacs packages..."
  [ -d "$TOOLS_DIR/node_modules" ] && rm -Rf "$TOOLS_DIR/node_modules"
  log_success "Sucessfully removed '$TOOLS_DIR/node_modules'"
}

if [ ! -f "./init.el" ]; then
  print_titled_header "Bootstraping init.el..."
  cp -v "init-bootstrap.el" "init.el"
fi

is_installed_list_of_secrets() {
  return 1 # We should detect it later
}

install_list_of_secrets() {
  log_installing "Installing list of secrets..."
  AUTH_FILE="$HOME/.authinfo.gpg"
  TEMP_FILE=$(mktemp)
  chmod 600 "$TEMP_FILE"

  log_info "Setting up AI API Tokens"
  echo "  (Files will be stored in $AUTH_FILE)"

  # Decrypt existing file if it exists
  if [ -f "$AUTH_FILE" ]; then
    log_info "Decrypting existing credentials..."
    # Try to decrypt. If it fails (e.g. bad passphrase), we abort to be safe
    gpg --quiet --decrypt "$AUTH_FILE" > "$TEMP_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
      log_error "Could not decrypt existing file. Aborting to prevent data loss."
      rm "$TEMP_FILE"
      exit 1
    fi
  else
    log_info "Creating new credentials file..."
    touch "$TEMP_FILE"
  fi

  # Helper to update a key
  update_key() {
    local machine=$1
    local user=$2
    local name=$3

    echo ""
    read -s -p "Enter $name API Key (leave empty to keep existing): " key
    echo ""

    if [ ! -z "$key" ]; then
      # Cleanly remove existing entry for this machine/user combo
      # We use a temp file for sed to avoid issues in some environments
      sed -i "/machine $machine login $user/d" "$TEMP_FILE"
      # Add new entry
      echo "machine $machine login $user password $key" >> "$TEMP_FILE"
      log_success "Updated $name key."
    else
      log_info "Skipping $name (unchanged)."
    fi
  }

  # Prompt for keys
  update_key "api.github.com" "apikey" "GitHub Copilot"
  update_key "generativelanguage.googleapis.com" "apikey" "Google Gemini"
  update_key "api.groq.com" "apikey" "Groq"
  update_key "api.deepseek.com" "apikey" "DeepSeek"
  update_key "api.openai.com" "apikey" "OpenAI"

  # Encrypt back
  log_info "Encrypting credentials..."
  # We encrypt for the current user
  RECIPIENT=$(whoami)
  gpg --yes --quiet --encrypt --recipient "$RECIPIENT" --output "$AUTH_FILE" "$TEMP_FILE"

  if [ $? -eq 0 ]; then
    log_success "Success! Credentials saved to $AUTH_FILE"
  else
    log_error "Encryption failed."
  fi

  # Secure cleanup
  shred -u "$TEMP_FILE" 2>/dev/null || rm "$TEMP_FILE"
  exit 0
}

uninstall_list_of_secrets() {
  log_uninstalling "Uninstalling list of secrets..."
  log_info "Skipping secrets uninstall"
}

register_action "Setup encrypted authinfo" "list-of-secrets"

is_installed_semgrep() {
  command -v semgrep >/dev/null 2>&1
}

install_semgrep() {
  install_via_pipx "Semgrep" "semgrep"
}

uninstall_semgrep() {
  log_uninstalling "Uninstalling Semgrep..."
  pipx uninstall semgrep 2>/dev/null
  log_info "Note: pipx was preserved, as it may be utilized by other projects."
}

register_action "Install Semgrep" "semgrep"

is_installed_copilot() {
  REQUIRED_NODE_VERSION="22.0.0" # Minimum requirement for Copilot
  check_node_version
  [ -f "$TOOLS_DIR/node_modules/.bin/copilot-language-server" ] || command -v copilot-language-server >/dev/null 2>&1
}

install_copilot() {
  install_nodejs_tools
}

uninstall_copilot() {
  log_uninstalling "Uninstalling Copilot Tools (via Node.js tools)"
  log_info "Current limitation: all local Node.js tools will be removed in this step"
  uninstall_nodejs_tools
}

register_action "Install GitHub Copilot" "copilot"

IS_SDKMAN_INITIALIZED=false

is_sdkman_installed() {
  if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    return 0
  fi

  return 1
}

initialize_sdkman() {
  if [ "$IS_SDKMAN_INITIALIZED" = false ]; then
    if is_sdkman_installed; then
      source "$HOME/.sdkman/bin/sdkman-init.sh"
      sdk version || exit 1
      IS_SDKMAN_INITIALIZED=true
      log_success "SDKMAN found in your environment and initialized."
    else
      log_error "SDKMAN not found in your environment. We require SDKMAN for Java-related tools."
      exit 1
    fi
  fi
}

install_sdkman() {
  if ! is_sdkman_installed; then
    log_sub "Setting up SDKMAN!"
    curl -s "https://get.sdkman.io" | bash
  fi
  initialize_sdkman
}

# Download specific version of JDTLS. Update version/date as needed:
JDTLS_VERSION="1.57.0"
JDTLS_DATE="202602261110"
JDTLS_TARGET_DIR="$HOME/.emacs.d/lsp_language_servers/eclipse.jdt.ls"

is_installed_jdtls() {
  [ -f "$JDTLS_TARGET_DIR/bin/jdtls" ]
}

install_jdtls() {
  if ! is_installed_jdtls; then
    log_sub "Setting up Eclipse JDT Language Server (jdtls)"

    local JDTLS_TMP_DIR
    JDTLS_TMP_DIR=$(mktemp -d)
    mkdir -p "$JDTLS_TARGET_DIR"
    curl -L -o "$JDTLS_TMP_DIR/jdtls.tar.gz" \
         "https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_DATE}.tar.gz"

    tar -xzf "$JDTLS_TMP_DIR/jdtls.tar.gz" -C "$JDTLS_TARGET_DIR"
    rm -rf "$JDTLS_TMP_DIR"

    log_success "Installed to $JDTLS_TARGET_DIR"
  fi
}

is_installed_java() {
  return 1 # SDKMAN! will skip already installed versions
}

install_java() {
  log_installing "Installing Java versions (via SDKMAN!)..."
  install_jdtls
  install_sdkman

  JAVA_VERSIONS_TO_INSTALL=(
    "8.0.482-tem"
    "11.0.30-tem"
    "17.0.18-tem"
    "21.0.10-tem"
    "25.0.2-tem"
  )

  for v in "${JAVA_VERSIONS_TO_INSTALL[@]}"; do
    log_sub "Installing Java version: $v"
    sdk install java "$v"
  done
}

uninstall_java() {
  log_uninstalling "Uninstalling Java..."
  log_info "Note: Java SDKs were preserved, as they may be utilized by other projects."
}

register_action "Install Java" "java"

KLS_VERSION="1.3.13"
KLS_TARGET_DIR="$HOME/.emacs.d/lsp_language_servers/kotlin.ls"

is_installed_kls() {
  [ -f "$KLS_TARGET_DIR/bin/kotlin-language-server" ]
}

install_kls() {
  if ! is_installed_kls; then
    local KLS_TMP_DIR
    KLS_TMP_DIR=$(mktemp -d)

    log_info "Downloading prebuilt Kotlin Language Server (KLS)"
    curl -L "https://github.com/fwcd/kotlin-language-server/releases/download/$KLS_VERSION/server.zip" -o "$KLS_TMP_DIR/kotlin-language-server.zip"

    log_info "Extracting Kotlin Language Server..."
    rm -Rf "$KLS_TARGET_DIR" # Clean previous install
    mkdir -p "$KLS_TARGET_DIR"
    unzip -q "$KLS_TMP_DIR/kotlin-language-server.zip" -d "$KLS_TMP_DIR"
    mv "$KLS_TMP_DIR/server"/* "$KLS_TARGET_DIR/"
    rm -Rf "$KLS_TMP_DIR"

    log_success "Kotlin Language Server installed to $KLS_TARGET_DIR"
    log_warn "IMPORTANT: You need Java (JDK 11+) installed for the server to run!"
  fi
}

is_installed_kotlin() {
  return 1 # SDKMAN! will skip already installed versions
}

install_kotlin() {
  log_installing "Installing Kotlin versions (via SDKMAN!)..."
  install_kls
  install_sdkman

  KOTLIN_VERSIONS_TO_INSTALL=(
    "2.3.10"
  )

  for v in "${KOTLIN_VERSIONS_TO_INSTALL[@]}"; do
    log_sub "Installing Kotlin version: $v"
    sdk install kotlin "$v"
  done
}

uninstall_kotlin() {
  log_uninstalling "Uninstalling Kotlin..."
  log_info "Note: Kotlin SDKs were preserved, as they may be utilized by other projects."
}

register_action "Install Kotlin" "kotlin"

LSP_BASH_LANGUAGE_SERVER_PATH="$HOME/.emacs.d/.cache/lsp/npm/bash-language-server"

is_installed_bash_language_server() {
    echo "$TOOLS_DIR/node_modules/.bin/bash-language-server"
  [ -f "$TOOLS_DIR/node_modules/.bin/bash-language-server" ] || command -v bash-language-server >/dev/null 2>&1
}

install_bash_language_server() {
  install_nodejs_tools
  log_installing "Installing Bash Language Server..."
  # Small hack for bash-language-server to work with lsp-mode: setting `lsp-bash-bash-language-server-path`
  # did not work as expected for unknown reasons.
  [ -d "$LSP_BASH_LANGUAGE_SERVER_PATH" ] && rm -Rf "$LSP_BASH_LANGUAGE_SERVER_PATH"
  mkdir -p "$LSP_BASH_LANGUAGE_SERVER_PATH/bin/"
  ln -s "$TOOLS_DIR/node_modules/.bin/bash-language-server" "$LSP_BASH_LANGUAGE_SERVER_PATH/bin/bash-language-server"
}

uninstall_bash_language_server() {
  log_uninstalling "Uninstalling Bash Language Server (via Node.js tools)..."
  log_info "Current limitation: all local Node.js tools will be removed in this step"
  uninstall_nodejs_tools
  [ -d "$LSP_BASH_LANGUAGE_SERVER_PATH" ] && rm -Rf "$LSP_BASH_LANGUAGE_SERVER_PATH"
  log_success "Sucessfully removed '$LSP_BASH_LANGUAGE_SERVER_PATH'"
}

register_action "Install Bash Language Server" "bash-language-server"

is_installed_autotools_language_server() {
  command -v autotools-language-server >/dev/null 2>&1
}

install_autotools_language_server() {
  log_installing "Installing Autotools Language Server..."
  install_via_pipx "Autotools Language Server" "autotools-language-server"
}

uninstall_autotools_language_server() {
  log_uninstalling "Installing Autotools Language Server (via pipx)..."
  pipx uninstall autotools-language-server 2>/dev/null
  log_info "Note: pipx was preserved, as it may be utilized by other projects."
}

register_action "Install Autotools Language Server" "autotools-language-server"

# Update PlantUML version as needed:
PLANTUML_VERSION="1.2026.2"
PLANTUML_DIR="$HOME/.emacs.d/plantuml"

is_installed_plantuml() {
  [ -f "$HOME/.emacs.d/plantuml/plantuml.jar" ]
}

install_plantuml() {
  log_installing "Installing PlantUML..."

  local PLANTUML_JAR="$PLANTUML_DIR/plantuml.jar"
  local PLANTUML_URL="https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

  if [ -f "$PLANTUML_JAR" ]; then
    log_info "PlantUML is already installed at $PLANTUML_JAR"
  else
    log_info "Downloading PlantUML..."
    mkdir -p "$PLANTUML_DIR"
    curl -L "$PLANTUML_URL" -o "$PLANTUML_JAR"
    log_success "PlantUML installed to $PLANTUML_JAR"
  fi
}

uninstall_plantuml() {
  log_uninstalling "Uninstalling PlantUML..."
  [ -d "$PLANTUML_DIR" ] && rm -Rf "$PLANTUML_DIR"
  log_success "Sucessfully removed '$PLANTUML_DIR'"
}

register_action "Install PlantUML" "plantuml"

# --- Runtime Logic ---
build_menu_lists
display_installed_tools
run_menu
if [[ "$FORCE_REINSTALL" == "true" ]]; then
  execute_uninstallers
fi
execute_installers
