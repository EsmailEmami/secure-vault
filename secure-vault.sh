#!/bin/bash

set -euo pipefail

# Constants
DEFAULT_OUTPUT_DIR="${HOME}/secure-vault"
MAX_PASSWORD_ATTEMPTS=3
VERSION="1.2.0"

# Ensure 'age' is installed
if ! command -v age >/dev/null 2>&1; then
    echo -e "\033[1;31m[ERROR]\033[0m 'age' encryption tool is not installed."
    echo "Please install it using your package manager (e.g., 'apt install age' or 'brew install age')."
    exit 1
fi

# Create default directory if it doesn't exist
mkdir -p "$DEFAULT_OUTPUT_DIR" 2>/dev/null || {
    echo -e "\033[1;31m[ERROR]\033[0m Cannot create directory $DEFAULT_OUTPUT_DIR"
    exit 1
}

# Colorized output functions
info()    { echo -e "\033[1;36m[INFO]\033[0m $1"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
prompt()  { echo -e "\033[1;34m[PROMPT]\033[0m $1"; }

# Trap for cleanup and interruption
cleanup() {
    [ -n "${TMP_FILE:-}" ] && rm -f "$TMP_FILE" 2>/dev/null
    warn "Operation cancelled."
    exit 1
}
trap cleanup INT

print_banner() {
    clear
    echo -e "\n\033[1;35m🔒 Secure Vault v${VERSION} 🔒\033[0m"
    echo "-----------------------------------"
}

prompt_output_dir() {
    while true; do
        prompt "Enter output directory [default: ${DEFAULT_OUTPUT_DIR}]: "
        read -r OUT_DIR
        OUTPUT_DIR="${OUT_DIR:-$DEFAULT_OUTPUT_DIR}"
        if mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
            if [ -w "$OUTPUT_DIR" ]; then
                break
            else
                error "Directory $OUTPUT_DIR is not writable"
            fi
        else
            error "Cannot create directory $OUTPUT_DIR"
        fi
    done
}

prompt_unique_filename() {
    local suggested="vault-$(date +%Y%m%d_%H%M%S)"
    while true; do
        prompt "Enter filename (without .age extension) [default: ${suggested}]: "
        read -r BASE_NAME
        BASE_NAME="${BASE_NAME:-$suggested}"
        OUTPUT_FILE="$OUTPUT_DIR/${BASE_NAME}.age"
        if [[ "$BASE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            if [ -e "$OUTPUT_FILE" ]; then
                warn "File already exists: $OUTPUT_FILE"
                prompt "Overwrite existing file? (y/N): "
                read -r OVERWRITE
                [[ "$OVERWRITE" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        else
            warn "Invalid filename. Use letters, numbers, underscores, or hyphens only."
        fi
    done
}

encrypt_from_input() {
    print_banner
    info "Creating new encrypted content"
    prompt_output_dir
    prompt_unique_filename

    TMP_FILE=$(mktemp --suffix=".vault") || error "Cannot create temporary file"
    chmod 600 "$TMP_FILE"  # Secure permissions for temp file

    EDITOR_CMD="${EDITOR:-nano}"
    info "Opening editor ($EDITOR_CMD). Save and exit to encrypt..."
    if ! "$EDITOR_CMD" "$TMP_FILE"; then
        rm -f "$TMP_FILE"
        error "Editor failed to open"
    fi

    if [ ! -s "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
        warn "No content provided. Operation cancelled."
        return
    fi

    info "Encrypting content..."
    for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
        if age --encrypt --passphrase --armor -o "$OUTPUT_FILE" "$TMP_FILE" 2>/tmp/age-error.log; then
            rm -f "$TMP_FILE"
            success "Content encrypted and saved to: $OUTPUT_FILE"
            return
        else
            error_msg=$(cat /tmp/age-error.log)
            warn "Encryption failed (attempt $attempt/$MAX_PASSWORD_ATTEMPTS): $error_msg"
            [ $attempt -lt $MAX_PASSWORD_ATTEMPTS ] && info "Please try again..."
        fi
    done
    rm -f "$TMP_FILE"
    error "Encryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
}

encrypt_existing_file() {
    print_banner
    info "Encrypting an existing file"
    while true; do
        prompt "Enter full path to the file to encrypt: "
        read -r INPUT_FILE
        if [ -z "$INPUT_FILE" ]; then
            warn "File path cannot be empty"
        elif [ ! -f "$INPUT_FILE" ]; then
            warn "File not found: $INPUT_FILE"
        elif [ ! -r "$INPUT_FILE" ]; then
            warn "File is not readable: $INPUT_FILE"
        else
            break
        fi
    done

    prompt_output_dir
    prompt_unique_filename

    info "Encrypting file..."
    for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
        if age --encrypt --passphrase --armor -o "$OUTPUT_FILE" "$INPUT_FILE" 2>/tmp/age-error.log; then
            success "File encrypted and saved to: $OUTPUT_FILE"
            return
        else
            error_msg=$(cat /tmp/age-error.log)
            warn "Encryption failed (attempt $attempt/$MAX_PASSWORD_ATTEMPTS): $error_msg"
            [ $attempt -lt $MAX_PASSWORD_ATTEMPTS ] && info "Please try again..."
        fi
    done
    error "Encryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
}

decrypt_file() {
    print_banner
    info "Decrypting file"
    while true; do
        prompt "Enter path to .age file: "
        read -r ENC_FILE
        if [ -z "$ENC_FILE" ]; then
            warn "File path cannot be empty"
        elif [ ! -f "$ENC_FILE" ]; then
            warn "File not found: $ENC_FILE"
        elif [[ ! "$ENC_FILE" =~ \.age$ ]]; then
            warn "File must have .age extension"
        else
            break
        fi
    done

    prompt "Save decrypted content to a file? (y/N): "
    read -r SAVE_OPT
    if [[ "$SAVE_OPT" =~ ^[Yy]$ ]]; then
        while true; do
            prompt "Enter path to save decrypted file: "
            read -r DEC_FILE
            if [ -z "$DEC_FILE" ]; then
                warn "Output path cannot be empty"
            elif [ -e "$DEC_FILE" ]; then
                prompt "File exists. Overwrite? (y/N): "
                read -r OVER
                [[ "$OVER" =~ ^[Yy]$ ]] && break
            else
                break
            fi
        done

        for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
            if age --decrypt "$ENC_FILE" > "$DEC_FILE" 2>/tmp/age-error.log; then
                success "Decrypted and saved to: $DEC_FILE"
                return
            else
                error_msg=$(cat /tmp/age-error.log)
                if echo "$error_msg" | grep -q "incorrect passphrase"; then
                    warn "Wrong password (attempt $attempt/$MAX_PASSWORD_ATTEMPTS). Please try again..."
                else
                    error "Decryption failed: $error_msg"
                fi
            fi
        done
        error "Decryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
    else
        echo -e "\n--- Decrypted content ---"
        for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
            if age --decrypt "$ENC_FILE" 2>/tmp/age-error.log; then
                echo -e "\n------------------------"
                return
            else
                error_msg=$(cat /tmp/age-error.log)
                if echo "$error_msg" | grep -q "incorrect passphrase"; then
                    warn "Wrong password (attempt $attempt/$MAX_PASSWORD_ATTEMPTS). Please try again..."
                else
                    error "Decryption failed: $error_msg"
                fi
            fi
        done
        error "Decryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
    fi
}

list_vault_files() {
    print_banner
    prompt_output_dir
    info "Listing encrypted files in ${OUTPUT_DIR}:"
    if ! find "$OUTPUT_DIR" -type f -name "*.age" -exec basename {} \; | sort; then
        warn "No .age files found in ${OUTPUT_DIR}"
    fi
}

edit_encrypted_file() {
    print_banner
    info "Editing encrypted file"
    while true; do
        prompt "Enter path to .age file: "
        read -r input_file
        if [ -z "$input_file" ]; then
            warn "File path cannot be empty"
        elif [ ! -f "$input_file" ]; then
            warn "File not found: $input_file"
        elif [[ ! "$input_file" =~ \.age$ ]]; then
            warn "File must have .age extension"
        else
            break
        fi
    done

    TMP_FILE=$(mktemp --suffix=".vault") || error "Cannot create temporary file"
    chmod 600 "$TMP_FILE"

    for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
        info "Decrypting file (attempt $attempt/$MAX_PASSWORD_ATTEMPTS)..."
        if age --decrypt "$input_file" > "$TMP_FILE" 2>/tmp/age-error.log; then
            break
        else
            error_msg=$(cat /tmp/age-error.log)
            if echo "$error_msg" | grep -q "incorrect passphrase"; then
                warn "Wrong password. Please try again..."
            else
                rm -f "$TMP_FILE"
                error "Decryption failed: $error_msg"
            fi
            [ $attempt -eq $MAX_PASSWORD_ATTEMPTS ] && {
                rm -f "$TMP_FILE"
                error "Decryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
            }
        fi
    done

    cp "$TMP_FILE" "${TMP_FILE}.bak"  # Backup before editing
    EDITOR_CSUM=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)
    ${EDITOR:-nano} "$TMP_FILE"

    NEW_CSUM=$(sha256sum "$TMP_FILE" | cut -d' ' -f1)
    if [ "$EDITOR_CSUM" = "$NEW_CSUM" ]; then
        rm -f "$TMP_FILE" "${TMP_FILE}.bak"
        warn "No changes made to the file. Operation cancelled."
        return
    fi

    prompt "Confirm re-encryption with the same password? (y/N): "
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm -f "$TMP_FILE" "${TMP_FILE}.bak"
        warn "Operation cancelled."
        return
    fi

    info "Re-encrypting file..."
    for attempt in $(seq 1 $MAX_PASSWORD_ATTEMPTS); do
        if age --encrypt --passphrase --armor -o "$input_file" "$TMP_FILE" 2>/tmp/age-error.log; then
            rm -f "$TMP_FILE" "${TMP_FILE}.bak"
            success "File updated and encrypted: $input_file"
            return
        else
            error_msg=$(cat /tmp/age-error.log)
            warn "Encryption failed (attempt $attempt/$MAX_PASSWORD_ATTEMPTS): $error_msg"
            [ $attempt -lt $MAX_PASSWORD_ATTEMPTS ] && info "Please try again..."
        fi
    done
    mv "${TMP_FILE}.bak" "$TMP_FILE"  # Restore backup on failure
    error "Encryption failed after $MAX_PASSWORD_ATTEMPTS attempts"
}

main_menu() {
    while true; do
        print_banner
        echo "1) Create and encrypt new content"
        echo "2) Encrypt an existing file"
        echo "3) Decrypt a file"
        echo "4) List encrypted files"
        echo "5) Edit an encrypted file"
        echo "6) Exit"
        echo
        prompt "Choose an option [1-6]: "
        read -r CHOICE
        case $CHOICE in
            1) encrypt_from_input ;;
            2) encrypt_existing_file ;;
            3) decrypt_file ;;
            4) list_vault_files ;;
            5) edit_encrypted_file ;;
            6) success "Thank you for using Secure Vault!"; exit 0 ;;
            *) warn "Invalid option. Please choose 1-6." ;;
        esac
        echo
        prompt "Press ENTER to return to menu..."
        read -r
    done
}

main_menu
