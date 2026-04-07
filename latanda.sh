#!/bin/bash
# ============================================
# La Tanda Chain - Interactive Node Manager
# Version: 1.1 (Security Hotfix)
# Chain ID: latanda-testnet-1
# Token: LTD (denom: ultd)
# ============================================

set -euo pipefail

# ============================================
# Global Environment PATH
# ============================================
export PATH="/usr/local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

# ============================================
# Defaults
# ============================================
CHAIN_ID="latanda-testnet-1"
HOME_DIR="${HOME}/.latanda"
DEFAULT_FEES="500ultd"
SOURCE_TARBALL="/tmp/latanda-chain-source.tar.gz"
GO_TARBALL="/tmp/go.tar.gz"
GO_SHA256="cb2396bae64183cdccce6c8e145b44f26b4a8c5e5c3ddc56b79f5bab60f41f4e"
# Set this to expected SHA256 to enforce source integrity verification.
SOURCE_SHA256="ba73d41a8f5ba146e90dc8af8fd60fdd3279fdec6f9fdbb026942c19751143dc"
LATMAN_UPDATE_URL="https://raw.githubusercontent.com/skyhazee/La-Tanda-Chain-Testnet/main/latanda.sh"

# ============================================
# Theme & Colors 
# ============================================
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================
# Dashboard Banner
# ============================================
function print_logo() {
    clear
    echo -e "${CYAN}"
    echo "  _          _____              _       "
    echo " | |    __ _|_   _|_ _ _ _  __| |__ _  "
    echo " | |__ / _\` | | |/ _\` | ' \\/ _\` / _\` | "
    echo " |____|\__,_| |_|\__,_|_||_\__,_\__,_| "
    echo "                                        "
    echo "  Chain Node Manager - latanda-testnet-1 "
    echo -e "${NC}"
}

# ============================================
# Transaction Helper (Hides JSON, Shows UI)
# ============================================
function broadcast_tx() {
    local desc="$1"
    shift
    echo -e "${CYAN}Broadcasting transaction: ${desc}${NC}"

    # Execute command using argument array (no eval) and capture JSON output.
    local output
    output=$("$@" -y --output json 2>&1 || true)

    if echo "$output" | jq -e . &>/dev/null; then
        local code
        local txhash
        local raw_log
        code=$(echo "$output" | jq -r '(.code // 0) | tostring')
        txhash=$(echo "$output" | jq -r '.txhash // empty')
        raw_log=$(echo "$output" | jq -r '.raw_log // empty')

        if [[ "$code" == "0" ]]; then
            echo -e "\n  ${GREEN}[OK] Transaction successful.${NC}"
            [[ -n "$txhash" ]] && echo -e "  TX Hash: ${CYAN}$txhash${NC}"
            echo -e "  (You can verify this hash on the explorer)"
            echo ""
            return 0
        else
            echo -e "\n  ${RED}[FAIL] Transaction failed.${NC}"
            echo -e "  Error Code: $code"
            [[ -n "$raw_log" ]] && echo -e "  Reason: $raw_log"
            echo ""
            return 1
        fi
    else
        echo -e "${RED}[FAIL] Command execution failed before broadcast.${NC}"
        echo "$output" | head -n 8
        echo ""
        return 1
    fi
}
# ============================================
# Binary Checker
# ============================================
function check_binary() {
    if ! command -v latandad &> /dev/null; then
        echo -e "\n${RED}Error: 'latandad' binary is NOT installed on this machine!${NC}"
        echo -e "You must install the node first before using this feature."
        echo -e "Please select ${YELLOW}Option 1 (Install Node & Run)${NC} from the main menu."
        echo ""
        read -p "Press Enter to return..."
        return 1
    fi
    return 0
}

function verify_checksum() {
    local file="$1"
    local expected="$2"
    if [[ -z "$expected" ]]; then
        echo -e "${YELLOW}[!] SOURCE_SHA256 is empty, checksum verification skipped.${NC}"
        return 0
    fi
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        echo -e "${RED}Checksum mismatch for $file${NC}"
        echo -e "Expected: $expected"
        echo -e "Actual  : $actual"
        return 1
    fi
    return 0
}

function extract_script_version() {
    local file="$1"
    grep -m1 '^# Version:' "$file" 2>/dev/null | sed 's/^# Version:[[:space:]]*//' || true
}

function file_sha256() {
    local file="$1"
    [[ -f "$file" ]] || { echo ""; return 0; }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}' || true
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}' || true
    else
        echo ""
    fi
}

function self_update() {
    print_logo
    echo -e "${YELLOW}--- Latman Self Update ---${NC}"
    echo ""

    local running_script target_script tmp_script target_dir target_tmp
    local local_hash remote_hash local_version remote_version

    running_script="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    if command -v latman >/dev/null 2>&1; then
        target_script="$(readlink -f "$(command -v latman)" 2>/dev/null || command -v latman)"
    else
        target_script="$running_script"
    fi

    tmp_script="$(mktemp /tmp/latman_update_XXXXXX.sh)"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$LATMAN_UPDATE_URL" -o "$tmp_script"; then
            rm -f "$tmp_script"
            echo -e "${RED}Failed to fetch update from GitHub.${NC}"
            read -p "Press Enter to return..."
            return
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "$LATMAN_UPDATE_URL" -O "$tmp_script"; then
            rm -f "$tmp_script"
            echo -e "${RED}Failed to fetch update from GitHub.${NC}"
            read -p "Press Enter to return..."
            return
        fi
    else
        rm -f "$tmp_script"
        echo -e "${RED}curl/wget not found. Cannot check updates.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if ! bash -n "$tmp_script" >/dev/null 2>&1; then
        rm -f "$tmp_script"
        echo -e "${RED}Downloaded update is invalid (bash syntax check failed).${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if [[ -f "$target_script" ]]; then
        local_hash="$(file_sha256 "$target_script")"
    else
        local_hash=""
    fi
    remote_hash="$(file_sha256 "$tmp_script")"
    local_version="$(extract_script_version "$target_script")"
    remote_version="$(extract_script_version "$tmp_script")"

    if [[ -n "$local_hash" && -n "$remote_hash" && "$local_hash" == "$remote_hash" ]]; then
        echo -e "${GREEN}2. latest version${NC}"
        [[ -n "$local_version" ]] && echo -e "Current version: ${CYAN}$local_version${NC}"
        rm -f "$tmp_script"
        read -p "Press Enter to return..."
        return
    fi

    echo -e "${YELLOW}1. update available${NC}"
    [[ -n "$local_version" ]] && echo -e "Current version: ${CYAN}${local_version}${NC}"
    [[ -n "$remote_version" ]] && echo -e "Latest version : ${GREEN}${remote_version}${NC}"
    echo -e "${CYAN}Applying update to: ${target_script}${NC}"

    chmod +x "$tmp_script"
    target_dir="$(dirname "$target_script")"
    target_tmp="${target_dir}/.latman_update_$$.sh"

    # Use atomic replace (mv) to avoid corrupting a script while it's running.
    if [[ -w "$target_dir" ]]; then
        if ! cp "$tmp_script" "$target_tmp"; then
            rm -f "$tmp_script"
            echo -e "${RED}Update failed: cannot stage update file in ${target_dir}.${NC}"
            read -p "Press Enter to return..."
            return
        fi
        chmod +x "$target_tmp" >/dev/null 2>&1 || true
        if ! mv -f "$target_tmp" "$target_script"; then
            rm -f "$tmp_script" "$target_tmp"
            echo -e "${RED}Update failed: cannot replace ${target_script}.${NC}"
            read -p "Press Enter to return..."
            return
        fi
    else
        if ! sudo cp "$tmp_script" "$target_tmp"; then
            rm -f "$tmp_script"
            echo -e "${RED}Update failed: no permission to write ${target_dir}.${NC}"
            echo -e "${YELLOW}Try: sudo latman update${NC}"
            read -p "Press Enter to return..."
            return
        fi
        sudo chmod +x "$target_tmp" >/dev/null 2>&1 || true
        if ! sudo mv -f "$target_tmp" "$target_script"; then
            rm -f "$tmp_script"
            sudo rm -f "$target_tmp" >/dev/null 2>&1 || true
            echo -e "${RED}Update failed: cannot replace ${target_script}.${NC}"
            echo -e "${YELLOW}Try: sudo latman update${NC}"
            read -p "Press Enter to return..."
            return
        fi
    fi

    rm -f "$tmp_script"
    echo -e "${GREEN}Update completed successfully.${NC}"
    echo -e "${CYAN}Node process is not restarted. Running node remains unaffected.${NC}"
    read -p "Press Enter to return..."
}

function validate_wallet_name() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]
}

function validate_proposal_id() {
    local value="$1"
    [[ "$value" =~ ^[0-9]{1,8}$ ]]
}

function validate_vote() {
    local value="$1"
    [[ "$value" == "yes" || "$value" == "no" || "$value" == "abstain" || "$value" == "no_with_veto" ]]
}

function validate_deposit() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+ultd$ ]]
}

# ============================================
# Option 1: Install Node
# ============================================
function install_node() {
    print_logo
    echo -e "${YELLOW}>> Starting Installation & Setup${NC}"
    echo ""

    echo -e "${YELLOW}[1/7] Checking system requirements...${NC}"
    if [[ "$(uname)" != "Linux" ]]; then
        echo -e "${RED}Error: This script requires Linux${NC}"
        read -p "Press Enter to return..." 
        return
    fi
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 3500 ]]; then
        echo -e "${RED}Error: Minimum 4GB RAM required.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo -e "${YELLOW}[2/7] Installing system dependencies & PM2...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git curl wget jq ufw > /dev/null 2>&1
    
    # Auto-install NPM and PM2 if not present
    if ! command -v pm2 &> /dev/null; then
        echo "Installing PM2 for background process management..."
        sudo apt-get install -y -qq npm > /dev/null 2>&1
        sudo npm install -g pm2 > /dev/null 2>&1
    fi

    echo -e "${YELLOW}[3/7] Installing Go 1.24.1...${NC}"
    if command -v go &> /dev/null && [[ "$(go version)" == *"go1.24"* ]]; then
        echo -e "${GREEN}Go already installed: $(go version)${NC}"
    else
        wget -q https://go.dev/dl/go1.24.1.linux-amd64.tar.gz -O "$GO_TARBALL"
        verify_checksum "$GO_TARBALL" "$GO_SHA256" || {
            read -p "Press Enter to return..."
            return
        }
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "$GO_TARBALL"
        rm "$GO_TARBALL"
        if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
        fi
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    fi

    echo -e "${YELLOW}[4/7] Building latandad binary...${NC}"
    BUILD_DIR="/tmp/latanda-build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    rm -f "$SOURCE_TARBALL"
    if wget -q https://latanda.online/chain/latanda-chain-source.tar.gz -O "$SOURCE_TARBALL"; then
        verify_checksum "$SOURCE_TARBALL" "$SOURCE_SHA256" || {
            read -p "Press Enter to return..."
            return
        }
        tar -xzf "$SOURCE_TARBALL" -C "$BUILD_DIR"
        cd "$BUILD_DIR"
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        go mod tidy 2>&1 | tail -3
        go build -o ./build_latandad ./cmd/latandad
        sudo mv ./build_latandad /usr/local/bin/latandad
        sudo chmod +x /usr/local/bin/latandad
    else
        echo -e "${RED}Error: Source tarball not found or network error.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    echo -e "${GREEN}latandad installed: $(latandad version 2>&1 || echo 'built')${NC}"

    echo -e "${YELLOW}[5/7] Initializing node...${NC}"
    read -p "Enter your node name (moniker): " MONIKER
    if [[ -z "$MONIKER" ]]; then
        MONIKER="latanda-node-$(hostname -s)"
    fi
    # Avoid failing if node already mapped
    latandad init "$MONIKER" --chain-id "$CHAIN_ID" --default-denom ultd --home "$HOME_DIR" > /dev/null 2>&1 || true

    echo "Downloading genesis file..."
    wget -q https://latanda.online/chain/genesis.json -O "$HOME_DIR/config/genesis.json"
    
    echo -e "${YELLOW}[6/7] Configuring node...${NC}"
    CONFIG_DIR="$HOME_DIR/config"
    PEERS="483a8110c3cd93c8dd3801d935151e98656f5b67@168.231.67.201:26656"
    sed -i "s|persistent_peers = \".*\"|persistent_peers = \"$PEERS\"|" "$CONFIG_DIR/config.toml"
    sed -i "s|seeds = \".*\"|seeds = \"$PEERS\"|" "$CONFIG_DIR/config.toml"
    sed -i "s|minimum-gas-prices = \".*\"|minimum-gas-prices = \"0.001ultd\"|" "$CONFIG_DIR/app.toml"
    # Keep RPC bound to localhost by default.
    sed -i 's|laddr = "tcp://0.0.0.0:26657"|laddr = "tcp://127.0.0.1:26657"|' "$CONFIG_DIR/config.toml"

    echo -e "${YELLOW}[7/7] Configuring firewall and starting node...${NC}"
    sudo ufw allow 26656/tcp > /dev/null 2>&1

    # Restarting via pm2 if running
    pm2 delete latanda-chain >/dev/null 2>&1 || true
    pm2 start latandad --name latanda-chain -- start --home "$HOME_DIR"
    pm2 save >/dev/null 2>&1

    echo ""
    echo -e "${GREEN}Installation Complete! Your node is running in the background.${NC}"
    echo -e "Node ID:  $(latandad comet show-node-id --home "$HOME_DIR" 2>/dev/null || latandad tendermint show-node-id --home "$HOME_DIR" 2>/dev/null)"
    echo -e "Moniker:  $MONIKER"
    echo ""
    read -p "Press Enter to return to menu..."
}

# ============================================
# Option 2: Check Status
# ============================================
function check_status() {
    check_binary || return
    print_logo
    echo -e "${CYAN}--- Node Sync Status ---${NC}"
    if ! command -v pm2 &> /dev/null || ! pm2 list | grep -q "latanda-chain"; then
        echo -e "${RED}Node is not running via PM2. Did you install it properly?${NC}"
    else
        # Allow jq some time if start up is slow
        catch_up=$(latandad status --home "$HOME_DIR" 2>&1 | jq -r '.sync_info.catching_up' || echo "true")
        block=$(latandad status --home "$HOME_DIR" 2>&1 | jq -r '.sync_info.latest_block_height' || echo "-")
        echo -e "Latest Validated Block:  ${GREEN}$block${NC}"
        
        if [[ "$catch_up" == "false" ]]; then
            echo -e "Sync Status (Catching Up): ${GREEN}False (Fully Synced && Ready for Validator)${NC}"
        else
            echo -e "Sync Status (Catching Up): ${YELLOW}True (Still syncing...)${NC}"
        fi
    fi
    echo ""
    read -p "Press Enter to return..." 
}

# ============================================
# Option 3: Wallet Management
# ============================================
function manage_wallet() {
    check_binary || return
    while true; do
        print_logo
        echo -e "${YELLOW}--- Wallet Management ---${NC}"
        echo "1. Create New Wallet"
        echo "2. Recover Wallet (from mnemonic seed)"
        echo "3. List Saved Wallets"
        echo "4. Check Wallet Balance"
        echo "0. Back to Main Menu"
        echo ""
        read -p "Select action: " opt
        case $opt in
            1)
                echo ""
                read -p "Enter new wallet name: " wname
                if ! validate_wallet_name "$wname"; then
                    echo -e "${RED}Invalid wallet name. Use letters, numbers, _ or - only.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                latandad keys add "$wname" --keyring-backend test --home "$HOME_DIR"
                echo -e "${RED}IMPORTANT: Save the 24 words mnemonic phrase above securely!${NC}"
                read -p "Press Enter once you have saved it..."
                ;;
            2)
                echo ""
                read -p "Enter recovery wallet name: " wname
                if ! validate_wallet_name "$wname"; then
                    echo -e "${RED}Invalid wallet name. Use letters, numbers, _ or - only.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                latandad keys add "$wname" --recover --keyring-backend test --home "$HOME_DIR"
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo -e "${CYAN}Available wallets on this machine:${NC}"
                latandad keys list --keyring-backend test --home "$HOME_DIR"
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                echo "1. Enter wallet address manually"
                echo "2. Select from saved wallets"
                read -p "Select method [1-2]: " balopt

                waddr=""
                case "$balopt" in
                    1)
                        read -p "Enter wallet address (starts with ltd1...): " waddr
                        ;;
                    2)
                        wallet_json=$(latandad keys list --keyring-backend test --home "$HOME_DIR" --output json 2>/dev/null || echo '[]')
                        if ! echo "$wallet_json" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
                            echo -e "${RED}No saved wallets found.${NC}"
                            read -p "Press Enter to continue..."
                            continue
                        fi
                        echo -e "${CYAN}Saved wallets:${NC}"
                        i=1
                        while IFS=$'\t' read -r n a; do
                            echo "  $i) $n - $a"
                            i=$((i+1))
                        done < <(echo "$wallet_json" | jq -r '.[] | [.name, .address] | @tsv' 2>/dev/null)
                        read -p "Select wallet number: " pick
                        if [[ ! "$pick" =~ ^[0-9]+$ ]]; then
                            echo -e "${RED}Invalid selection.${NC}"
                            read -p "Press Enter to continue..."
                            continue
                        fi
                        waddr=$(echo "$wallet_json" | jq -r --argjson idx "$((pick-1))" '.[$idx].address // empty' 2>/dev/null || true)
                        wname=$(echo "$wallet_json" | jq -r --argjson idx "$((pick-1))" '.[$idx].name // empty' 2>/dev/null || true)
                        if [[ -z "$waddr" ]]; then
                            echo -e "${RED}Invalid selection.${NC}"
                            read -p "Press Enter to continue..."
                            continue
                        fi
                        echo -e "Selected wallet: ${GREEN}${wname}${NC} (${CYAN}${waddr}${NC})"
                        ;;
                    *)
                        echo -e "${RED}Invalid option.${NC}"
                        read -p "Press Enter to continue..."
                        continue
                        ;;
                esac

                if [[ ! "$waddr" =~ ^ltd1[a-z0-9]{38,58}$ ]]; then
                    echo -e "${RED}Invalid wallet address format.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                RAW_BAL=$(latandad query bank balances "$waddr" --home "$HOME_DIR" --output json 2>/dev/null || latandad query bank balances "$waddr" --node https://t-latanda.rpc.utsa.tech:443 --output json 2>/dev/null)
                balance=$(echo "$RAW_BAL" | jq -r '.balances[0].amount' 2>/dev/null)
                if [[ -z "$balance" || "$balance" == "null" || "$balance" == "" ]]; then balance="0"; fi
                echo -e "Balance: ${GREEN}${balance} ultd${NC}"
                read -p "Press Enter to continue..."
                ;;
            0) break ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# ============================================
# Option 4: Create Validator
# ============================================
function create_validator() {
    check_binary || return
    print_logo
    echo -e "${YELLOW}--- Create Validator ---${NC}"
    catch_up=$(latandad status --home "$HOME_DIR" 2>&1 | jq -r '.sync_info.catching_up' || echo "true")
    if [[ "$catch_up" != "false" ]]; then
        echo -e "${RED}Warning: Your node is not fully synced yet! Wait until Catching Up is 'False'.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    echo -e "You will need at least ${GREEN}1,000,000 ultd${NC} testing balance for the initial delegation."
    echo ""
    wallet_json=$(latandad keys list --keyring-backend test --home "$HOME_DIR" --output json 2>/dev/null || echo '[]')
    if ! echo "$wallet_json" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
        echo -e "${RED}No saved wallets found in local keyring.${NC}"
        echo -e "Open ${YELLOW}Option 3 (Wallet Management)${NC} to create/recover wallet first."
        read -p "Press Enter to return..."
        return
    fi
    echo -e "${CYAN}Saved wallets from Option 3:${NC}"
    echo "$wallet_json" | jq -r '.[] | "  - \(.name): \(.address)"'
    echo ""
    read -p "Enter your wallet name (from which testnet LTD is funded): " wname
    if ! validate_wallet_name "$wname"; then
        echo -e "${RED}Invalid wallet name. Use letters, numbers, _ or - only.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    if ! latandad keys show "$wname" --keyring-backend test --home "$HOME_DIR" -a >/dev/null 2>&1; then
        echo -e "${RED}Wallet '$wname' not found in local keyring.${NC}"
        echo -e "Open ${YELLOW}Option 3 (Wallet Management)${NC} to create/recover/list wallets first."
        read -p "Press Enter to return..."
        return
    fi
    wallet_addr=$(latandad keys show "$wname" --keyring-backend test --home "$HOME_DIR" -a 2>/dev/null || true)
    wallet_valoper=$(latandad keys show "$wname" --bech val --keyring-backend test --home "$HOME_DIR" -a 2>/dev/null || true)
    if [[ -z "$wallet_addr" ]]; then
        echo -e "${RED}Failed to read wallet address for '$wname'.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    read -p "Enter your Validator Moniker (Public Name): " moniker

    # Make JSON structure safely into validator.json
    if ! pubkey="$(latandad tendermint show-validator --home "$HOME_DIR" 2>/dev/null)"; then
        echo -e "${RED}Failed to read validator pubkey from local node.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    validator_file="$(mktemp /tmp/validator_XXXXXX.json)"
    if ! jq -n \
        --argjson pubkey "$pubkey" \
        --arg moniker "$moniker" \
        '{
            pubkey: $pubkey,
            amount: "1000000ultd",
            moniker: $moniker,
            "commission-rate": "0.10",
            "commission-max-rate": "0.20",
            "commission-max-change-rate": "0.01",
            "min-self-delegation": "1"
        }' > "$validator_file"; then
        echo -e "${RED}Failed to generate validator JSON payload.${NC}"
        rm -f "$validator_file" 2>/dev/null || true
        read -p "Press Enter to return..."
        return
    fi

    echo ""
    echo -e "${CYAN}Creating validator using saved wallet from Option 3:${NC}"
    echo -e "  Wallet Name    : ${GREEN}${wname}${NC}"
    echo -e "  Wallet Address : ${CYAN}${wallet_addr}${NC}"
    [[ -n "$wallet_valoper" ]] && echo -e "  Valoper        : ${CYAN}${wallet_valoper}${NC}"
    echo -e "  Moniker        : ${GREEN}${moniker}${NC}"
    echo ""

    if broadcast_tx "create-validator for $moniker" \
        latandad tx staking create-validator "$validator_file" \
        --from "$wname" \
        --keyring-backend test \
        --chain-id "$CHAIN_ID" \
        --home "$HOME_DIR" \
        --gas auto \
        --gas-adjustment 1.4 \
        --fees "$DEFAULT_FEES"; then
        echo -e "${GREEN}Validator creation submitted. Wait a bit, then check status/rewards.${NC}"
    else
        echo -e "${RED}Validator creation failed. Please read the error above and try again.${NC}"
    fi
    rm -f "$validator_file" 2>/dev/null || true
    read -p "Press Enter to return..."
}

# ============================================
# Option 5: Check Validator Rewards
# ============================================
function check_validator_rewards() {
    check_binary || return
    print_logo
    echo -e "${YELLOW}--- Check Validator Rewards ---${NC}"
    echo ""

    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local rewards_json total_ultd wallet_json validator_name delegator_addr valoper_addr selected_idx
    local key_name key_addr key_valoper validator_json
    local -a wallet_names=()
    local -a wallet_addrs=()
    local -a wallet_valopers=()

    wallet_json=$(latandad keys list --keyring-backend test --home "$HOME_DIR" --output json 2>/dev/null || echo '[]')
    if ! echo "$wallet_json" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
        echo -e "${RED}No saved wallets found in keyring.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    while IFS=$'\t' read -r key_name key_addr; do
        [[ -z "$key_name" ]] && continue
        wallet_names+=("$key_name")
        wallet_addrs+=("$key_addr")
        key_valoper=$(latandad keys show "$key_name" --bech val --keyring-backend test --home "$HOME_DIR" -a 2>/dev/null || true)
        wallet_valopers+=("$key_valoper")
    done < <(echo "$wallet_json" | jq -r '.[] | [.name, .address] | @tsv' 2>/dev/null || true)

    for i in "${!wallet_names[@]}"; do
        key_valoper="${wallet_valopers[$i]}"
        [[ -z "$key_valoper" ]] && continue
        validator_json=$(latandad query staking validator "$key_valoper" --home "$HOME_DIR" --output json 2>/dev/null || latandad query staking validator "$key_valoper" --node "$fallback_node" --output json 2>/dev/null || true)
        if echo "$validator_json" | jq -e --arg v "$key_valoper" '.validator.operator_address? == $v' >/dev/null 2>&1; then
            validator_name="${wallet_names[$i]}"
            delegator_addr="${wallet_addrs[$i]}"
            valoper_addr="$key_valoper"
            break
        fi
    done

    if [[ -z "${delegator_addr:-}" ]]; then
        echo -e "${YELLOW}Validator wallet could not be auto-detected.${NC}"
        echo -e "${YELLOW}Select wallet manually:${NC}"
        j=1
        for i in "${!wallet_names[@]}"; do
            echo "  $j) ${wallet_names[$i]} - ${wallet_addrs[$i]}"
            j=$((j+1))
        done
        read -p "Select wallet number: " selected_idx
        if [[ ! "$selected_idx" =~ ^[0-9]+$ ]] || (( selected_idx < 1 || selected_idx > ${#wallet_names[@]} )); then
            echo -e "${RED}Invalid selection.${NC}"
            read -p "Press Enter to return..."
            return
        fi
        selected_idx=$((selected_idx-1))
        validator_name="${wallet_names[$selected_idx]}"
        delegator_addr="${wallet_addrs[$selected_idx]}"
        valoper_addr="${wallet_valopers[$selected_idx]}"
    fi

    echo -e "Wallet name       : ${GREEN}${validator_name}${NC}"
    echo -e "Delegator address : ${CYAN}${delegator_addr}${NC}"
    if [[ -n "${valoper_addr:-}" ]]; then
        echo -e "Validator operator: ${CYAN}${valoper_addr}${NC}"
    fi
    echo ""

    rewards_json=$(latandad query distribution rewards "$delegator_addr" --home "$HOME_DIR" --output json 2>/dev/null || latandad query distribution rewards "$delegator_addr" --node "$fallback_node" --output json 2>/dev/null || true)

    if echo "$rewards_json" | jq -e . &>/dev/null; then
        total_ultd=$(echo "$rewards_json" | jq -r '
            .total[]?
            | if type == "object" and (.denom // "") == "ultd" then (.amount // "")
              elif type == "string" then .
              else empty end
        ' 2>/dev/null | awk '
            BEGIN { sum = 0 }
            {
                gsub(/[[:space:]]/, "", $0)
                if ($0 ~ /^[0-9]+(\.[0-9]+)?ultd$/) { sub(/ultd$/, "", $0); sum += $0 }
                else if ($0 ~ /^[0-9]+(\.[0-9]+)?$/) { sum += $0 }
            }
            END { printf "%.6f", sum }
        ')

        if [[ -z "$total_ultd" || "$total_ultd" == "0.000000" ]]; then
            total_ultd=$(echo "$rewards_json" | jq -r '
                .rewards[]?.reward[]?
                | if type == "object" and (.denom // "") == "ultd" then (.amount // "")
                  elif type == "string" then .
                  else empty end
            ' 2>/dev/null | awk '
                BEGIN { sum = 0 }
                {
                    gsub(/[[:space:]]/, "", $0)
                    if ($0 ~ /^[0-9]+(\.[0-9]+)?ultd$/) { sub(/ultd$/, "", $0); sum += $0 }
                    else if ($0 ~ /^[0-9]+(\.[0-9]+)?$/) { sum += $0 }
                }
                END { printf "%.6f", sum }
            ')
        fi

        ltd_amount=$(awk -v amount="$total_ultd" 'BEGIN { printf "%.6f", amount / 1000000 }' 2>/dev/null || echo "0")
        echo -e "${CYAN}Reward Summary:${NC}"
        echo -e "Unclaimed rewards : ${GREEN}${total_ultd} ultd${NC}"
        echo -e "Approx in LTD     : ${GREEN}${ltd_amount} LTD${NC}"
        if [[ "$total_ultd" == "0" || "$total_ultd" == "0.0" || "$total_ultd" == "0.000000" ]]; then
            echo -e "${YELLOW}No claimable rewards yet.${NC}"
        fi
    else
        echo -e "${RED}Failed to query rewards.${NC}"
        echo "$rewards_json" | head -n 5
    fi

    echo ""
    echo -e "${YELLOW}Command used:${NC}"
    echo "latandad query distribution rewards $delegator_addr --home ~/.latanda"
    echo ""
    read -p "Press Enter to return..."
}

# ============================================
# Option 6: Governance
# ============================================
function manage_gov() {
    check_binary || return
    while true; do
        print_logo
        echo -e "${YELLOW}--- Governance Hub ---${NC}"
        echo "1. List All Active/Passed Proposals"
        echo "2. Vote on a Proposal"
        echo "3. Submit a New Text Proposal"
        echo "0. Back/Exit"
        echo ""
        read -p "Select action: " opt
        case $opt in
            1)
                echo -e "${CYAN}Fetching network proposals...${NC}"
                PROPOSALS=$(latandad query gov proposals --home "$HOME_DIR" --output json 2>/dev/null || latandad query gov proposals --node https://t-latanda.rpc.utsa.tech:443 --output json 2>/dev/null || echo '{"proposals":[]}')
                
                echo "$PROPOSALS" | jq -c '(.proposals // [])[] | {id: .id, status: .status, title: (.title // .messages[0].content.title), desc: (.summary // .messages[0].content.description), end: .voting_end_time}' | while read -r line; do
                    id=$(echo "$line" | jq -r '.id')
                    status=$(echo "$line" | jq -r '.status')
                    title=$(echo "$line" | jq -r '.title')
                    desc=$(echo "$line" | jq -r '.desc' | head -c 180 | tr '\n' ' ')
                    end_time=$(echo "$line" | jq -r '.end')
                    
                    echo -e "\n${CYAN}- GOV-$(printf "%03d" "$id"): $title${NC}"
                    echo -e "  - Status: ${status#PROPOSAL_STATUS_}"
                    if [[ "$status" == "PROPOSAL_STATUS_VOTING_PERIOD" ]]; then
                        echo -e "  - Voting Ends: $end_time"
                    fi
                    echo -e "  - $desc..."
                    if [[ "$status" == "PROPOSAL_STATUS_VOTING_PERIOD" ]]; then
                        echo -e "  - ${YELLOW}Vote command:${NC}"
                        echo -e "  - latandad tx gov vote $id yes --from <your-key> --keyring-backend test --chain-id latanda-testnet-1 \\"
                        echo -e "  -   --fees 500ultd --gas auto -y"
                    fi


                done
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                read -p "Enter Proposal ID to vote on: " pid
                if ! validate_proposal_id "$pid"; then
                    echo -e "${RED}Invalid proposal ID.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                read -p "Enter your vote (yes / no / no_with_veto / abstain): " vote
                if ! validate_vote "$vote"; then
                    echo -e "${RED}Invalid vote option.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                read -p "Enter your wallet name to vote from: " wname
                if ! validate_wallet_name "$wname"; then
                    echo -e "${RED}Invalid wallet name.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                if ! broadcast_tx "vote on proposal $pid" \
                    latandad tx gov vote "$pid" "$vote" \
                    --from "$wname" \
                    --keyring-backend test \
                    --chain-id "$CHAIN_ID" \
                    --home "$HOME_DIR" \
                    --gas auto \
                    --gas-adjustment 1.4 \
                    --fees "$DEFAULT_FEES"; then
                    echo -e "${RED}Vote transaction failed.${NC}"
                fi
                    
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo -e "${YELLOW}Submitting a Standard Text Proposal${NC}"
                read -p "Enter proposal title: " ptitle
                read -p "Enter proposal description/summary: " pdesc
                read -p "Enter initial deposit (e.g., 1000000ultd): " pdep
                if ! validate_deposit "$pdep"; then
                    echo -e "${RED}Invalid deposit format. Example: 1000000ultd${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                read -p "Enter wallet name the proposal comes from: " wname
                if ! validate_wallet_name "$wname"; then
                    echo -e "${RED}Invalid wallet name.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi

                proposal_file="$(mktemp /tmp/proposal_XXXXXX.json)"
                jq -n \
                    --arg pdep "$pdep" \
                    --arg ptitle "$ptitle" \
                    --arg pdesc "$pdesc" \
                    '{
                        messages: [],
                        metadata: "ipfs://CID",
                        deposit: $pdep,
                        title: $ptitle,
                        summary: $pdesc,
                        expedited: false
                    }' > "$proposal_file"
                if ! broadcast_tx "submit proposal" \
                    latandad tx gov submit-proposal "$proposal_file" \
                    --from "$wname" \
                    --keyring-backend test \
                    --chain-id "$CHAIN_ID" \
                    --home "$HOME_DIR" \
                    --gas auto \
                    --gas-adjustment 1.4 \
                    --fees "$DEFAULT_FEES"; then
                    echo -e "${RED}Submit proposal transaction failed.${NC}"
                fi

                rm -f "$proposal_file" 2>/dev/null || true
                read -p "Press Enter to continue..."
                ;;
            0) break ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# ============================================
# Option 7: Logs
# ============================================
function show_logs() {
    print_logo
    echo -e "${GREEN}Fetching Live Logs from PM2...${NC}"
    echo -e "${YELLOW}(Press Ctrl+C to stop viewing logs and return to prompt)${NC}"
    if ! command -v pm2 &> /dev/null; then
        echo -e "${RED}PM2 is not installed.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    if ! pm2 list | grep -q "latanda-chain"; then
        echo -e "${RED}latanda-chain is not running in PM2.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    pm2 logs latanda-chain
}

# ============================================
# Option 8: Install Advanced Monitor 
# ============================================
function install_advanced_monitor() {
    print_logo
    echo -e "${YELLOW}>> Installing Advanced Monitor...${NC}"
    echo ""

    if ! sudo -v; then
        echo -e "${RED}Sudo access is required to install the monitor launcher.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing python3...${NC}"
        sudo apt-get install -y python3 >/dev/null 2>&1
    fi
    if ! command -v screen >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing screen...${NC}"
        sudo apt-get install -y screen >/dev/null 2>&1
    fi

    INSTALL_DIR="$HOME/.latandad-monitor"
    mkdir -p "$INSTALL_DIR"

    # Write Python Script
    cat > "$INSTALL_DIR/monitor.py" << 'PYEOF'
#!/usr/bin/env python3
import subprocess, json, time, os, sys, threading
from datetime import datetime
from collections import deque

BINARY       = "latandad"
LOCAL_RPC    = "http://localhost:26657"
GENESIS_RPC  = "http://168.231.67.201:26657"
API_BASE     = "http://localhost:1317"
NODE_HOME    = os.path.expanduser("~/.latanda")
VALOPER      = "ltdvaloper1rqff4y87n39qzd4e4y4vcdawvss3e8mq8d2wqv"
CONS_HEX     = "BE0D26EAE32F40DF14F471AA7D2F917640C264F6"
CONS_BECH32  = "ltdvalcons1hcxjd6hr9aqd7985wx486tu3weqvye8kwdngrt"
VAL_START_H  = 426813
REFRESH_SEC  = 10
HISTORY_LEN  = 20
LOG_LINES    = 3
GENESIS_H    = 329

R="\033[0m"; BLD="\033[1m"; DIM="\033[2m"
CYN="\033[36m"; GRN="\033[32m"; YLW="\033[33m"
RED="\033[31m"; BLU="\033[34m"; MGN="\033[35m"; WHT="\033[97m"

def clr(): os.system("clear")
def box(w): return "â”€" * w

def http_get(url, timeout=12):
    try:
        import urllib.request
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "latmon/2.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except:
        return None

def get_local_status():
    try:
        r   = subprocess.run([BINARY, "status", "--home", NODE_HOME], capture_output=True, text=True, timeout=6)
        raw = r.stdout.strip() or r.stderr.strip()
        d   = json.loads(raw)
        si  = d.get("sync_info") or d.get("SyncInfo") or {}
        vi  = d.get("validator_info") or d.get("ValidatorInfo") or {}
        return {"ok": True, "local": int(si.get("latest_block_height", 0)), "block_time": si.get("latest_block_time", ""), "catching_up": bool(si.get("catching_up", True)), "voting_power": vi.get("voting_power", "â€”")}
    except Exception as e:
        return {"ok": False, "error": str(e), "local": 0, "catching_up": True, "voting_power": "â€”"}

def get_network_height():
    for rpc in [GENESIS_RPC, LOCAL_RPC]:
        d = http_get(f"{rpc}/status")
        if d:
            try:
                return int(d["result"]["sync_info"]["latest_block_height"]), rpc.replace("http://", "").split(":")[0]
            except:
                continue
    return None, None

def get_peers():
    d = http_get(f"{LOCAL_RPC}/net_info")
    if d:
        try: return int(d["result"]["n_peers"])
        except: pass
    return None

_val_cache = {"data": None, "ts": 0}
def get_validator_info():
    now = time.time()
    if _val_cache["data"] and now - _val_cache["ts"] < 60: return _val_cache["data"]
    d = http_get(f"{API_BASE}/cosmos/staking/v1beta1/validators/{VALOPER}")
    if d and "validator" in d:
        v = d["validator"]
        result = {"ok": True, "status": v.get("status", ""), "jailed": v.get("jailed", False), "tokens": int(v.get("tokens", 0)), "commission": float(v["commission"]["commission_rates"]["rate"]) * 100}
        _val_cache["data"], _val_cache["ts"] = result, now
        return result
    return {"ok": False}

_slash_cache = {"data": None, "ts": 0}
def get_slash_info():
    now = time.time()
    if _slash_cache["data"] and now - _slash_cache["ts"] < 30: return _slash_cache["data"]
    def parse_si(si): return {"ok": True, "missed_counter": int(si.get("missed_blocks_counter", 0)), "tombstoned": si.get("tombstoned", False), "start_height": int(si.get("start_height", 0)), "jailed_until": si.get("jailed_until", "")}
    d = http_get(f"{API_BASE}/cosmos/slashing/v1beta1/signing_infos/{CONS_BECH32}")
    if d and "val_signing_info" in d:
        result = parse_si(d["val_signing_info"]); _slash_cache["data"], _slash_cache["ts"] = result, now; return result
    d2 = http_get(f"{API_BASE}/cosmos/slashing/v1beta1/signing_infos?pagination.limit=100")
    if d2:
        for si in (d2.get("info") or []):
            if si.get("address", "") == CONS_BECH32:
                result = parse_si(si); _slash_cache["data"], _slash_cache["ts"] = result, now; return result
    return {"ok": False}

_del_cache = {"data": None, "ts": 0}
def get_delegations():
    now = time.time()
    if _del_cache["data"] and now - _del_cache["ts"] < 60: return _del_cache["data"]
    d = http_get(f"{API_BASE}/cosmos/staking/v1beta1/validators/{VALOPER}/delegations")
    if d:
        dels = d.get("delegation_responses", [])
        result = {"ok": True, "count": len(dels), "total": sum(int(x["balance"]["amount"]) for x in dels)}
        _del_cache["data"], _del_cache["ts"] = result, now
        return result
    return {"ok": False}

_sc = {"signed": 0, "missed": 0, "last_scanned": 0, "val_start": 0, "initialized": False, "backfill_done": False, "backfill_pct": 0.0, "lock": threading.Lock()}
def _scan_block(h):
    blk = http_get(f"{LOCAL_RPC}/block?height={h}")
    if not blk: return 0, 0, 1
    try:
        sigs = blk["result"]["block"]["last_commit"]["signatures"]
        if any((s.get("validator_address") or "").upper() == CONS_HEX.upper() for s in sigs): return 1, 0, 0
        elif len(sigs) > 0: return 0, 1, 0
    except: pass
    return 0, 0, 1

def signing_thread(stop_event):
    with _sc["lock"]:
        _sc["val_start"] = VAL_START_H
        _sc["last_scanned"] = VAL_START_H - 1
        _sc["initialized"] = True
    add_log(f"Validator start_height: #{VAL_START_H} (hardcoded)", "OK")
    if stop_event.is_set(): return
    val_start = _sc["val_start"]
    local_st = get_local_status()
    current = local_st.get("local", val_start)
    total_backfill = max(0, current - val_start)
    done_backfill = 0
    add_log(f"Backfill {total_backfill} blok sejak #{val_start}...", "INFO")
    h = val_start
    while h <= current and not stop_event.is_set():
        signed, missed, _ = _scan_block(h)
        with _sc["lock"]:
            _sc["signed"] += signed; _sc["missed"] += missed; _sc["last_scanned"] = h
        done_backfill += 1
        if total_backfill > 0:
            with _sc["lock"]: _sc["backfill_pct"] = done_backfill / total_backfill * 100
        h += 1
        if done_backfill % 100 == 0: add_log(f"Backfill {done_backfill}/{total_backfill} blok...", "INFO")
    with _sc["lock"]:
        _sc["backfill_done"] = True; _sc["backfill_pct"] = 100.0
    add_log(f"Backfill selesai! Total: {_sc['signed']+_sc['missed']} blok", "OK")
    while not stop_event.is_set():
        local_st = get_local_status(); latest = local_st.get("local", 0); last = _sc["last_scanned"]
        if latest > last:
            for h in range(last + 1, latest + 1):
                if stop_event.is_set(): break
                signed, missed, _ = _scan_block(h)
                with _sc["lock"]:
                    _sc["signed"] += signed; _sc["missed"] += missed; _sc["last_scanned"] = h
        time.sleep(REFRESH_SEC)

def calc_scores(signed, missed, local, net_h):
    total = signed + missed
    uptime_score = (signed / total * 100) if total > 0 else 0.0
    sync_score = 100.0 if not net_h or net_h <= 0 else (100.0 if (net_h - local) <= 50 else max(0.0, 100.0 - (((net_h - local) - 50) * 0.15)))
    return uptime_score, sync_score, (uptime_score * 0.6) + (sync_score * 0.4)

def fmt_n(n): return f"{int(n):,}".replace(",", ".") if n is not None else "â€”"
def fmt_ltd(utld): return f"{utld/1000000:,.2f} LTD".replace(",", ".")
def fmt_dur(sec):
    if sec is None or sec < 0: return "â€”"
    sec = int(sec)
    if sec < 60: return f"{sec}s"
    if sec < 3600: return f"{sec//60}m {sec%60}s"
    h = sec // 3600; m = (sec % 3600) // 60
    return f"{h//24}d {h%24}j {m}m" if h >= 24 else f"{h}j {m}m"
def fmt_blktime(iso): return iso[:19].replace("T", " ") if iso else "â€”"
def pbar(pct, width=44, col=None):
    pct = max(0.0, min(100.0, pct)); filled = int(width * pct / 100)
    return (col or (GRN if pct >= 99.9 else YLW if pct >= 85 else CYN)) + "â–ˆ" * filled + DIM + "â–‘" * (width - filled) + R
def score_col(s): return GRN if s >= 95 else YLW if s >= 80 else RED

history = deque(maxlen=HISTORY_LEN); logs = deque(maxlen=60); start_ts = time.time(); net_src = "â€”"
def add_log(msg, lvl="INFO"):
    logs.appendleft(f"{DIM}{datetime.now().strftime('%H:%M:%S')}{R} {({'OK': GRN, 'WARN': YLW, 'ERR': RED, 'INFO': BLU}.get(lvl, DIM))}[{lvl:4}]{R} {msg}")

def render(local_st, net_h, peers):
    W = 90
    local = local_st.get("local", 0); catching = local_st.get("catching_up", True)
    has_err = not local_st.get("ok", True); remaining = max(0, net_h - local) if net_h is not None else None
    pct_sync = min(100.0, max(0.0, (local - GENESIS_H) / max(1, (net_h or local + 1) - GENESIS_H) * 100)) if net_h else 0.0
    bps = eta_sec = None
    if len(history) >= 4:
        win = [(t, b) for t, b in history if time.time() - t <= 60]
        if len(win) >= 2:
            dt = win[-1][0] - win[0][0]; db = win[-1][1] - win[0][1]
            if dt > 0.5 and db > 0: bps = db / dt; eta_sec = remaining / bps if remaining else None
    
    node_status = f"{RED}{BLD}â— ERROR{R}" if has_err else f"{GRN}{BLD}â— SYNCED{R}" if not catching else f"{YLW}{BLD}â— SYNCING{R}"
    with _sc["lock"]: signed, missed, val_start, b_done, b_pct = _sc["signed"], _sc["missed"], _sc["val_start"], _sc["backfill_done"], _sc["backfill_pct"]
    score = calc_scores(signed, missed, local, net_h)
    
    clr()
    pad = max(0, (W - 54) // 2)
    print(f"\n{BLD}{CYN}{' '*pad}  â¬¡ VALIDATOR â€” LA TANDA CHAIN MONITOR  {R}\n{DIM}{box(W)}{R}")
    print(f"  {node_status}   {DIM}monitor uptime:{R} {WHT}{fmt_dur(time.time()-start_ts)}{R}   {DIM}peers:{R} {WHT}{peers or 'â€”'}{R}\n{DIM}{box(W)}{R}\n")
    print(f"  {BLD}{BLU}â–¸ VALIDATOR SCORE{R}\n  {DIM}{'â”€'*52}{R}")
    print(f"  {DIM}Final Score:<24{R}{score_col(score[2])}{BLD}{score[2]:.2f}/100{R}")
    print(f"  {pbar(score[2], W-6, score_col(score[2]))}\n")
    
    print(f"  {BLD}{BLU}â–¸ NODE SYNC{R}\n  {DIM}{'â”€'*52}{R}")
    print(f"  {DIM}Block Lokal:<24{R}{CYN}{BLD}{fmt_n(local)}{R}   {DIM}Sisa: {fmt_n(remaining)}{R}")
    print(f"  {pbar(pct_sync, W-14)}  {BLD}{pct_sync:.2f}%{R}\n")
    
    print(f"  {DIM}{'â”€'*4} Log {'â”€'*(W-12)}{R}")
    for line in list(logs)[:LOG_LINES]: print(f"  {line}")
    print(f"\n{DIM}{box(W)}{R}\n  {DIM}Ctrl+C keluar  â”‚  screen -r latmon re-attach{R}\n")

def main():
    global net_src
    add_log("Monitor dimulai", "OK")
    threading.Thread(target=signing_thread, args=(threading.Event(),), daemon=True).start()
    net_h = peers = tick = prev_local = prev_net = None
    try:
        while True:
            tick = (tick or 0) + 1; local_st = get_local_status()
            if local_st["ok"]:
                cur = local_st["local"]
                if prev_local is None or cur > prev_local:
                    history.append((time.time(), cur)); prev_local = cur
            if tick % 3 == 0 or net_h is None:
                nh, src = get_network_height()
                if nh: net_h, net_src, prev_net = nh, src or "â€”", nh
            if tick % 4 == 0 or peers is None: peers = get_peers()
            render(local_st, net_h, peers)
            time.sleep(REFRESH_SEC)
    except KeyboardInterrupt:
        os.system("clear"); sys.exit(0)

if __name__ == "__main__": main()
PYEOF

    chmod +x "$INSTALL_DIR/monitor.py"

    echo -e "${YELLOW}Creating 'latmon' launcher in /usr/local/bin...${NC}"
    MONITOR_FULL_PATH="$INSTALL_DIR/monitor.py"
    sudo tee /usr/local/bin/latmon >/dev/null << LAUNCHEREOF
#!/bin/bash
SCREEN_NAME="latmon"
MONITOR_PATH="$MONITOR_FULL_PATH"

case "\$1" in
  stop) screen -XS \$SCREEN_NAME quit 2>/dev/null && echo "Monitor dihentikan." || echo "Tidak ada session aktif." ;;
  attach|log) screen -r \$SCREEN_NAME ;;
  status) screen -list | grep \$SCREEN_NAME || echo "Monitor tidak berjalan." ;;
  restart) screen -XS \$SCREEN_NAME quit 2>/dev/null; sleep 1; screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH; echo -e "\033[32m[âœ“] Monitor di-restart.\033[0m" ;;
  *)
    if screen -list 2>/dev/null | grep -q "\$SCREEN_NAME"; then
      echo -e "\033[33m[!] Monitor sudah berjalan.\033[0m"
      echo -e "    Attach  : screen -r \$SCREEN_NAME"
      echo -e "    Stop    : latmon stop"
    else
      echo -e "\033[32m[âœ“] Memulai monitor...\033[0m"
      screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH
      sleep 0.8
      if screen -list 2>/dev/null | grep -q "\$SCREEN_NAME"; then
        echo -e "\033[32m[âœ“] Berjalan! Attach dengan:\033[0m  screen -r \$SCREEN_NAME"
      else
        echo -e "\033[31m[âœ—] Gagal start. Coba manual:\033[0m  python3 \$MONITOR_PATH"
      fi
    fi
    ;;
esac
LAUNCHEREOF

    sudo chmod +x /usr/local/bin/latmon
    echo -e "${GREEN}Monitor successfully installed!${NC}"
    echo -e "You can launch it anytime by typing: ${GREEN}latmon${NC}"
    echo ""
    read -p "Press Enter to return to main menu..."
}

# ============================================
# Option 9: Clean Uninstall
# ============================================
function uninstall_node() {
    print_logo
    echo -e "${RED}======================================================${NC}"
    echo -e "${RED}       âš ï¸  DANGER: CLEAN UNINSTALLATION âš ï¸           ${NC}"
    echo -e "${RED}======================================================${NC}"
    echo -e "This will completely remove the La Tanda Node, PM2 routines,"
    echo -e "Blockchain Data, and ${RED}ALL YOUR SAVED WALLETS${NC} from this machine."
    echo ""
    echo -e "${YELLOW}ðŸš¨ CRITICAL REMINDER: ðŸš¨${NC}"
    echo -e "Please ensure you have securely backed up your 24-word Mnemonic"
    echo -e "Phrases for all your wallets. Once wiped, they are gone FOREVER."
    echo ""
    read -p "Type 'DELETE' to confirm you have backed up and want to wipe: " confirm
    
    if [[ "$confirm" != "DELETE" ]]; then
        echo -e "\n${CYAN}Uninstall aborted. Your node and wallets are safe.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    echo -e "\n${YELLOW}Stopping PM2 Background Processes...${NC}"
    if command -v pm2 &> /dev/null; then
        pm2 stop latanda-chain &>/dev/null || true
        pm2 delete latanda-chain &>/dev/null || true
        pm2 save --force &>/dev/null || true
    fi
    pkill -f latandad &>/dev/null || true
    pkill -f monitor.py &>/dev/null || true
    pkill -f latmon &>/dev/null || true

    echo -e "${YELLOW}Wiping Node & Wallet Data...${NC}"
    rm -rf "$HOME/.latanda"

    echo -e "${YELLOW}Removing Binaries & System Scripts...${NC}"
    sudo rm -f /usr/local/bin/latandad
    sudo rm -f /usr/local/bin/latman
    sudo rm -f /usr/local/bin/latmon
    rm -rf "$HOME/.latandad-monitor"

    echo -e "${GREEN}âœ… Uninstallation Complete!${NC}"
    echo -e "The La Tanda CLI and all node data have been cleanly wiped."
    exit 0
}

function show_interactive_menu() {
    while true; do
        print_logo
        echo "1) Install Node & Run (One-Click PM2 Setup)"
        echo "2) Check Node Status & Sync Progress"
        echo "3) Wallet Management"
        echo "4) Create Validator (Stake on Network)"
        echo "5) Check Validator Rewards"
        echo "6) Governance Actions (Vote / Propose)"
        echo "7) View Live Logs"
        echo "8) Install & Run Advanced Monitor"
        echo "9) Clean Uninstall Node & Manager"
        echo "0) Exit Manager"
        echo "---------------------------------------------------"
        read -p "Please select an option [0-9]: " choice

        case $choice in
            1) install_node ;;
            2) check_status ;;
            3) manage_wallet ;;
            4) create_validator ;;
            5) check_validator_rewards ;;
            6) manage_gov ;;
            7) show_logs ;;
            8) install_advanced_monitor ;;
            9) uninstall_node ;;
            0) echo -e "${CYAN}Exiting La Tanda Manager. See you next time!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid feature! Select a valid number.${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================
# Subcommand Router
# ============================================
case "${1:-}" in
    status) check_status ;;
    wallet) manage_wallet ;;
    validator) create_validator ;;
    rewards) check_validator_rewards ;;
    gov) manage_gov ;;
    logs) show_logs ;;
    monitor) 
        if command -v latmon &> /dev/null; then
            latmon attach || latmon
        else
            echo -e "${RED}Monitor is not installed. Run 'latman' and choose option 7 to install it.${NC}"
        fi
        ;;
    update) self_update ;;
    install) install_node ;;
    uninstall) uninstall_node ;;
    help|--help|-h)
        echo -e "${CYAN}  La Tanda Node Manager (latman)${NC}"
        echo "  Usage: latman [command]"
        echo ""
        echo "  Commands:"
        echo "    (none)      - Open interactive menu dashboard"
        echo "    status      - Check node status and sync progress"
        echo "    wallet      - Manage wallets"
        echo "    validator   - Create or check validator"
        echo "    rewards     - Check validator rewards (auto-detect validator address)"
        echo "    gov         - Manage governance proposals"
        echo "    logs        - View live pm2 logs"
        echo "    monitor     - Attach to advanced python monitor"
        echo "    update      - Check latest script and auto-update latman"
        echo "    install     - Install node and run with PM2"
        echo "    uninstall   - Cleanly wipe the node, data, and CLI manager"
        ;;
    *)
        show_interactive_menu
        ;;
esac
