#!/bin/bash

set -euo pipefail

DEFAULT_OUTPUT_DIR="$HOME/vault"
mkdir -p "$DEFAULT_OUTPUT_DIR"

info()    { echo -e "\033[1;36m[INFO]\033[0m $1"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }

trap 'echo; warn "Operation cancelled."; exit 1' INT

print_banner() {
  echo -e "\n\033[1;35mSecure Vault 🛡️\033[0m"
  echo "------------------------------"
}

prompt_output_dir() {
  read -rp "Enter output directory [${DEFAULT_OUTPUT_DIR}]: " OUT_DIR
  OUTPUT_DIR="${OUT_DIR:-$DEFAULT_OUTPUT_DIR}"
  mkdir -p "$OUTPUT_DIR"
}

prompt_unique_filename() {
  local suggested="vault-$(date +%Y%m%d_%H%M%S)"
  while true; do
    read -rp "Enter filename (without extension) [${suggested}]: " BASE_NAME
    BASE_NAME="${BASE_NAME:-$suggested}"
    OUTPUT_FILE="$OUTPUT_DIR/${BASE_NAME}.age"
    if [ -e "$OUTPUT_FILE" ]; then
      warn "File already exists: $OUTPUT_FILE"
    else
      break
    fi
  done
}

encrypt_from_input() {
  info "Encrypting new input"
  prompt_output_dir
  prompt_unique_filename

  TMP_FILE=$(mktemp --suffix=".vault")
  EDITOR_CMD="${EDITOR:-nano}"
  info "Opening editor ($EDITOR_CMD)..."
  "$EDITOR_CMD" "$TMP_FILE"

  if [ ! -s "$TMP_FILE" ]; then
    warn "No content provided. Aborting."
    rm -f "$TMP_FILE"
    return
  fi

  info "You will be prompted for a password"
  age --encrypt --passphrase --armor -o "$OUTPUT_FILE" "$TMP_FILE"
  rm -f "$TMP_FILE"
  success "Encrypted and saved to: $OUTPUT_FILE"
}

encrypt_existing_file() {
  info "Encrypting an existing file"
  read -rp "Enter full path to file: " INPUT_FILE
  if [ ! -f "$INPUT_FILE" ]; then
    error "File not found: $INPUT_FILE"
    return
  fi

  prompt_output_dir
  prompt_unique_filename

  info "You will be prompted for a password"
  age --encrypt --passphrase --armor -o "$OUTPUT_FILE" "$INPUT_FILE"
  success "Encrypted and saved to: $OUTPUT_FILE"
}

decrypt_file() {
  info "Decrypting file"
  read -rp "Enter path to .age file: " ENC_FILE
  if [ ! -f "$ENC_FILE" ]; then
    error "File not found: $ENC_FILE"
    return
  fi

  read -rp "Save decrypted content to file? (y/N): " SAVE_OPT
  if [[ "$SAVE_OPT" =~ ^[Yy]$ ]]; then
    read -rp "Enter path to save decrypted file: " DEC_FILE
    if [ -e "$DEC_FILE" ]; then
      read -rp "File exists. Overwrite? (y/N): " OVER
      [[ ! "$OVER" =~ ^[Yy]$ ]] && { warn "Canceled."; return; }
    fi

    while true; do
      if age --decrypt "$ENC_FILE" > "$DEC_FILE" 2>/tmp/age-error.log; then
        success "Decrypted and saved to: $DEC_FILE"
        break
      else
        ERR_MSG=$(cat /tmp/age-error.log)
        if echo "$ERR_MSG" | grep -q "incorrect passphrase"; then
          error "Wrong password. Please try again or press Ctrl+C to cancel."
        else
          error "Decryption failed: $ERR_MSG"
          break
        fi
      fi
    done
  else
    echo -e "\n--- Decrypted content ---"
    while true; do
      if age --decrypt "$ENC_FILE" 2>/tmp/age-error.log; then
        echo -e "\n-------------------------"
        break
      else
        ERR_MSG=$(cat /tmp/age-error.log)
        if echo "$ERR_MSG" | grep -q "incorrect passphrase"; then
          error "Wrong password. Please try again or press Ctrl+C to cancel."
        else
          error "Decryption failed: $ERR_MSG"
          break
        fi
      fi
    done
  fi
}


list_vault_files() {
  prompt_output_dir
  echo -e "\n\033[1;34mEncrypted files in ${OUTPUT_DIR}:\033[0m"
  find "$OUTPUT_DIR" -type f -name "*.age" -exec basename {} \;
}

main_menu() {
  while true; do
    print_banner
    echo "1) Encrypt new input"
    echo "2) Encrypt existing file"
    echo "3) Decrypt file"
    echo "4) List vault files"
    echo "5) Exit"
    echo

    read -rp "Choose an option [1-5]: " CHOICE
    echo
    case $CHOICE in
      1) encrypt_from_input ;;
      2) encrypt_existing_file ;;
      3) decrypt_file ;;
      4) list_vault_files ;;
      5) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid option." ;;
    esac
    echo
    read -rp "Press ENTER to return to menu..."
    clear
  done
}

main_menu

