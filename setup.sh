#!/bin/bash

SKIP_JAVA=false
SKIP_KOTLIN=false
ENABLE_COPILOT=false
SETUP_TOKENS=false

parse_args() {
  for arg in "$@"; do
    case $arg in
      --skip-java)
        SKIP_JAVA=true
        shift
        ;;
      --skip-kotlin)
        SKIP_KOTLIN=true
        shift
        ;;
      --enable-copilot)
        ENABLE_COPILOT=true
        shift
        ;;
      --setup-tokens)
        SETUP_TOKENS=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
}

initialize_sdkman() {
  if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    echo -e "\033[1;33m[ Initializing SDKMAN ]\033[0m"
    . "$HOME/.sdkman/bin/sdkman-init.sh"
    echo "SDKMAN initialized."
  else
    echo "SDKMAN not found in your environment."
  fi
}

setup_tokens() {
  AUTH_FILE="$HOME/.authinfo.gpg"
  TEMP_FILE=$(mktemp)
  chmod 600 "$TEMP_FILE"

  echo -e "\033[1;36m[ Setting up AI API Tokens ]\033[0m"
  echo "Files will be stored in $AUTH_FILE"

  # Decrypt existing file if it exists
  if [ -f "$AUTH_FILE" ]; then
    echo "Decrypting existing credentials..."
    # Try to decrypt. If it fails (e.g. bad passphrase), we abort to be safe
    gpg --quiet --decrypt "$AUTH_FILE" > "$TEMP_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
      echo -e "\033[1;31mError: Could not decrypt existing file. Aborting to prevent data loss.\033[0m"
      rm "$TEMP_FILE"
      exit 1
    fi
  else
    echo "Creating new credentials file..."
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
      echo -e "\033[1;32mUpdated $name key.\033[0m"
    else
      echo "Skipping $name (unchanged)."
    fi
  }

  # Prompt for keys
  update_key "api.github.com" "apikey" "GitHub Copilot"
  update_key "generativelanguage.googleapis.com" "apikey" "Google Gemini"
  update_key "api.groq.com" "apikey" "Groq"
  update_key "api.deepseek.com" "apikey" "DeepSeek"
  update_key "api.openai.com" "apikey" "OpenAI"

  # Encrypt back
  echo ""
  echo "Encrypting credentials..."
  # We encrypt for the current user
  RECIPIENT=$(whoami)
  gpg --yes --quiet --encrypt --recipient "$RECIPIENT" --output "$AUTH_FILE" "$TEMP_FILE"

  if [ $? -eq 0 ]; then
    echo -e "\033[1;32mSuccess! Credentials saved to $AUTH_FILE\033[0m"
  else
    echo -e "\033[1;31mError: Encryption failed.\033[0m"
  fi

  # Secure cleanup
  shred -u "$TEMP_FILE" 2>/dev/null || rm "$TEMP_FILE"
  exit 0
}

parse_args "$@"

if [ "$SKIP_JAVA" = "false" ] || [ "$SKIP_KOTLIN" = "false" ]; then
  initialize_sdkman
fi

if [ "$SETUP_TOKENS" = "true" ]; then
  setup_tokens
fi

if [ ! -f "./init.el" ]; then
  echo -e "\033[1;32m\n[ Bootstraping init.el ]\033[0m"
  cp "init-bootstrap.el" "init.el"
fi

# Set Node.js version requirement based on Copilot usage. Update minimum versions as needed.
if [ "$ENABLE_COPILOT" = "true" ]; then
  REQUIRED_NODE_VERSION="22.0.0"  # GitHub Copilot requires Node.js 22.x or later
  echo -e "\033[1;33m[ Copilot enabled - Node.js 22.0.0+ required ]\033[0m"
else
  REQUIRED_NODE_VERSION="20.19.2"  # Standard requirement without Copilot.
  echo -e "\033[1;33m[ Standard setup - Node.js 20.19.2+ required ]\033[0m"
fi

check_node_version() {
  echo -e "\033[1;32m[ Checking Node.js Version ]\033[0m"

  if ! command -v node >/dev/null 2>&1; then
    echo -e "\033[1;31mError: Node.js is not installed. Please install it before running this script.\033[0m"
    exit 1
  fi

  CURRENT_NODE_VERSION=$(node -v | sed 's/v//')

  # Version comparison logic: checks if current version is less than required version
  if [ ! "$(printf '%s\n' "$REQUIRED_NODE_VERSION" "$CURRENT_NODE_VERSION" | sort -V | head -n1)" = "$REQUIRED_NODE_VERSION" ]; then
    echo -e "\033[1;31mError: You have Node.js version $CURRENT_NODE_VERSION, but we require at least version $REQUIRED_NODE_VERSION to proceed.\033[0m"
    echo "Please update Node.js before proceeding."
    exit 1
  fi

  echo -e "\033[1;32mNode.js $CURRENT_NODE_VERSION meets the requirement ($REQUIRED_NODE_VERSION).\033[0m"
}

install_nodejs_tools() {
  echo -e "\033[1;32m\n[ Installing Node.js tools used by Emacs packages ]\033[0m"

  local TOOLS_DIR="$HOME/.emacs.d/nodejs_tools"

  if [ ! -d "$TOOLS_DIR" ]; then
    echo "Error: Directory $TOOLS_DIR not found. Skipping npm install."
    return 1
  fi

  cd "$TOOLS_DIR" || exit 1
  rm -Rf node_modules
  npm install

  # Small hack for bash-language-server to work with lsp-mode
  echo "Applying bash-language-server symlink hack..."
  rm -Rf "$HOME/.emacs.d/.cache/lsp/npm/bash-language-server/"
  mkdir -p "$HOME/.emacs.d/.cache/lsp/npm/bash-language-server/bin/"
  ln -s "$TOOLS_DIR/node_modules/.bin/bash-language-server" "$HOME/.emacs.d/.cache/lsp/npm/bash-language-server/bin/bash-language-server"
}

check_node_version
install_nodejs_tools

# Download specific version of JDTLS. Update version/date as needed:
JDTLS_VERSION="1.51.0"
JDTLS_DATE="202510022025"

install_jdtls() {
  echo -e "\033[1;32m\n[ Installing Eclipse JDT Language Server (jdtls) ]\033[0m"

  local JDTLS_TMP_DIR
  JDTLS_TMP_DIR=$(mktemp -d)

  # Change it if you prefer another directory for the jdtls:
  local JDTLS_TARGET_DIR="$HOME/.emacs.d/lsp_language_servers/eclipse.jdt.ls"
  mkdir -p "$JDTLS_TARGET_DIR"

  echo "Downloading jdt-language-server-$JDTLS_VERSION-$JDTLS_DATE.tar.gz..."

  cd "$JDTLS_TMP_DIR" || exit 1

  # Download and extract
  curl -L -O "https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_DATE}.tar.gz"
  tar -xzf "jdt-language-server-${JDTLS_VERSION}-${JDTLS_DATE}.tar.gz"

  # Copy to final location
  cp -r * "$JDTLS_TARGET_DIR/"

  # Clean up temp files
  rm -rf "$JDTLS_TMP_DIR"

  echo -e "\033[1;32mEclipse JDT Language Server installed to $JDTLS_TARGET_DIR\033[0m"
}

if ! "$SKIP_JAVA"; then
  install_jdtls
else
  echo -e "\033[1;33m\n[ Skipping Eclipse JDT Language Server (jdtls) as requested ]\033[0m"
fi

# Update the version for Kotlin below as needed:
KOTLIN_VERSION="2.2.21"
KOTLIN_LS_VERSION="1.3.13"

install_kls() {
  local KLS_TMP_DIR
  KLS_TMP_DIR=$(mktemp -d)
  local KLS_TARGET_DIR="$HOME/.emacs.d/lsp_language_servers/kotlin.ls"

  echo "Downloading prebuilt Kotlin Language Server (KLS)..."
  curl -L "https://github.com/fwcd/kotlin-language-server/releases/download/$KOTLIN_LS_VERSION/server.zip" -o "$KLS_TMP_DIR/kotlin-language-server.zip"

  echo "Extracting Kotlin Language Server..."
  rm -Rf "$KLS_TARGET_DIR" # Clean previous install
  mkdir -p "$KLS_TARGET_DIR"
  unzip -q "$KLS_TMP_DIR/kotlin-language-server.zip" -d "$KLS_TMP_DIR"
  mv "$KLS_TMP_DIR/server"/* "$KLS_TARGET_DIR/"
  rm -Rf "$KLS_TMP_DIR"

  echo -e "\033[1;32mKotlin Language Server installed to $KLS_TARGET_DIR\033[0m"
}

install_kotlin_sdkman() {
  echo -e "\033[1;32m\n[ Installing Kotlin Language Server (KLS) via SDKMAN ]\033[0m"

  sdk install kotlin "$KOTLIN_VERSION"

  local KOTLIN_HOME
  KOTLIN_HOME=$(sdk home kotlin "$KOTLIN_VERSION" 2>/dev/null)

  if [ -n "$KOTLIN_HOME" ]; then
    echo "Kotlin installed in $KOTLIN_HOME"
    install_kls
  else
    echo -e "\033[1;33mWarning: Could not determine Kotlin installation path. Skipping Kotlin Language Server installation.\033[0m"
  fi
}

install_kotlin_manual() {
  echo -e "\033[1;32m\n[ Installing Kotlin Language Server (KLS) Manually ]\033[0m"
  echo "SDKMAN not found. Installing Kotlin compiler from official sources..."

  local KOTLIN_DIR="$HOME/.kotlin"
  rm -Rfv "$KOTLIN_DIR" # Clean previous install
  mkdir -p "$KOTLIN_DIR"

  echo "Downloading Kotlin $KOTLIN_VERSION..."
  curl -L "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VERSION}/kotlin-compiler-${KOTLIN_VERSION}.zip" -o /tmp/kotlin.zip
  unzip -q /tmp/kotlin.zip -d "$KOTLIN_DIR"
  rm /tmp/kotlin.zip

  echo "Kotlin compiler installed to $KOTLIN_DIR/kotlinc"
  echo "Note: Add $KOTLIN_DIR/kotlinc/bin to your PATH manually."

  # Install Kotlin Language Server
  install_kls
}

if ! "$SKIP_KOTLIN"; then
  if command -v sdk >/dev/null 2>&1; then
    install_kotlin_sdkman
  else
    install_kotlin_manual
  fi
else
  echo -e "\033[1;33m\n[ Skipping Kotlin Language Server (KLS) as requested ]\033[0m"
fi

install_required_tools() {
  echo -e "\033[1;32m\n[ Checking System Dependencies ]\033[0m"

  local system_tools=("shellcheck" "pipx")
  local missing_system=()

  # 1. Identify missing system tools
  for tool in "${system_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_system+=("$tool")
    fi
  done

  # 2. Batch install system tools
  if [ ${#missing_system[@]} -gt 0 ]; then
    echo "Installing missing system packages: ${missing_system[*]}"
    if [ -f /etc/debian_version ]; then
      sudo apt update && sudo apt install -y "${missing_system[@]}"
    elif [ -f /etc/fedora-release ] || command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "${missing_system[@]}"
    fi
    # Refresh PATH to ensure new tools are found
    export PATH="$PATH:$HOME/.local/bin"
  fi

  # 3. Install pipx-managed tools (Semgrep)
  echo -e "\033[1;32m\n[ Checking Isolated Dependencies (pipx) ]\033[0m"
  if ! command -v semgrep >/dev/null 2>&1; then
    echo "Installing semgrep via pipx..."
    # Ensure pipx path is registered
    pipx ensurepath >/dev/null 2>&1
    pipx install semgrep
  else
    echo "Semgrep is already installed via pipx."
  fi
}

install_required_tools

# Update PlantUML version as needed:
PLANTUML_VERSION="1.2025.10"

install_plantuml() {
  echo -e "\033[1;32m\n[ Installing PlantUML ]\033[0m"

  local PLANTUML_DIR="$HOME/.emacs.d/plantuml"
  local PLANTUML_JAR="$PLANTUML_DIR/plantuml.jar"
  local PLANTUML_URL="https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

  if [ -f "$PLANTUML_JAR" ]; then
    echo "PlantUML is already installed at $PLANTUML_JAR"
  else
    echo "Downloading PlantUML..."
    mkdir -p "$PLANTUML_DIR"
    curl -L "$PLANTUML_URL" -o "$PLANTUML_JAR"
    echo -e "\033[1;32mPlantUML installed to $PLANTUML_JAR\033[0m"
  fi
}

install_plantuml
