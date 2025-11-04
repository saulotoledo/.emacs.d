#!/bin/bash

SKIP_JAVA=false
SKIP_KOTLIN=false
ENABLE_COPILOT=false

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

parse_args "$@"

if [ "$SKIP_JAVA" = "false" ] || [ "$SKIP_KOTLIN" = "false" ]; then
  initialize_sdkman
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

install_shellcheck() {
  echo -e "\033[1;32m\n[ Installing ShellCheck ]\033[0m"

  if ! command -v shellcheck >/dev/null 2>&1; then

    # 1. Check for Debian/Ubuntu (apt)
    if [ -f /etc/debian_version ] && command -v apt >/dev/null 2>&1; then
      echo "Using apt to install ShellCheck..."
      sudo apt update
      sudo apt install -y shellcheck

    # 2. Check for Fedora/RHEL (dnf)
    elif [ -f /etc/fedora-release ] || command -v dnf >/dev/null 2>&1; then
      echo "Using dnf to install ShellCheck (RHEL/Fedora)..."
      # dnf is generally available and doesn't require a preceding update like apt
      sudo dnf install -y ShellCheck

    # 3. Fallback/Manual install warning
    else
      echo -e "\033[1;33mWarning: Could not automatically install ShellCheck. Please install it manually using your OS package manager.\033[0m"
      echo "See: https://github.com/koalaman/shellcheck#installing"
    fi
  else
    echo "ShellCheck is already installed."
  fi
}

install_shellcheck
