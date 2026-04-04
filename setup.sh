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
log_skip()    {
  local label="$1"
  local status="${2:-SKIPPED}"
  echo -e "  ${UNCHECK_COLOR}→${NC} ${label}... ${WARN_COLOR}[${status}]${NC}"
}

# --- Global Registry ---
TOOLS=()
MENU_INDICES=()
MENU_SELECTED_INDICES=()
INSTALLED_ITEMS=()

declare -A SYSTEM_PACKAGES_MAP

# --- Installer Group Titles (Order defines UI sequence) ---
INSTALLER_GROUPS=(
  "secrets|Security & Credentials"
  "node|Node.js Toolchain (Shared)"
  "jvm|JVM Toolchain (SDKMAN!)"
  "standalone|General Purpose Tools"
)

# --- Help Function ---
show_help() {
  cat << EOF
Usage: ./setup.sh [options]

Options:
  -h                  Show this help message and exit
  --force-reinstall   Force a clean reinstall of all managed tools
  -v/--verbose        Enable verbose output

This script manages the lifecycle of your development tools,
including SDKMAN! versions, language servers, and Node.js utilities.
EOF
  exit 0
}

FORCE_REINSTALL=false
VERBOSE=false

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
      -v|--verbose)
        VERBOSE=true;
        shift
        ;;
    esac
  done
}

parse_args "$@"

# --- Execution Wrapper ---
run_task() {
  local label="$1"
  local cmd="$2"

  if [[ "$VERBOSE" == "true" ]]; then
    # Use a subtle separator instead of a giant box
    echo -e "\n${TITLE_COLOR}--- [ RUNNING: $label ] ---${NC}"

    if eval "$cmd"; then
      log_success "$label completed successfully."
      echo -e "${TITLE_COLOR}----------------------------------------------------${NC}"
      return 0
    else
      log_error "$label failed."
      echo -e "${TITLE_COLOR}----------------------------------------------------${NC}"
      return 1
    fi
  else
    # Quiet Mode remains exactly the same
    echo -ne "  ${UNCHECK_COLOR}→${NC} ${label}... "
    local tmp_log
    tmp_log=$(mktemp)

    if [[ "$cmd" == *"sudo"* ]] && ! sudo -n true 2>/dev/null; then
      # Move cursor to the next line for the password prompt
      # and do not break the UI:
      echo ""
    fi

    if eval "$cmd" > "$tmp_log" 2>&1; then
      echo -e "${CHECK_COLOR}[OK]${NC}"
      rm "$tmp_log"
      return 0
    else
      echo -e "${ERR_COLOR}[FAILED]${NC}"
      log_error "Error details for $label:"
      sed 's/^/    /' "$tmp_log"
      rm "$tmp_log"
      return 1
    fi
  fi
}

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
  local group="${3:-standalone}" # Default to standalone if not provided
  local func_id="${id//-/_}"

  # Format: name | flag | checker | installer | uninstaller | group
  TOOLS+=("$name|--install-$id|is_installed_$func_id|install_$func_id|uninstall_$func_id|$group")
}

# --- UI Helpers ---
print_titled_header() {
  local title_text="$1"
  echo -e "${TITLE_COLOR}────────────────────────────────────────────────────${NC}"
  printf "${TITLE_COLOR}%b${NC}\n" "$title_text"
  echo -e "${TITLE_COLOR}────────────────────────────────────────────────────${NC}"
}

log_action() {
  local action="$1"
  local name="$2"
  echo -e "\n${TITLE_COLOR}----------------------------------------------------${NC}"
  echo -e "${TITLE_COLOR}[${NC} ${WARN_COLOR}${action}${NC} ${TITLE_COLOR}]${NC} ${KEY_COLOR}${name}${NC}"
  echo -e "${TITLE_COLOR}----------------------------------------------------${NC}"
}

log_installing() {
  local name="$1"
  log_action "INSTALLING" "$1"
}

log_uninstalling() {
  local name="$1"
  log_action "UNINSTALLING" "$1"
}

# --- Other ---
sort_tools_by_group() {
  local sorted=()

  for entry in "${INSTALLER_GROUPS[@]}"; do
    IFS='|' read -r g_key _ <<< "$entry"

    for tool in "${TOOLS[@]}"; do
      IFS='|' read -r _ _ _ _ _ t_group <<< "$tool"

      if [[ "$t_group" == "$g_key" ]]; then
        sorted+=("$tool")
      fi
    done
  done

  # Catch-all for tools registered with a group not in INSTALLER_GROUPS
  for tool in "${TOOLS[@]}"; do
    IFS='|' read -r _ _ _ _ _ t_group <<< "$tool"
    local found=false
    for entry in "${INSTALLER_GROUPS[@]}"; do
      [[ "${entry%%|*}" == "$t_group" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && sorted+=("$tool")
  done

  TOOLS=("${sorted[@]}")
}

get_group_title() {
  local search_key="$1"
  for entry in "${INSTALLER_GROUPS[@]}"; do
    if [[ "${entry%%|*}" == "$search_key" ]]; then
      echo "${entry#*|}"
      return
    fi
  done
  echo "$search_key"
}

get_os_family() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "mac"
    return 0
  fi

  if [[ -f /etc/os-release ]]; then
    local os_id
    os_id=$(grep -i '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]')

    case "$os_id" in
      "fedora"|"rhel"|"centos") echo "fedora" ;;
      "ubuntu"|"debian"|"pop"|"mint") echo "debian-ubuntu" ;;
      "alpine") echo "alpine" ;;
      *) echo "$os_id" ;;
    esac
    return 0
  fi

  echo "unknown"
}

OS_FAMILY=$(get_os_family)

# --- Interactive Menu ---
menu_select_actions() {
  declare -n _indices=$1
  local cursor=0
  local selected=()
  local num_items=${#_indices[@]}

  for i in "${!_indices[@]}"; do selected[i]=0; done

  tput civis
  stty -echo -icanon isig
  clear
  trap "stty echo icanon; tput cnorm; exit" INT TERM EXIT

  while true; do
    tput cup 0 0
    local frame=""
    print_titled_header "Select the actions to perform"

    for i in "${!_indices[@]}"; do
      local idx=${_indices[$i]}
      IFS='|' read -r name _ _ _ _ <<< "${TOOLS[$idx]}"
      local pointer="  "
      local bracket="[ ]"
      [[ $i -eq $cursor ]] && pointer="${TITLE_COLOR}> ${NC}"
      [[ ${selected[$i]} -eq 1 ]] && bracket="${CHECK_COLOR}[✓]${NC}"

      if [[ $i -eq $cursor ]]; then
        frame+="  ${pointer}${bracket} ${TITLE_COLOR}${name}${NC}$(tput el)\n"
      else
        frame+="    ${bracket} ${name}$(tput el)\n"
      fi
    done

    frame+="${TITLE_COLOR}────────────────────────────────────────────────────${NC}\n"
    frame+=" $(printf "%b↑/↓/n/p%b Navigate  %bSPACE%b Toggle  %bENTER%b Run  %bA%b Abort" "${KEY_COLOR}" "${NC}" "${KEY_COLOR}" "${NC}" "${CHECK_COLOR}" "${NC}" "${ERR_COLOR}" "${NC}")\n"
    frame+="${TITLE_COLOR}────────────────────────────────────────────────────${NC}\n"
    frame+="$(tput ed)"

    echo -ne "$frame"

    # Input gatekeeper: wait for the first interaction
    local key
    if ! IFS= read -rsn1 key; then break; fi

    # Then we process the immediate key
    case "$key" in
      $'\e')
        read -rsn2 -t 0.01 seq
        [[ "$seq" == "[A" ]] && ((cursor = (cursor - 1 + num_items) % num_items))
        [[ "$seq" == "[B" ]] && ((cursor = (cursor + 1) % num_items))
        ;;
      " ") ((selected[cursor] ^= 1)) ;;
      "p") ((cursor = (cursor - 1 + num_items) % num_items)) ;;
      "n") ((cursor = (cursor + 1) % num_items)) ;;
      # The "Triple-Catch" for Enter:
      # 1. $'\x0a' (Line Feed)
      # 2. $'\x0d' (Carriage Return)
      # 3. "" (Empty string - often how read -n1 returns a newline)
      $'\x0a'|$'\x0d'|"") break ;;
      "a"|"A") stty echo icanon; tput cnorm; clear; exit 1 ;;
    esac

    # Below we drain the buffer and jump to the last key
    # We attempt to read a large chunk (100 chars) that accumulated
    # while the script was redrawing. This might happen when keeping
    # the key pressed and the keyboard sends repeated keys fast:
    local extra=""
    if IFS= read -rsn100 -t 0.01 extra; then
      # If the chunk contains arrow sequences, find the LAST one
      # and move the cursor there immediately.
      if [[ "$extra" == *$'\e[A'* ]]; then
        ((cursor = (cursor - 1 + num_items) % num_items))
      elif [[ "$extra" == *$'\e[B'* ]]; then
        ((cursor = (cursor + 1) % num_items))
      fi

      # Clear any toggles (spaces) that were in the burst
      local space_count
      space_count=$(echo "$extra" | tr -cd ' ' | wc -c)
      if (( space_count > 0 )); then
         # This part is tricky; usually we don't want to "burst" toggle
         # but we can toggle the current cursor if spaces were found.
         ((selected[cursor] ^= (space_count % 2)))
      fi

      # Immediately drop everything else in the hardware buffer.
      # This stops the "sliding" effect when pressing and holding the key.
      stty flush ioproc >/dev/null 2>&1
    fi

    # Giving the terminal some time to breath
    sleep 0.01
  done

  stty echo icanon
  tput cnorm
  clear

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

get_safe_key() {
  echo "$1" | xargs | tr '[:upper:]' '[:lower:]' | sed 's/+/p/g' | tr '-' '_'
}

register_system_package() {
  local friendly_name="$1"
  local internal_key
  internal_key=$(get_safe_key "$friendly_name")

  shift

  SYSTEM_PACKAGES_MAP["$internal_key"]+="${SYSTEM_PACKAGES_MAP["$internal_key"]:+ }$*"
}

get_registered_package_name() {
  local friendly_name="$1"
  local internal_key
  internal_key=$(get_safe_key "$friendly_name")
  local all_mappings="${SYSTEM_PACKAGES_MAP["$internal_key"]}"

  [[ -z "$all_mappings" ]] && return 1

  for mapping in $all_mappings; do
    if [[ "$mapping" == "$OS_FAMILY:"* ]]; then
      echo "${mapping#*:}"
      return 0
    fi
  done
  return 1
}

print_system_packages_map() {
  echo -e "${TITLE_COLOR}Current System Package Mappings:${NC}"
  echo "────────────────────────────────────────────────────"

  # Check if the map is empty first
  if [[ ${#SYSTEM_PACKAGES_MAP[@]} -eq 0 ]]; then
    echo "  (Map is empty. Ensure 'declare -A SYSTEM_PACKAGES_MAP' is at the top.)"
    return 1
  fi

  # Iterate through all keys in the associative array
  for key in "${!SYSTEM_PACKAGES_MAP[@]}"; do
    printf "  ${KEY_COLOR}%-20s${NC} | %s\n" "$key" "${SYSTEM_PACKAGES_MAP[$key]}"
  done

  echo "────────────────────────────────────────────────────"
}

is_system_package_installed() {
  local friendly_name="$1"
  local pkg_name

  # Let the helper handle the safe_key conversion and mapping
  pkg_name=$(get_registered_package_name "$friendly_name")
  [[ -z "$pkg_name" ]] && return 1

  case "$OS_FAMILY" in
    "fedora")
      rpm -q "$pkg_name" >/dev/null 2>&1 || \
      rpm -q --whatprovides "$pkg_name" >/dev/null 2>&1
      ;;
    "debian-ubuntu")
      dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q "ok installed"
      ;;
    "mac"|"linuxbrew")
      brew list "$pkg_name" >/dev/null 2>&1
      ;;
    "alpine")
      apk info -e "$pkg_name" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

are_these_system_packages_installed() {
  for package in "$@"; do
    if ! is_system_package_installed "$package"; then
      return 1
    fi
  done

  return 0
}

install_system_package() {
  local friendly_name="$1"
  local os_label=""
  local cmd_prefix=""
  local distro_key=""

  if [[ "$OSTYPE" == "darwin"* ]]; then
    distro_key="mac"
    os_label="macOS (Homebrew)"
    cmd_prefix="brew install"
  elif [ -f /etc/debian_version ]; then
    distro_key="debian-ubuntu"
    os_label="Debian/Ubuntu"
    cmd_prefix="sudo DEBIAN_FRONTEND=noninteractive apt update && sudo apt install -y"
  elif [ -f /etc/fedora-release ] || command -v dnf >/dev/null 2>&1; then
    distro_key="fedora"
    os_label="Fedora/RHEL"
    cmd_prefix="sudo dnf install -y"
  elif [ -f /etc/alpine-release ] || command -v apk >/dev/null 2>&1; then
    distro_key="alpine"
    os_label="Alpine"
    cmd_prefix="sudo apk add"
  elif command -v brew >/dev/null 2>&1; then
    # This handles Homebrew on Linux if no other match was found
    distro_key="linuxbrew"
    os_label="Linux (Homebrew)"
    cmd_prefix="brew install"
  else
    log_error "OS not supported for auto-installation."
    return 1
  fi

  local pkg_to_install
  pkg_to_install=$(get_registered_package_name "$friendly_name")

  if [ -z "$pkg_to_install" ]; then
    log_error "Package '$friendly_name' not found in setup for $os_label."
    return 1
  fi

  if [ -z "$pkg_to_install" ]; then
    log_error "Package '$friendly_name' not found in setup for $os_label."
    return 1
  fi

  local final_cmd="$cmd_prefix $pkg_to_install"

  if [[ "$FORCE_REINSTALL" == "true" ]]; then
    case "$distro_key" in
      debian-ubuntu)
        final_cmd="$cmd_prefix --reinstall $pkg_to_install"
        ;;
      fedora|mac|linuxbrew)
        final_cmd="${cmd_prefix/install/reinstall} $pkg_to_install"
        ;;
      alpine)
        final_cmd="$cmd_prefix --force-reinstall $pkg_to_install"
        ;;
    esac
  fi

  run_task "System: Installing $friendly_name ($os_label)" "$final_cmd"
}

install_system_packages() {
  for package in "$@"; do
    if ! is_system_package_installed "$package" || [[ "$FORCE_REINSTALL" == "true" ]]; then
      install_system_package "$package"
    else
      log_skip "$package" "ALREADY INSTALLED"
    fi
  done
}

register_shell_path() {
  local line="$1"
  local shell_files=("$HOME/.zshrc" "$HOME/.bashrc")
  local changed=false

  for file in "${shell_files[@]}"; do
    if [ -f "$file" ]; then
      if ! grep -qF "$line" "$file"; then
        echo "$line" >> "$file"
        changed=true
      fi
    fi
  done

  if [ "$changed" = true ]; then
    log_success "Shell environment updated."
  else
    log_skip "Shell environment" "ALREADY SET"
  fi
}

register_system_package "pipx" \
                        "alpine:pipx" \
                        "fedora:pipx" \
                        "linuxbrew:pipx" \
                        "mac:pipx" \
                        "debian-ubuntu:pipx"

install_pipx() {
  if ! command -v pipx >/dev/null 2>&1; then
    install_system_packages "pipx"

    run_task "Configuring pipx path" "export PATH=\"\$PATH:\$HOME/.local/bin\""
    # shellcheck disable=SC2016
    register_shell_path 'export PATH="$PATH:$HOME/.local/bin"'
  else
    log_skip "Pipx" "EXISTS"
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
    run_task "$friendly_name via pipx" "pipx install $package"
  else
    log_error "Installation of $package skipped because pipx is unavailable."
    return 1
  fi
}

execute_uninstallers() {
  [[ ${#MENU_SELECTED_INDICES[@]} -eq 0 ]] && return 0

  print_titled_header "Starting Cleanup Phase"
  LAST_GROUP_PRINTED=""

  for idx in "${MENU_SELECTED_INDICES[@]}"; do
    IFS='|' read -r name _ checker installer uninstaller group <<< "${TOOLS[$idx]}"

    if [[ "$group" != "$LAST_GROUP_PRINTED" ]]; then
      local group_title
      group_title=$(get_group_title "$group")
      log_uninstalling "$group_title"
      LAST_GROUP_PRINTED="$group"
    fi

    if declare -f "$uninstaller" > /dev/null; then
      $uninstaller
    fi
  done
  echo ""
}

execute_installers() {
  [[ ${#MENU_SELECTED_INDICES[@]} -eq 0 ]] && return 0

  print_titled_header "Starting Installation Phase"
  LAST_GROUP_PRINTED=""

  for idx in "${MENU_SELECTED_INDICES[@]}"; do
    IFS='|' read -r name _ checker installer uninstaller group <<< "${TOOLS[$idx]}"

    if [[ "$group" != "$LAST_GROUP_PRINTED" ]]; then
      # We use the helper function to find the friendly name in our unified array
      local group_title
      group_title=$(get_group_title "$group")

      log_installing "$group_title"
      LAST_GROUP_PRINTED="$group"
    fi

    if declare -f "$installer" > /dev/null; then
      $installer
    else
      log_error "Installer function $installer not found."
    fi
  done

  echo ""
  log_success "All selected tasks completed."
}

NVM_VERSION="v0.40.4"
NODE_TARGET_VERSION="22.22.1"
TOOLS_DIR="$HOME/.emacs.d/nodejs_tools"

load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

is_installed_nvm() {
  [ -d "$HOME/.nvm" ]
}

install_nvm() {
  if ! is_installed_nvm; then
    run_task "Installing NVM ($NVM_VERSION)" "curl -sL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
    load_nvm
  else
    load_nvm
    # Use our new skip helper instead of log_info
    log_skip "NVM" "ACTIVE"
  fi
}

ensure_nvm_available() {
  load_nvm
  if ! command -v nvm >/dev/null 2>&1; then
    install_nvm
  fi
  command -v nvm >/dev/null 2>&1
}

ARE_NODEJS_TOOLS_INSTALLED=false
ARE_NODEJS_TOOLS_UNINSTALLED=false
install_nodejs_tools() {
  [[ "$ARE_NODEJS_TOOLS_INSTALLED" == "true" ]] && return 0

  ensure_nvm_available || { log_error "NVM bootstrap failed"; return 1; }

  run_task "Node.js $NODE_TARGET_VERSION" "nvm install $NODE_TARGET_VERSION" || return 1

  if [ -d "$TOOLS_DIR" ]; then
    run_task "Updating node_modules" "cd $TOOLS_DIR && nvm exec $NODE_TARGET_VERSION npm install"
  else
    log_error "Tools directory missing: $TOOLS_DIR"
    return 1
  fi

  # shellcheck disable=SC2034
  ARE_NODEJS_TOOLS_UUNINSTALLED=false
  ARE_NODEJS_TOOLS_INSTALLED=true
}

uninstall_nodejs_tools() {
  [[ "$ARE_NODEJS_TOOLS_UNINSTALLED" == "true" ]] && return 0

  if [ -d "$TOOLS_DIR/node_modules" ]; then
    run_task "Node.js toolchain: Removing node_modules" "rm -Rf $TOOLS_DIR/node_modules"
  else
    log_skip "Node.js toolchain (node_modules)" "NOT FOUND"
  fi

  ARE_NODEJS_TOOLS_INSTALLED=false
  ARE_NODEJS_TOOLS_UNINSTALLED=true
}

if [ ! -f "./init.el" ]; then
  print_titled_header "Bootstraping init.el..."
  cp -v "init-bootstrap.el" "init.el"
fi

is_installed_list_of_secrets() {
  [ -f "$HOME/.authinfo.gpg" ]
}

install_list_of_secrets() {
  AUTH_FILE="$HOME/.authinfo.gpg"
  TEMP_FILE=$(mktemp)
  chmod 600 "$TEMP_FILE"

  if [ -f "$AUTH_FILE" ]; then
    if ! run_task "Decrypting existing credentials" "gpg --quiet --decrypt $AUTH_FILE > $TEMP_FILE"; then
      log_error "Decryption failed. Aborting to prevent data loss."
      rm "$TEMP_FILE"
      return 1
    fi
  else
    run_task "Initializing new vault" "touch $TEMP_FILE"
  fi

  echo -e "\n${KEY_COLOR}[*]${NC} Setting up AI API Tokens"
  echo -e "    (Vault: $AUTH_FILE)\n"

  update_key() {
    local machine=$1
    local user=$2
    local name=$3
    local key

    read -rs -p "  Enter $name API Key (leave empty to keep existing): " key
    echo ""

    if [ -n "$key" ]; then
      sed -i "/machine $machine login $user/d" "$TEMP_FILE"
      echo "machine $machine login $user password $key" >> "$TEMP_FILE"
      log_success "Updated $name"
    else
      log_info "Skipping $name (unchanged)"
    fi
  }

  update_key "api.github.com" "apikey" "GitHub Copilot"
  update_key "generativelanguage.googleapis.com" "apikey" "Google Gemini"
  update_key "api.groq.com" "apikey" "Groq"
  update_key "api.deepseek.com" "apikey" "DeepSeek"
  update_key "api.openai.com" "apikey" "OpenAI"

  echo ""
  RECIPIENT=$(whoami)

  run_task "Encrypting vault" "gpg --yes --quiet --batch --encrypt --recipient $RECIPIENT --output $AUTH_FILE $TEMP_FILE"

  run_task "Securely cleaning temporary data" "shred -u $TEMP_FILE 2>/dev/null || rm $TEMP_FILE"
}

uninstall_list_of_secrets() {
  log_skip "Encrypted secrets vault"
}

register_action "Setup encrypted authinfo" "list-of-secrets" "secrets"

DIRVISH_UTILITIES=(
  "fd" "git"
  "mediainfo" "imagemagick" "ffmpegthumbnailer" "vipsthumbnail"
  "poppler" "unzip" "glow" "pandoc"
)

is_installed_dirvish_utilities_bundle() {
  are_these_system_packages_installed "${DIRVISH_UTILITIES[@]}"
}

# --- Core Performance & Navigation ---
# Used for fast searching, jumping to files, and directory rendering.
register_system_package "fd" \
                        "alpine:fd" \
                        "fedora:fd-find" \
                        "linuxbrew:fd" \
                        "mac:fd" \
                        "debian-ubuntu:fd-find"

register_system_package "git" \
                        "alpine:git" \
                        "fedora:git" \
                        "linuxbrew:git" \
                        "mac:git" \
                        "debian-ubuntu:git"

# --- Media Metadata & Previews ---
# Used by dispatchers to show technical info and thumbnails for video/audio/images.
register_system_package "mediainfo" \
                        "alpine:mediainfo" \
                        "fedora:mediainfo" \
                        "linuxbrew:mediainfo" \
                        "mac:mediainfo" \
                        "debian-ubuntu:mediainfo"

register_system_package "imagemagick" \
                        "alpine:imagemagick" \
                        "fedora:ImageMagick" \
                        "linuxbrew:imagemagick" \
                        "mac:imagemagick" \
                        "debian-ubuntu:imagemagick"

register_system_package "ffmpegthumbnailer" \
                        "alpine:ffmpegthumbnailer" \
                        "fedora:ffmpegthumbnailer" \
                        "linuxbrew:ffmpegthumbnailer" \
                        "mac:ffmpegthumbnailer" \
                        "debian-ubuntu:ffmpegthumbnailer"

register_system_package "vipsthumbnail" \
                        "alpine:vips-tools" \
                        "fedora:vips-tools" \
                        "linuxbrew:vips" \
                        "mac:vips" \
                        "debian-ubuntu:libvips-tools"

# --- Document & Archive Parsing ---
# Used to peek inside PDFs, archives, and formatted text files.
register_system_package "poppler" \
                        "alpine:poppler-utils" \
                        "fedora:poppler" \
                        "linuxbrew:poppler" \
                        "mac:poppler" \
                        "debian-ubuntu:poppler-utils"

register_system_package "unzip" \
                        "alpine:unzip" \
                        "fedora:unzip" \
                        "linuxbrew:unzip" \
                        "mac:unzip" \
                        "debian-ubuntu:unzip"

register_system_package "glow" \
                        "alpine:glow" \
                        "fedora:glow" \
                        "linuxbrew:glow" \
                        "mac:glow" \
                        "debian-ubuntu:glow"

register_system_package "pandoc" \
                        "alpine:pandoc" \
                        "fedora:pandoc" \
                        "linuxbrew:pandoc" \
                        "mac:pandoc" \
                        "debian-ubuntu:pandoc"

install_dirvish_utilities_bundle() {
  log_info "Starting Dirvish utilities setup..."
  install_system_packages "${DIRVISH_UTILITIES[@]}"
}

uninstall_dirvish_utilities_bundle() {
  log_skip "Dirvish utilities" "The packages used with Dirvish are system packages and will not be uninstalled automatically"
}

register_action "Install Dirvish utilities" "dirvish_utilities_bundle" "Utils"

is_installed_ripgrep() {
  is_system_package_installed "ripgrep"
}

register_system_package "ripgrep" \
                        "alpine:ripgrep" \
                        "fedora:ripgrep" \
                        "linuxbrew:ripgrep" \
                        "mac:ripgrep" \
                        "debian-ubuntu:ripgrep"

install_ripgrep() {
  log_info "Starting Ripgrep setup..."
  install_system_packages "ripgrep"
}

uninstall_ripgrep() {
  log_skip "Ripgrep" "Ripgrep is system package and will not be uninstalled automatically"
}

register_action "Install Ripgrep" "ripgrep" "Utils"

VTERM_BUILD_PACKAGES=(
  "libvterm" "cmake" "build-essential"
)

is_installed_vterm_build_bundle() {
  are_these_system_packages_installed "${VTERM_BUILD_PACKAGES[@]}"
}

register_system_package "libvterm" \
                        "alpine:libvterm-dev" \
                        "fedora:libvterm-devel" \
                        "linuxbrew:libvterm" \
                        "mac:libvterm" \
                        "debian-ubuntu:libvterm-dev"

register_system_package "cmake" \
                        "alpine:cmake" \
                        "fedora:cmake" \
                        "linuxbrew:cmake" \
                        "mac:cmake" \
                        "debian-ubuntu:cmake"

register_system_package "build-essential" \
                        "alpine:build-base" \
                        "fedora:gcc-c++" \
                        "linuxbrew:gcc" \
                        "mac:xcode" \
                        "debian-ubuntu:build-essential"

install_vterm_build_bundle() {
  log_info "Starting C++ Development environment setup..."
  install_system_packages "${VTERM_BUILD_PACKAGES[@]}"
}

uninstall_vterm_build_bundle() {
  log_skip "vterm build bundle" "The packages used for vterm builds are system packages and will not be uninstalled automatically"
}

register_action "Install vterm build bundle" "vterm_build_bundle" "Utils"

is_installed_semgrep() {
  command -v semgrep >/dev/null 2>&1
}

install_semgrep() {
  install_via_pipx "Semgrep" "semgrep"
}

uninstall_semgrep() {
  run_task "Uninstalling Semgrep" "pipx uninstall semgrep 2>/dev/null || true"
}

register_action "Install Semgrep" "semgrep" "standalone"

is_installed_copilot() {
  [ -f "$TOOLS_DIR/node_modules/.bin/copilot-language-server" ] || command -v copilot-language-server >/dev/null 2>&1
}

install_copilot() {
  install_nodejs_tools
}

uninstall_copilot() {
  uninstall_nodejs_tools
}

register_action "Install GitHub Copilot" "copilot" "node"

is_installed_prettier() {
  [ -f "$TOOLS_DIR/node_modules/.bin/typescript-language-server" ] || command -v typescript-language-server >/dev/null 2>&1
}

install_prettier() {
  install_nodejs_tools
}

uninstall_prettier() {
  uninstall_nodejs_tools
}

register_action "Install Prettier" "prettier" "node"

CPP_MIN_DEV_PACKAGES=(
  "gcc-c++" "gdb" "cmake" "make" "clang-tools-extra" "bear"
  "openssl-devel" "libxcrypt-devel" "ncurses-devel"
  "zlib-devel" "sqlite-devel" "readline-devel" "libffi-devel"
)

is_installed_cpp_dev_bundle() {
  are_these_system_packages_installed "${CPP_MIN_DEV_PACKAGES[@]}"
}

# Compiler & Build Tools
register_system_package "bear" \
                        "alpine:bear" \
                        "fedora:bear" \
                        "linuxbrew:bear" \
                        "mac:bear" \
                        "debian-ubuntu:bear"

register_system_package "clang-tools-extra" \
                        "alpine:clang-extra-tools" \
                        "fedora:clang-tools-extra" \
                        "linuxbrew:llvm" \
                        "mac:llvm" \
                        "debian-ubuntu:clangd"

register_system_package "cmake" \
                        "alpine:cmake" \
                        "fedora:cmake" \
                        "linuxbrew:cmake" \
                        "mac:cmake" \
                        "debian-ubuntu:cmake"

register_system_package "gcc-c++" \
                        "alpine:g++" \
                        "fedora:gcc-c++" \
                        "linuxbrew:gcc" \
                        "mac:gcc" \
                        "debian-ubuntu:g++"

# Note: gdb on Mac might require extra configuration for "signing"
# the binary to allow it to control other processes
register_system_package "gdb" \
                        "alpine:gdb" \
                        "fedora:gdb" \
                        "linuxbrew:gdb" \
                        "mac:gdb" \
                        "debian-ubuntu:gdb"

register_system_package "make" \
                        "alpine:make" \
                        "fedora:make" \
                        "linuxbrew:make" \
                        "mac:make" \
                        "debian-ubuntu:make"

# Libraries & Headers
register_system_package "libffi-devel" \
                        "alpine:libffi-dev" \
                        "fedora:libffi-devel" \
                        "linuxbrew:libffi" \
                        "mac:libffi" \
                        "debian-ubuntu:libffi-dev"

register_system_package "libxcrypt-devel" \
                        "alpine:libxcrypt-dev" \
                        "fedora:libxcrypt-devel" \
                        "linuxbrew:libxcrypt" \
                        "mac:libxcrypt" \
                        "debian-ubuntu:libxcrypt-dev"

register_system_package "ncurses-devel" \
                        "alpine:ncurses-dev" \
                        "fedora:ncurses-devel" \
                        "linuxbrew:ncurses" \
                        "mac:ncurses" \
                        "debian-ubuntu:libncurses-dev"

register_system_package "openssl-devel" \
                        "alpine:openssl-dev" \
                        "fedora:openssl-devel" \
                        "linuxbrew:openssl" \
                        "mac:openssl" \
                        "debian-ubuntu:libssl-dev"

register_system_package "readline-devel" \
                        "alpine:readline-dev" \
                        "fedora:readline-devel" \
                        "linuxbrew:readline" \
                        "mac:readline" \
                        "debian-ubuntu:libreadline-dev"

register_system_package "sqlite-devel" \
                        "alpine:sqlite-dev" \
                        "fedora:sqlite-devel" \
                        "linuxbrew:sqlite" \
                        "mac:sqlite" \
                        "debian-ubuntu:libsqlite3-dev"

register_system_package "zlib-devel" \
                        "alpine:zlib-dev" \
                        "fedora:zlib-devel" \
                        "linuxbrew:zlib" \
                        "mac:zlib" \
                        "debian-ubuntu:zlib1g-dev"

install_cpp_dev_bundle() {
  log_info "Starting C++ Development environment setup..."
  install_system_packages "${CPP_MIN_DEV_PACKAGES[@]}"
}

uninstall_cpp_dev_bundle() {
  log_skip "C++ dev bundle" "The packages used for C++ development are system packages and will not be uninstalled automatically"
}

register_action "Install C++ dev tools" "cpp-dev-bundle" "C++"

IS_SDKMAN_INITIALIZED=false

is_installed_sdkman() {
  if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    return 0
  fi

  return 1
}

initialize_sdkman() {
  if [[ "$IS_SDKMAN_INITIALIZED" == "false" ]]; then
    if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
      # shellcheck disable=SC1091
      [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh" > /dev/null 2>&1

      if command -v sdk >/dev/null 2>&1; then
        IS_SDKMAN_INITIALIZED=true
      fi
    else
      log_error "SDKMAN! initialization script not found."
      return 1
    fi
  fi
}

install_sdkman() {
  if ! is_installed_sdkman; then
    run_task "Installing SDKMAN" "curl -s 'https://get.sdkman.io' | bash"
  fi

  # Initialize will now be quiet
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
    local JDTLS_TMP_DIR
    JDTLS_TMP_DIR=$(mktemp -d)
    mkdir -p "$JDTLS_TARGET_DIR"
    run_task "Downloading JDTLS" "curl -L -o $JDTLS_TMP_DIR/jdtls.tar.gz https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_DATE}.tar.gz"
    run_task "Extracting JDTLS" "tar -xzf $JDTLS_TMP_DIR/jdtls.tar.gz -C $JDTLS_TARGET_DIR"

    rm -rf "$JDTLS_TMP_DIR"
  fi
}

uninstall_jdtls() {
  if is_installed_jdtls; then
    run_task "Removing existing JDTLS installation" "rm -Rf${VERBOSE:+v} $JDTLS_TARGET_DIR"
  fi
}

is_installed_java() {
  return 1 # SDKMAN! will skip already installed versions
}

install_java() {
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
    run_task "Java $v" "sdk install java $v > /dev/null 2>&1"
  done
}

uninstall_java() {
  uninstall_jdtls
  log_skip "Java SDKs (SDKMAN!)."
}

register_action "Install Java" "java" "jvm"

GOOGLE_JAVA_FORMAT_VERSION="1.25.0"
GOOGLE_JAVA_FORMAT_DIR="$HOME/.emacs.d/google-java-format"
GOOGLE_JAVA_FORMAT_BIN="$GOOGLE_JAVA_FORMAT_DIR/google-java-format"

is_installed_google_java_format() {
  [ -x "$GOOGLE_JAVA_FORMAT_BIN" ]
}

install_google_java_format() {
  if ! is_installed_google_java_format; then
    # Determine platform binary name.
    local arch
    arch="$(uname -m)"
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local binary_name

    case "${os}_${arch}" in
      linux_x86_64)  binary_name="google-java-format_linux-x86-64" ;;
      linux_aarch64) binary_name="google-java-format_linux-arm64" ;;
      darwin_arm64)  binary_name="google-java-format_darwin-arm64" ;;
      *)
        log_error "No pre-built google-java-format binary for ${os}_${arch}."
        log_error "Install manually: https://github.com/google/google-java-format/releases"
        return 1
        ;;
    esac

    mkdir -p "$GOOGLE_JAVA_FORMAT_DIR"

    local url="https://github.com/google/google-java-format/releases/download/v${GOOGLE_JAVA_FORMAT_VERSION}/${binary_name}"
    run_task "Downloading google-java-format v${GOOGLE_JAVA_FORMAT_VERSION}" \
             "curl -L -o '$GOOGLE_JAVA_FORMAT_BIN' '$url'"
    chmod +x "$GOOGLE_JAVA_FORMAT_BIN"
  fi
}

uninstall_google_java_format() {
  if is_installed_google_java_format; then
    run_task "Removing google-java-format" "rm -Rf${VERBOSE:+v} $GOOGLE_JAVA_FORMAT_DIR"
  fi
}

register_action "Install Google Java Format" "google-java-format" "jvm"

KLS_VERSION="1.3.13"
KLS_TARGET_DIR="$HOME/.emacs.d/lsp_language_servers/kotlin.ls"

is_installed_kls() {
  [ -f "$KLS_TARGET_DIR/bin/kotlin-language-server" ]
}

install_kls() {
  if ! is_installed_kls; then
    local KLS_TMP_DIR
    KLS_TMP_DIR=$(mktemp -d)

    rm -Rf "$KLS_TARGET_DIR" # Clean previous install
    mkdir -p "$KLS_TARGET_DIR"
    run_task "Downloading KLS" "curl -L https://github.com/fwcd/kotlin-language-server/releases/download/$KLS_VERSION/server.zip -o $KLS_TMP_DIR/kotlin-language-server.zip"
    run_task "Extracting KLS" "unzip -q $KLS_TMP_DIR/kotlin-language-server.zip -d $KLS_TMP_DIR && mv $KLS_TMP_DIR/server/* $KLS_TARGET_DIR/"

    rm -Rf "$KLS_TMP_DIR"
  fi
}

uninstall_kls() {
  if is_installed_kls; then
    run_task "Removing existing KLS installation" "rm -Rf${VERBOSE:+v} $KLS_TARGET_DIR"
  fi
}

is_installed_kotlin() {
  return 1 # SDKMAN! will skip already installed versions
}

install_kotlin() {
  install_kls
  install_sdkman

  KOTLIN_VERSIONS_TO_INSTALL=(
    "2.3.10"
  )

  for v in "${KOTLIN_VERSIONS_TO_INSTALL[@]}"; do
    run_task "Kotlin $v" "sdk install kotlin $v > /dev/null 2>&1"
  done
}

uninstall_kotlin() {
  uninstall_kls
  log_skip "Kotlin SDKs (SDKMAN!)"
}

register_action "Install Kotlin" "kotlin" "jvm"

is_installed_typescript_language_server() {
  [ -f "$TOOLS_DIR/node_modules/.bin/typescript-language-server" ] || command -v typescript-language-server >/dev/null 2>&1
}

install_typescript_language_server() {
  install_nodejs_tools
}

uninstall_typescript_language_server() {
  uninstall_nodejs_tools
}

register_action "Install TypeScript Language Server" "typescript-language-server" "node"

LSP_BASH_LANGUAGE_SERVER_PATH="$HOME/.emacs.d/.cache/lsp/npm/bash-language-server"

is_installed_bash_language_server() {
  [ -f "$TOOLS_DIR/node_modules/.bin/bash-language-server" ] || command -v bash-language-server >/dev/null 2>&1
}

install_bash_language_server() {
  install_nodejs_tools
  # Small hack for bash-language-server to work with lsp-mode: setting `lsp-bash-bash-language-server-path`
  # did not work as expected for unknown reasons.
  run_task "Linking Bash LS" "rm -Rf $LSP_BASH_LANGUAGE_SERVER_PATH && mkdir -p $LSP_BASH_LANGUAGE_SERVER_PATH/bin/ && ln -s $TOOLS_DIR/node_modules/.bin/bash-language-server $LSP_BASH_LANGUAGE_SERVER_PATH/bin/bash-language-server"
}

uninstall_bash_language_server() {
  uninstall_nodejs_tools
  run_task "Cleaning Bash LS cache" "rm -Rf $LSP_BASH_LANGUAGE_SERVER_PATH"
}

register_action "Install Bash Language Server" "bash-language-server" "node"

is_installed_shellcheck() {
  command -v shellcheck >/dev/null 2>&1
}

register_system_package "ShellCheck" \
                        "alpine:shellcheck" \
                        "fedora:shellcheck" \
                        "linuxbrew:shellcheck" \
                        "mac:shellcheck" \
                        "debian-ubuntu:shellcheck"

install_shellcheck() {
  install_system_packages "ShellCheck"
}

uninstall_shellcheck() {
  log_skip "ShellCheck" "ShellCheck is a system package and will not be uninstalled automatically"
}

register_action "Install ShellCheck" "shellcheck" "standalone"

is_installed_autotools_language_server() {
  command -v autotools-language-server >/dev/null 2>&1
}

install_autotools_language_server() {
  install_via_pipx "Autotools Language Server" "autotools-language-server"
}

uninstall_autotools_language_server() {
  run_task "Uninstalling Autotools LS" "pipx uninstall autotools-language-server 2>/dev/null || true"
}

register_action "Install Autotools Language Server" "autotools-language-server" "standalone"

# Update PlantUML version as needed:
PLANTUML_VERSION="1.2026.2"
PLANTUML_DIR="$HOME/.emacs.d/plantuml"

is_installed_plantuml() {
  [ -f "$HOME/.emacs.d/plantuml/plantuml.jar" ]
}

install_plantuml() {
  local PLANTUML_JAR="$PLANTUML_DIR/plantuml.jar"
  local PLANTUML_URL="https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

  if [ -f "$PLANTUML_JAR" ]; then
    log_skip "PlantUML" "EXISTS"
  else
    run_task "Downloading PlantUML" "mkdir -p $PLANTUML_DIR && curl -L $PLANTUML_URL -o $PLANTUML_JAR"
  fi
}

uninstall_plantuml() {
  run_task "Removing PlantUML" "rm -Rf $PLANTUML_DIR"
}

register_action "Install PlantUML" "plantuml" "standalone"

# --- Runtime Logic ---
sort_tools_by_group
build_menu_lists
if [[ "$VERBOSE" == "true" ]]; then
  print_system_packages_map
fi
display_installed_tools
run_menu
if [[ "$FORCE_REINSTALL" == "true" ]]; then
  execute_uninstallers
fi
execute_installers
