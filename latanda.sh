#!/bin/bash
# ============================================
# La Tanda Chain - Interactive Node Manager
# Version: 2.2 (Configurable Monitor Validator)
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
GO_SHA256="cb2396bae64183cdccf81a9a6df0aea3bce9511fc21469fb89a0c00470088073"
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
    local output json_output
    output=$("$@" -y --output json 2>&1 || true)
    json_output="$output"

    if ! echo "$json_output" | jq -e . &>/dev/null; then
        json_output=$(echo "$output" | awk 'found || $0 ~ /^[[:space:]]*\{/ { found=1; print }')
    fi

    if echo "$json_output" | jq -e . &>/dev/null; then
        local code
        local txhash
        local raw_log
        code=$(echo "$json_output" | jq -r '(.code // 0) | tostring')
        txhash=$(echo "$json_output" | jq -r '.txhash // empty')
        raw_log=$(echo "$json_output" | jq -r '.raw_log // empty')

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
    local force_mode="${1:-}"

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
        if [[ "$force_mode" == "--force" || "$force_mode" == "-f" ]]; then
            echo -e "${YELLOW}Force update requested. Reinstalling current latest script...${NC}"
        else
            echo -e "${GREEN}2. latest version${NC}"
            [[ -n "$local_version" ]] && echo -e "Current version: ${CYAN}$local_version${NC}"
            rm -f "$tmp_script"
            read -p "Press Enter to return..."
            return
        fi
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

function validate_wallet_address() {
    local value="$1"
    [[ "$value" =~ ^ltd1[a-z0-9]{38,58}$ ]]
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

function ultd_to_ltd() {
    local amount="${1:-0}"
    awk -v amount="$amount" 'BEGIN { printf "%.6f", amount / 1000000 }' 2>/dev/null || echo "0.000000"
}

function ltd_to_ultd() {
    local amount="${1:-0}"
    awk -v amount="$amount" '
        BEGIN {
            if (amount !~ /^[0-9]+([.][0-9]{1,6})?$/) exit 1
            printf "%.0f", amount * 1000000
        }
    '
}

function format_number() {
    local value="${1:-0}"
    awk -v n="$value" '
        function group(x,    out, len, part) {
            x = sprintf("%d", x)
            out = ""
            while (length(x) > 3) {
                len = length(x)
                part = substr(x, len - 2, 3)
                out = "." part out
                x = substr(x, 1, len - 3)
            }
            return x out
        }
        BEGIN { print group(n) }
    ' 2>/dev/null || echo "$value"
}

function format_duration() {
    local seconds="${1:-0}"
    awk -v s="$seconds" '
        BEGIN {
            s = int(s)
            if (s < 0) s = 0
            d = int(s / 86400); s %= 86400
            h = int(s / 3600); s %= 3600
            m = int(s / 60)
            if (d > 0) printf "%dd %dh %dm", d, h, m
            else if (h > 0) printf "%dh %dm", h, m
            else printf "%dm", m
        }
    '
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
    if ! command -v pm2 &> /dev/null || ! pm2 list | grep -q "latanda-chain"; then
        print_logo
        echo -e "${CYAN}--- Node Sync Status ---${NC}"
        echo -e "${RED}Node is not running via PM2. Did you install it properly?${NC}"
        echo ""
        read -p "Press Enter to return..."
        return
    fi

    local local_rpc="http://127.0.0.1:26657"
    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local refresh_sec=3
    local prev_block="" prev_ts="" last_error=""
    local status_json net_json catch_up local_block network_block blocks_left progress_pct
    local now_ts loop_started elapsed sleep_for tick block_diff time_diff block_rate eta_seconds eta_text
    local stop_dashboard=0

    trap 'stop_dashboard=1' INT
    tick=0
    while (( stop_dashboard == 0 )); do
        loop_started=$(date +%s)
        tick=$((tick + 1))
        status_json=$(curl -fsS --max-time 2 "$local_rpc/status" 2>/dev/null || true)

        if ! echo "$status_json" | jq -e . >/dev/null 2>&1; then
            last_error="Failed to read local RPC status within 2 seconds."
            local_block="${prev_block:-0}"
            catch_up="true"
        else
            last_error=""
            catch_up=$(echo "$status_json" | jq -r '.result.sync_info.catching_up // true')
            local_block=$(echo "$status_json" | jq -r '.result.sync_info.latest_block_height // 0')
        fi

        if (( tick == 1 || tick % 5 == 0 )); then
            net_json=$(curl -fsS --max-time 1 "$fallback_node/status" 2>/dev/null || true)
            network_block=$(echo "$net_json" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
        fi
        if [[ -z "$network_block" || ! "$network_block" =~ ^[0-9]+$ ]]; then
            network_block="$local_block"
            [[ -z "$last_error" ]] && last_error="Failed to read public RPC network height."
        fi

        blocks_left=$((network_block - local_block))
        (( blocks_left < 0 )) && blocks_left=0
        progress_pct=$(awk -v l="$local_block" -v n="$network_block" 'BEGIN { if (n > 0) printf "%.2f", (l / n) * 100; else printf "0.00" }')

        now_ts=$(date +%s)
        block_rate="0.00"
        eta_text="Unknown"
        if [[ "$prev_block" =~ ^[0-9]+$ && "$prev_ts" =~ ^[0-9]+$ && "$local_block" =~ ^[0-9]+$ ]]; then
            block_diff=$((local_block - prev_block))
            time_diff=$((now_ts - prev_ts))
            if (( block_diff > 0 && time_diff > 0 )); then
                block_rate=$(awk -v d="$block_diff" -v s="$time_diff" 'BEGIN { printf "%.2f", d / s }')
                eta_seconds=$(awk -v left="$blocks_left" -v rate="$block_rate" 'BEGIN { if (rate > 0) printf "%.0f", left / rate; else print 0 }')
                eta_text=$(format_duration "$eta_seconds")
            fi
        fi
        if [[ "$catch_up" == "false" || "$blocks_left" == "0" ]]; then
            eta_text="Already synced"
        fi

        print_logo
        echo -e "${CYAN}--- Node Sync Dashboard ---${NC}"
        echo -e "Local Block     : ${GREEN}$(format_number "$local_block")${NC}"
        echo -e "Network Block   : ${CYAN}$(format_number "$network_block")${NC}"
        echo -e "Blocks Left     : ${YELLOW}$(format_number "$blocks_left")${NC}"
        echo -e "Sync Progress   : ${GREEN}${progress_pct}%${NC}"
        echo -e "Block Rate      : ${GREEN}${block_rate} blocks/sec${NC}"
        if [[ "$eta_text" == "Already synced" ]]; then
            echo -e "ETA Fully Sync  : ${GREEN}${eta_text}${NC}"
        else
            echo -e "ETA Fully Sync  : ${YELLOW}${eta_text}${NC}"
        fi
        if [[ "$catch_up" == "false" ]]; then
            echo -e "Sync Status     : ${GREEN}False (Fully Synced && Ready for Validator)${NC}"
        else
            echo -e "Sync Status     : ${YELLOW}True (Still syncing...)${NC}"
        fi
        [[ -n "$last_error" ]] && echo -e "Warning         : ${YELLOW}${last_error}${NC}"
        echo ""
        echo -e "${CYAN}Refresh every ${refresh_sec}s | Press Ctrl+C to return to menu${NC}"

        if [[ "$local_block" =~ ^[0-9]+$ ]]; then
            prev_block="$local_block"
            prev_ts="$now_ts"
        fi
        elapsed=$(( $(date +%s) - loop_started ))
        sleep_for=$((refresh_sec - elapsed))
        (( sleep_for < 1 )) && sleep_for=1
        sleep "$sleep_for"
    done
    trap - INT
    echo ""
}

# ============================================
# Option 3: Wallet Management
# ============================================
function send_ltd() {
    print_logo
    echo -e "${YELLOW}--- Send LTD ---${NC}"
    echo ""

    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local wallet_json pick sender_name sender_addr recipient_addr
    local balance_json balance_ultd balance_ltd fee_ultd available_ultd
    local amount_ltd amount_ultd confirm

    wallet_json=$(latandad keys list --keyring-backend test --home "$HOME_DIR" --output json 2>/dev/null || echo '[]')
    if ! echo "$wallet_json" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
        echo -e "${RED}No saved wallets found.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo -e "${CYAN}Select sender wallet:${NC}"
    local i=1
    while IFS=$'\t' read -r n a; do
        echo "  $i) $n - $a"
        i=$((i+1))
    done < <(echo "$wallet_json" | jq -r '.[] | [.name, .address] | @tsv' 2>/dev/null)

    read -p "Select wallet number: " pick
    if [[ ! "$pick" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    sender_name=$(echo "$wallet_json" | jq -r --argjson idx "$((pick-1))" '.[$idx].name // empty' 2>/dev/null || true)
    sender_addr=$(echo "$wallet_json" | jq -r --argjson idx "$((pick-1))" '.[$idx].address // empty' 2>/dev/null || true)
    if [[ -z "$sender_name" || -z "$sender_addr" ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    balance_json=$(latandad query bank balances "$sender_addr" --home "$HOME_DIR" --output json 2>/dev/null || latandad query bank balances "$sender_addr" --node "$fallback_node" --output json 2>/dev/null || true)
    balance_ultd=$(echo "$balance_json" | jq -r '.balances[]? | select(.denom=="ultd") | .amount' 2>/dev/null | head -n 1)
    [[ -z "$balance_ultd" || "$balance_ultd" == "null" ]] && balance_ultd="0"
    if [[ ! "$balance_ultd" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Failed to read the sender wallet balance.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    fee_ultd="${DEFAULT_FEES%ultd}"
    if [[ ! "$fee_ultd" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Configured transaction fee is invalid: ${DEFAULT_FEES}${NC}"
        read -p "Press Enter to return..."
        return
    fi

    available_ultd=$((balance_ultd - fee_ultd))
    (( available_ultd < 0 )) && available_ultd=0
    balance_ltd=$(ultd_to_ltd "$balance_ultd")

    echo ""
    echo -e "Sender wallet    : ${GREEN}${sender_name}${NC} (${CYAN}${sender_addr}${NC})"
    echo -e "Wallet balance   : ${GREEN}${balance_ltd} LTD${NC}"
    echo -e "Reserved tx fee  : ${YELLOW}${DEFAULT_FEES}${NC}"
    echo -e "Maximum send     : ${GREEN}$(ultd_to_ltd "$available_ultd") LTD${NC}"
    echo ""

    read -p "Enter recipient address (starts with ltd1...): " recipient_addr
    if ! validate_wallet_address "$recipient_addr"; then
        echo -e "${RED}Invalid recipient wallet address format.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    if [[ "$recipient_addr" == "$sender_addr" ]]; then
        echo -e "${RED}Recipient address cannot be the same as the sender address.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    read -p "Enter amount to send in LTD (example: 100 or 12.5): " amount_ltd
    if ! amount_ultd=$(ltd_to_ultd "$amount_ltd") || [[ ! "$amount_ultd" =~ ^[0-9]+$ ]] || (( amount_ultd <= 0 )); then
        echo -e "${RED}Invalid amount. Use a positive LTD amount with up to 6 decimal places.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if (( amount_ultd > available_ultd )); then
        echo -e "${RED}Insufficient balance after reserving ${DEFAULT_FEES} for the transaction fee.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo ""
    echo -e "${YELLOW}Review transaction carefully:${NC}"
    echo -e "From   : ${GREEN}${sender_name}${NC} (${CYAN}${sender_addr}${NC})"
    echo -e "To     : ${CYAN}${recipient_addr}${NC}"
    echo -e "Amount : ${GREEN}${amount_ltd} LTD${NC} (${CYAN}${amount_ultd} ultd${NC})"
    echo -e "Fee    : ${YELLOW}${DEFAULT_FEES}${NC}"
    echo ""
    read -p "Type 'SEND' to broadcast the transaction: " confirm
    if [[ "$confirm" != "SEND" ]]; then
        echo -e "${CYAN}Send cancelled. Nothing was broadcast.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if broadcast_tx "send ${amount_ltd} LTD to ${recipient_addr}" \
        latandad tx bank send "$sender_name" "$recipient_addr" "${amount_ultd}ultd" \
        --from "$sender_name" \
        --keyring-backend test \
        --chain-id "$CHAIN_ID" \
        --home "$HOME_DIR" \
        --gas auto \
        --gas-adjustment 1.4 \
        --fees "$DEFAULT_FEES"; then
        echo -e "${GREEN}Send transaction submitted.${NC}"
    else
        echo -e "${RED}Send transaction failed. Please read the error above and try again.${NC}"
    fi
    read -p "Press Enter to return..."
}

function manage_wallet() {
    check_binary || return
    while true; do
        print_logo
        echo -e "${YELLOW}--- Wallet Management ---${NC}"
        echo "1. Create New Wallet"
        echo "2. Recover Wallet (from mnemonic seed)"
        echo "3. List Saved Wallets"
        echo "4. Check Wallet Balance"
        echo "5. Send LTD"
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

                if ! validate_wallet_address "$waddr"; then
                    echo -e "${RED}Invalid wallet address format.${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                RAW_BAL=$(latandad query bank balances "$waddr" --home "$HOME_DIR" --output json 2>/dev/null || latandad query bank balances "$waddr" --node https://t-latanda.rpc.utsa.tech:443 --output json 2>/dev/null)
                balance=$(echo "$RAW_BAL" | jq -r '.balances[]? | select(.denom=="ultd") | .amount' 2>/dev/null | head -n 1)
                if [[ -z "$balance" || "$balance" == "null" || "$balance" == "" ]]; then balance="0"; fi
                ltd_balance=$(ultd_to_ltd "$balance")
                echo -e "Balance: ${GREEN}${ltd_balance} LTD${NC}"
                echo -e "Raw    : ${CYAN}${balance} ultd${NC}"
                read -p "Press Enter to continue..."
                ;;
            5) send_ltd ;;
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
# Option 5: Validator Rewards
# ============================================
function select_validator_wallet() {
    local fallback_node="$1"
    local wallet_json selected_idx
    local key_name key_addr key_valoper validator_json
    local -a wallet_names=()
    local -a wallet_addrs=()
    local -a wallet_valopers=()

    REWARD_WALLET_NAME=""
    REWARD_DELEGATOR_ADDR=""
    REWARD_VALOPER_ADDR=""

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
            REWARD_WALLET_NAME="${wallet_names[$i]}"
            REWARD_DELEGATOR_ADDR="${wallet_addrs[$i]}"
            REWARD_VALOPER_ADDR="$key_valoper"
            break
        fi
    done

    if [[ -z "$REWARD_DELEGATOR_ADDR" ]]; then
        echo -e "${YELLOW}Validator wallet could not be auto-detected.${NC}"
        echo -e "${YELLOW}Select wallet manually:${NC}"
        local j=1
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
        REWARD_WALLET_NAME="${wallet_names[$selected_idx]}"
        REWARD_DELEGATOR_ADDR="${wallet_addrs[$selected_idx]}"
        REWARD_VALOPER_ADDR="${wallet_valopers[$selected_idx]}"
    fi

    echo -e "Wallet name       : ${GREEN}${REWARD_WALLET_NAME}${NC}"
    echo -e "Delegator address : ${CYAN}${REWARD_DELEGATOR_ADDR}${NC}"
    [[ -n "$REWARD_VALOPER_ADDR" ]] && echo -e "Validator operator: ${CYAN}${REWARD_VALOPER_ADDR}${NC}"
    echo ""
    return 0
}

function print_rewards_summary() {
    local rewards_json="$1"
    local total_ultd ltd_amount

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

    ltd_amount=$(ultd_to_ltd "$total_ultd")
    echo -e "${CYAN}Reward Summary:${NC}"
    echo -e "Unclaimed rewards : ${GREEN}${ltd_amount} LTD${NC}"
    echo -e "Raw amount        : ${CYAN}${total_ultd} ultd${NC}"
    if [[ "$total_ultd" == "0" || "$total_ultd" == "0.0" || "$total_ultd" == "0.000000" ]]; then
        echo -e "${YELLOW}No claimable rewards yet.${NC}"
    fi
}

function show_validator_rewards() {
    print_logo
    echo -e "${YELLOW}--- Check Validator Rewards ---${NC}"
    echo ""

    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local rewards_json

    select_validator_wallet "$fallback_node" || return

    rewards_json=$(latandad query distribution rewards "$REWARD_DELEGATOR_ADDR" --home "$HOME_DIR" --output json 2>/dev/null || latandad query distribution rewards "$REWARD_DELEGATOR_ADDR" --node "$fallback_node" --output json 2>/dev/null || true)

    if echo "$rewards_json" | jq -e . &>/dev/null; then
        print_rewards_summary "$rewards_json"
    else
        echo -e "${RED}Failed to query rewards.${NC}"
        echo "$rewards_json" | head -n 5
    fi

    echo ""
    echo -e "${YELLOW}Command used:${NC}"
    echo "latandad query distribution rewards $REWARD_DELEGATOR_ADDR --home ~/.latanda"
    echo ""
    read -p "Press Enter to return..."
}

function claim_validator_rewards() {
    print_logo
    echo -e "${YELLOW}--- Claim Validator Rewards ---${NC}"
    echo ""

    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local validator_json rewards_json confirm

    select_validator_wallet "$fallback_node" || return

    if [[ -z "$REWARD_VALOPER_ADDR" ]]; then
        echo -e "${RED}Validator operator address could not be derived from this wallet.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    validator_json=$(latandad query staking validator "$REWARD_VALOPER_ADDR" --home "$HOME_DIR" --output json 2>/dev/null || latandad query staking validator "$REWARD_VALOPER_ADDR" --node "$fallback_node" --output json 2>/dev/null || true)
    if ! echo "$validator_json" | jq -e --arg v "$REWARD_VALOPER_ADDR" '.validator.operator_address? == $v' >/dev/null 2>&1; then
        echo -e "${RED}This wallet does not appear to be an active validator on-chain.${NC}"
        echo -e "Open ${YELLOW}Option 4${NC} to create a validator first, or select the validator wallet."
        read -p "Press Enter to return..."
        return
    fi

    rewards_json=$(latandad query distribution rewards "$REWARD_DELEGATOR_ADDR" --home "$HOME_DIR" --output json 2>/dev/null || latandad query distribution rewards "$REWARD_DELEGATOR_ADDR" --node "$fallback_node" --output json 2>/dev/null || true)
    if echo "$rewards_json" | jq -e . &>/dev/null; then
        print_rewards_summary "$rewards_json"
        echo ""
    fi

    echo -e "${YELLOW}This will withdraw delegator rewards and validator commission, if available.${NC}"
    echo -e "From wallet : ${GREEN}${REWARD_WALLET_NAME}${NC}"
    echo -e "Validator   : ${CYAN}${REWARD_VALOPER_ADDR}${NC}"
    echo ""
    read -p "Type 'CLAIM' to broadcast the claim transaction: " confirm
    if [[ "$confirm" != "CLAIM" ]]; then
        echo -e "${CYAN}Claim cancelled. Nothing was broadcast.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if broadcast_tx "claim validator rewards" \
        latandad tx distribution withdraw-rewards "$REWARD_VALOPER_ADDR" \
        --from "$REWARD_WALLET_NAME" \
        --commission \
        --keyring-backend test \
        --chain-id "$CHAIN_ID" \
        --home "$HOME_DIR" \
        --gas auto \
        --gas-adjustment 1.4 \
        --fees "$DEFAULT_FEES"; then
        echo -e "${GREEN}Claim transaction submitted. Check your wallet balance after the tx is indexed.${NC}"
    else
        echo -e "${RED}Claim transaction failed. Please read the error above and try again.${NC}"
    fi
    read -p "Press Enter to return..."
}

function restake_validator_rewards() {
    print_logo
    echo -e "${YELLOW}--- Restake Claimed Rewards ---${NC}"
    echo ""

    local fallback_node="https://t-latanda.rpc.utsa.tech:443"
    local validator_json balance_json balance_ultd balance_ltd
    local amount_ltd amount_ultd fee_ultd available_ultd confirm

    select_validator_wallet "$fallback_node" || return

    if [[ -z "$REWARD_VALOPER_ADDR" ]]; then
        echo -e "${RED}Validator operator address could not be derived from this wallet.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    validator_json=$(latandad query staking validator "$REWARD_VALOPER_ADDR" --home "$HOME_DIR" --output json 2>/dev/null || latandad query staking validator "$REWARD_VALOPER_ADDR" --node "$fallback_node" --output json 2>/dev/null || true)
    if ! echo "$validator_json" | jq -e --arg v "$REWARD_VALOPER_ADDR" '.validator.operator_address? == $v' >/dev/null 2>&1; then
        echo -e "${RED}This wallet does not appear to be a validator on-chain.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    balance_json=$(latandad query bank balances "$REWARD_DELEGATOR_ADDR" --home "$HOME_DIR" --output json 2>/dev/null || latandad query bank balances "$REWARD_DELEGATOR_ADDR" --node "$fallback_node" --output json 2>/dev/null || true)
    balance_ultd=$(echo "$balance_json" | jq -r '[.balances[]? | select(.denom=="ultd") | (.amount | tonumber)] | add // 0' 2>/dev/null || echo "0")
    if [[ ! "$balance_ultd" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Failed to read the wallet LTD balance.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    fee_ultd="${DEFAULT_FEES%ultd}"
    if [[ ! "$fee_ultd" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Configured transaction fee is invalid: ${DEFAULT_FEES}${NC}"
        read -p "Press Enter to return..."
        return
    fi

    available_ultd=$((balance_ultd - fee_ultd))
    (( available_ultd < 0 )) && available_ultd=0
    balance_ltd=$(ultd_to_ltd "$balance_ultd")

    echo -e "Wallet balance    : ${GREEN}${balance_ltd} LTD${NC} (${CYAN}${balance_ultd} ultd${NC})"
    echo -e "Reserved tx fee   : ${YELLOW}${DEFAULT_FEES}${NC}"
    echo -e "Maximum restake   : ${GREEN}$(ultd_to_ltd "$available_ultd") LTD${NC}"
    echo ""
    echo -e "${YELLOW}Claim rewards first, then wait for the claim transaction to be indexed before restaking.${NC}"
    read -p "Enter amount to restake in LTD (example: 5000 or 12.5): " amount_ltd

    if ! amount_ultd=$(ltd_to_ultd "$amount_ltd") || [[ ! "$amount_ultd" =~ ^[0-9]+$ ]] || (( amount_ultd <= 0 )); then
        echo -e "${RED}Invalid amount. Use a positive LTD amount with up to 6 decimal places.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if (( amount_ultd > available_ultd )); then
        echo -e "${RED}Insufficient balance after reserving ${DEFAULT_FEES} for the transaction fee.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo ""
    echo -e "Restake amount : ${GREEN}${amount_ltd} LTD${NC} (${CYAN}${amount_ultd} ultd${NC})"
    echo -e "Validator      : ${CYAN}${REWARD_VALOPER_ADDR}${NC}"
    echo -e "From wallet    : ${GREEN}${REWARD_WALLET_NAME}${NC}"
    echo ""
    read -p "Type 'RESTAKE' to broadcast the delegation transaction: " confirm
    if [[ "$confirm" != "RESTAKE" ]]; then
        echo -e "${CYAN}Restake cancelled. Nothing was broadcast.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    if broadcast_tx "restake ${amount_ltd} LTD to validator" \
        latandad tx staking delegate "$REWARD_VALOPER_ADDR" "${amount_ultd}ultd" \
        --from "$REWARD_WALLET_NAME" \
        --keyring-backend test \
        --chain-id "$CHAIN_ID" \
        --home "$HOME_DIR" \
        --gas auto \
        --gas-adjustment 1.4 \
        --fees "$DEFAULT_FEES"; then
        echo -e "${GREEN}Restake transaction submitted.${NC}"
    else
        echo -e "${RED}Restake transaction failed. Please read the error above and try again.${NC}"
    fi
    read -p "Press Enter to return..."
}

function manage_validator_rewards() {
    check_binary || return
    while true; do
        print_logo
        echo -e "${YELLOW}--- Validator Rewards ---${NC}"
        echo "1. Check Validator Rewards"
        echo "2. Claim Validator Rewards"
        echo "3. Restake Claimed Rewards"
        echo "0. Back to Main Menu"
        echo ""
        read -p "Select action: " opt
        case $opt in
            1) show_validator_rewards ;;
            2) claim_validator_rewards ;;
            3) restake_validator_rewards ;;
            0) break ;;
            *) echo "Invalid option."; sleep 1 ;;
        esac
    done
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

    echo -e "${CYAN}Enter the validator operator address to monitor.${NC}"
    echo -e "Example: ltdvaloper1..."
    read -p "Validator operator address: " MONITOR_VALOPER
    if [[ ! "$MONITOR_VALOPER" =~ ^ltdvaloper1[a-z0-9]{38,58}$ ]]; then
        echo -e "${RED}Invalid validator operator address format.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    printf 'VALOPER=%s\n' "$MONITOR_VALOPER" > "$INSTALL_DIR/monitor.env"

    # Write Python Script
    cat > "$INSTALL_DIR/monitor.py" << 'PYEOF'
#!/usr/bin/env python3
import base64, hashlib, subprocess, json, time, os, sys, threading, re
from datetime import datetime
from collections import deque

BINARY       = "latandad"
LOCAL_RPC    = "http://localhost:26657"
GENESIS_RPC  = "http://168.231.67.201:26657"
API_BASE     = "http://localhost:1317"
NODE_HOME    = os.path.expanduser("~/.latanda")
CONFIG_DIR   = os.path.expanduser("~/.latandad-monitor")
CONFIG_PATH  = os.path.join(CONFIG_DIR, "monitor.env")
VALOPER      = ""
CONS_HEX     = ""
CONS_BECH32  = ""
VAL_START_H  = 0
REFRESH_SEC  = 10
HISTORY_LEN  = 20
LOG_LINES    = 3
GENESIS_H    = 329

VALOPER_RE   = re.compile(r'^ltdvaloper1[a-z0-9]{38,58}$')

R="\033[0m"; BLD="\033[1m"; DIM="\033[2m"
CYN="\033[36m"; GRN="\033[32m"; YLW="\033[33m"
RED="\033[31m"; BLU="\033[34m"; MGN="\033[35m"; WHT="\033[97m"

def clr(): os.system("clear")
def box(w): return "-" * w

def http_get(url, timeout=12):
    try:
        import urllib.request
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "latmon/2.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except:
        return None

def run_cmd(args, timeout=10):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return (r.stdout.strip() or r.stderr.strip()) if r.returncode == 0 else ""
    except:
        return ""

def run_json(args, timeout=10):
    raw = run_cmd(args, timeout)
    try:
        return json.loads(raw)
    except:
        return None

def read_config_valoper():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("VALOPER="):
                    return line.split("=", 1)[1].strip()
    except:
        pass
    return ""

def save_config_valoper(valoper):
    """Save the validator operator address to config for future sessions."""
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            f.write(f"VALOPER={valoper}\n")
    except Exception as e:
        print(f"{RED}[!] Failed to save config: {e}{R}")

def resolve_valoper():
    """Determine VALOPER from: CLI arg > saved config > interactive prompt."""
    # 1. CLI argument takes priority (latmon <address>)
    if len(sys.argv) > 1:
        candidate = sys.argv[1].strip()
        if VALOPER_RE.match(candidate):
            save_config_valoper(candidate)
            return candidate
        else:
            print(f"{RED}[!] Invalid validator address format: {candidate}{R}")
            print(f"{DIM}    Expected: ltdvaloper1...{R}")
            sys.exit(1)

    # 2. Check saved config
    saved = read_config_valoper()
    if saved and VALOPER_RE.match(saved):
        return saved

    # 3. Interactive prompt as last resort
    print(f"\n{BLD}{CYN}  LA TANDA CHAIN - VALIDATOR MONITOR{R}")
    print(f"{DIM}{'─'*50}{R}")
    print(f"\n  {YLW}No validator address configured.{R}")
    print(f"  {DIM}Enter your validator operator address to start monitoring.{R}")
    print(f"  {DIM}Example: ltdvaloper1abc123...{R}\n")

    while True:
        try:
            addr = input(f"  {CYN}Validator address:{R} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n{DIM}Exiting.{R}")
            sys.exit(0)
        if VALOPER_RE.match(addr):
            save_config_valoper(addr)
            print(f"  {GRN}[OK] Saved! Starting monitor...{R}\n")
            return addr
        else:
            print(f"  {RED}[!] Invalid format. Must start with 'ltdvaloper1' followed by 38-58 alphanumeric chars.{R}")

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
def bech32_polymod(values):
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1ffffff) << 5 ^ v
        for i, g in enumerate([0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]):
            if (top >> i) & 1: chk ^= g
    return chk
def bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]
def bech32_create_checksum(hrp, data):
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0,0,0,0,0,0]) ^ 1
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
def convertbits(data, frombits, tobits, pad=True):
    acc = bits = 0; ret = []; maxv = (1 << tobits) - 1
    for value in data:
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad and bits:
        ret.append((acc << (tobits - bits)) & maxv)
    return ret
def bech32_encode(hrp, payload):
    data = convertbits(payload, 8, 5)
    combined = data + bech32_create_checksum(hrp, data)
    return hrp + "1" + "".join(CHARSET[d] for d in combined)

def consensus_bech32_from_hex(cons_hex):
    try:
        return bech32_encode("ltdvalcons", bytes.fromhex(cons_hex))
    except:
        return ""

def validator_pubkey_key(v):
    pk = v.get("consensus_pubkey") or {}
    return pk.get("key") or pk.get("value") or ""

def get_validator_record(valoper):
    d = run_json([BINARY, "query", "staking", "validator", valoper, "--home", NODE_HOME, "--output", "json"], timeout=12)
    if d and "validator" in d: return d["validator"]
    d = http_get(f"{API_BASE}/cosmos/staking/v1beta1/validators/{valoper}", timeout=10)
    return (d or {}).get("validator") or {}

def consensus_hex_from_validator(v):
    key = validator_pubkey_key(v)
    try:
        raw = base64.b64decode(key)
        return hashlib.sha256(raw).digest()[:20].hex().upper()
    except:
        return ""

def signing_start_height(cons_bech32):
    if not cons_bech32: return 0
    d = http_get(f"{API_BASE}/cosmos/slashing/v1beta1/signing_infos/{cons_bech32}", timeout=10)
    si = (d or {}).get("val_signing_info") or {}
    try: return int(si.get("start_height", 0))
    except: return 0

# --- Resolve VALOPER at startup ---
VALOPER = resolve_valoper()
print(f"{DIM}  Attaching to validator: {CYN}{VALOPER}{R}")
_validator_record = get_validator_record(VALOPER) if VALOPER else {}
CONS_HEX = consensus_hex_from_validator(_validator_record)
CONS_BECH32 = consensus_bech32_from_hex(CONS_HEX)
VAL_START_H = signing_start_height(CONS_BECH32)

def get_local_status():
    try:
        r   = subprocess.run([BINARY, "status", "--home", NODE_HOME], capture_output=True, text=True, timeout=6)
        raw = r.stdout.strip() or r.stderr.strip()
        d   = json.loads(raw)
        si  = d.get("sync_info") or d.get("SyncInfo") or {}
        vi  = d.get("validator_info") or d.get("ValidatorInfo") or {}
        return {"ok": True, "local": int(si.get("latest_block_height", 0)), "block_time": si.get("latest_block_time", ""), "catching_up": bool(si.get("catching_up", True)), "voting_power": vi.get("voting_power", "-")}
    except Exception as e:
        return {"ok": False, "error": str(e), "local": 0, "catching_up": True, "voting_power": "-"}

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

def fmt_n(n): return f"{int(n):,}".replace(",", ".") if n is not None else "-"
def fmt_ltd(utld): return f"{utld/1000000:,.2f} LTD".replace(",", ".")
def fmt_dur(sec):
    if sec is None or sec < 0: return "-"
    sec = int(sec)
    if sec < 60: return f"{sec}s"
    if sec < 3600: return f"{sec//60}m {sec%60}s"
    h = sec // 3600; m = (sec % 3600) // 60
    return f"{h//24}d {h%24}j {m}m" if h >= 24 else f"{h}j {m}m"
def fmt_blktime(iso): return iso[:19].replace("T", " ") if iso else "-"
def pbar(pct, width=44, col=None):
    pct = max(0.0, min(100.0, pct)); filled = int(width * pct / 100)
    return (col or (GRN if pct >= 99.9 else YLW if pct >= 85 else CYN)) + "#" * filled + DIM + "." * (width - filled) + R
def score_col(s): return GRN if s >= 95 else YLW if s >= 80 else RED

history = deque(maxlen=HISTORY_LEN); logs = deque(maxlen=60); start_ts = time.time(); net_src = "-"
def add_log(msg, lvl="INFO"):
    logs.appendleft(f"{DIM}{datetime.now().strftime('%H:%M:%S')}{R} {({'OK': GRN, 'WARN': YLW, 'ERR': RED, 'INFO': BLU}.get(lvl, DIM))}[{lvl:4}]{R} {msg}")

def val_status_label(status_str):
    """Convert BOND_STATUS_* to a readable colored label."""
    s = (status_str or "").upper()
    if "BONDED" in s and "UNBONDING" not in s and "UNBONDED" not in s:
        return f"{GRN}{BLD}ACTIVE{R}"
    elif "UNBONDING" in s:
        return f"{YLW}{BLD}UNBONDING{R}"
    elif "UNBONDED" in s:
        return f"{RED}{BLD}UNBONDED{R}"
    return f"{DIM}UNKNOWN{R}"

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
    
    node_status = f"{RED}{BLD}[ERROR]{R}" if has_err else f"{GRN}{BLD}[SYNCED]{R}" if not catching else f"{YLW}{BLD}[SYNCING]{R}"
    with _sc["lock"]: signed, missed, val_start, b_done, b_pct = _sc["signed"], _sc["missed"], _sc["val_start"], _sc["backfill_done"], _sc["backfill_pct"]
    score = calc_scores(signed, missed, local, net_h)
    total_blocks = signed + missed

    # Fetch validator on-chain info
    vinfo = get_validator_info()
    sinfo = get_slash_info()
    dinfo = get_delegations()
    
    clr()
    pad = max(0, (W - 54) // 2)
    print(f"\n{BLD}{CYN}{' '*pad}  VALIDATOR - LA TANDA CHAIN MONITOR  {R}\n{DIM}{box(W)}{R}")
    print(f"  {node_status}   {DIM}monitor uptime:{R} {WHT}{fmt_dur(time.time()-start_ts)}{R}   {DIM}peers:{R} {WHT}{peers or '-'}{R}\n{DIM}{box(W)}{R}\n")

    # === VALIDATOR IDENTITY ===
    print(f"  {BLD}{BLU}> VALIDATOR{R}\n  {DIM}{'-'*52}{R}")
    short_valoper = VALOPER[:20] + "..." + VALOPER[-8:] if len(VALOPER) > 32 else VALOPER
    print(f"  {DIM}{'Address:':<16}{R}{CYN}{short_valoper}{R}")
    if CONS_HEX:
        print(f"  {DIM}{'Consensus Hex:':<16}{R}{DIM}{CONS_HEX[:16]}...{R}")
    else:
        print(f"  {DIM}{'Consensus Hex:':<16}{R}{RED}NOT FOUND{R}  {DIM}(cannot track signing){R}")
    if vinfo.get("ok"):
        vstatus = val_status_label(vinfo.get("status", ""))
        jailed = vinfo.get("jailed", False)
        jail_label = f"  {RED}{BLD}[JAILED]{R}" if jailed else ""
        tokens_fmt = fmt_ltd(vinfo.get("tokens", 0))
        commission = vinfo.get("commission", 0)
        print(f"  {DIM}{'Status:':<16}{R}{vstatus}{jail_label}")
        print(f"  {DIM}{'Total Stake:':<16}{R}{WHT}{tokens_fmt}{R}   {DIM}Commission: {commission:.1f}%{R}")
    else:
        print(f"  {DIM}{'Status:':<16}{R}{RED}Unable to fetch validator info{R}")
    if dinfo.get("ok"):
        print(f"  {DIM}{'Delegators:':<16}{R}{WHT}{dinfo['count']}{R}   {DIM}Total: {fmt_ltd(dinfo['total'])}{R}")
    print()

    # === VALIDATOR SCORE ===
    print(f"  {BLD}{BLU}> SIGNING PERFORMANCE{R}\n  {DIM}{'-'*52}{R}")
    print(f"  {DIM}{'Final Score:':<16}{R}{score_col(score[2])}{BLD}{score[2]:.2f}/100{R}   {DIM}(uptime {score[0]:.1f}% x0.6 + sync {score[1]:.1f}% x0.4){R}")
    print(f"  {pbar(score[2], W-6, score_col(score[2]))}")
    print(f"  {DIM}{'Signed:':<16}{R}{GRN}{fmt_n(signed)}{R}   {DIM}Missed:{R} {RED if missed > 0 else DIM}{fmt_n(missed)}{R}   {DIM}Total: {fmt_n(total_blocks)}{R}")
    if sinfo.get("ok"):
        mc = sinfo.get("missed_counter", 0)
        tomb = sinfo.get("tombstoned", False)
        mc_col = RED if mc > 50 else YLW if mc > 10 else GRN
        print(f"  {DIM}{'Missed (chain):':<16}{R}{mc_col}{mc}{R}   {DIM}Tombstoned:{R} {'${RED}YES' if tomb else f'{GRN}No'}{R}")
    if not b_done:
        print(f"  {DIM}{'Backfill:':<16}{R}{YLW}{b_pct:.1f}%{R} {DIM}(scanning historical blocks...){R}")
    print()

    # === NODE SYNC ===
    print(f"  {BLD}{BLU}> NODE SYNC{R}\n  {DIM}{'-'*52}{R}")
    print(f"  {DIM}{'Block Lokal:':<16}{R}{CYN}{BLD}{fmt_n(local)}{R}   {DIM}Sisa: {fmt_n(remaining)}{R}")
    print(f"  {pbar(pct_sync, W-14)}  {BLD}{pct_sync:.2f}%{R}\n")
    
    print(f"  {DIM}{'-'*4} Log {'-'*(W-12)}{R}")
    for line in list(logs)[:LOG_LINES]: print(f"  {line}")
    print(f"\n{DIM}{box(W)}{R}\n  {DIM}Ctrl+C keluar | latmon attach to re-attach{R}\n")

def main():
    global net_src
    # Startup validation logging
    if not CONS_HEX:
        add_log(f"WARN: Could not derive consensus key for {VALOPER[:24]}...", "WARN")
        add_log("Signing detection will NOT work without consensus key", "ERR")
    else:
        add_log(f"Validator: {VALOPER[:24]}... | Cons: {CONS_HEX[:12]}...", "OK")
    if VAL_START_H > 0:
        add_log(f"Signing start height: #{VAL_START_H}", "OK")
    else:
        add_log("Could not determine signing start height", "WARN")
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
                if nh: net_h, net_src, prev_net = nh, src or "-", nh
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
CONFIG_DIR="\$HOME/.latandad-monitor"
CONFIG_FILE="\$CONFIG_DIR/monitor.env"
VALOPER_RE='^ltdvaloper1[a-z0-9]{38,58}\$'

get_saved_valoper() {
    [[ -f "\$CONFIG_FILE" ]] && grep -oP '^VALOPER=\K.*' "\$CONFIG_FILE" 2>/dev/null || echo ""
}

case "\$1" in
  stop) screen -XS \$SCREEN_NAME quit 2>/dev/null && echo "Monitor dihentikan." || echo "Tidak ada session aktif." ;;
  attach|log) screen -r \$SCREEN_NAME ;;
  status) screen -list | grep \$SCREEN_NAME || echo "Monitor tidak berjalan." ;;
  restart)
    VALOPER_ADDR="\${2:-\$(get_saved_valoper)}"
    screen -XS \$SCREEN_NAME quit 2>/dev/null; sleep 1
    if [[ -n "\$VALOPER_ADDR" ]]; then
      screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH "\$VALOPER_ADDR"
    else
      screen -S \$SCREEN_NAME python3 \$MONITOR_PATH
    fi
    echo -e "\033[32m[OK] Monitor di-restart.\033[0m"
    ;;
  set)
    # latmon set <valoper_address> - save address without starting
    if [[ -z "\$2" ]] || [[ ! "\$2" =~ \$VALOPER_RE ]]; then
      echo -e "\033[31m[!] Usage: latmon set ltdvaloper1...\033[0m"
      exit 1
    fi
    mkdir -p "\$CONFIG_DIR"
    printf 'VALOPER=%s\n' "\$2" > "\$CONFIG_FILE"
    echo -e "\033[32m[OK] Validator address saved: \$2\033[0m"
    echo -e "     Run 'latmon' to start monitoring."
    ;;
  *)
    # Determine valoper: positional arg > saved config > interactive prompt
    VALOPER_ADDR="\${1:-}"

    if screen -list 2>/dev/null | grep -q "\$SCREEN_NAME"; then
      echo -e "\033[33m[!] Monitor sudah berjalan.\033[0m"
      echo -e "    Attach  : latmon attach  (or screen -r \$SCREEN_NAME)"
      echo -e "    Stop    : latmon stop"
      echo -e "    Restart : latmon restart [ltdvaloper1...]"
      exit 0
    fi

    if [[ -n "\$VALOPER_ADDR" ]]; then
      # Address provided as argument
      if [[ ! "\$VALOPER_ADDR" =~ \$VALOPER_RE ]]; then
        echo -e "\033[31m[!] Invalid validator address format.\033[0m"
        echo -e "    Expected: ltdvaloper1..."
        exit 1
      fi
      echo -e "\033[32m[OK] Memulai monitor untuk: \$VALOPER_ADDR\033[0m"
      screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH "\$VALOPER_ADDR"
    else
      # No argument - Python script will prompt or read config
      SAVED=\$(get_saved_valoper)
      if [[ -n "\$SAVED" ]] && [[ "\$SAVED" =~ \$VALOPER_RE ]]; then
        echo -e "\033[32m[OK] Memulai monitor untuk: \$SAVED\033[0m"
        screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH "\$SAVED"
      else
        echo -e "\033[33m[!] No validator address configured.\033[0m"
        echo -e "\n\033[36mUsage:\033[0m"
        echo -e "  latmon ltdvaloper1...     Start monitor with validator address"
        echo -e "  latmon set ltdvaloper1... Save address for future use"
        echo -e "  latmon attach             Re-attach to running monitor"
        echo -e "  latmon stop               Stop the monitor"
        echo -e "  latmon restart            Restart the monitor"
        echo -e ""
        # Interactive fallback: ask for address
        read -p "Enter your validator operator address: " VALOPER_ADDR
        if [[ ! "\$VALOPER_ADDR" =~ \$VALOPER_RE ]]; then
          echo -e "\033[31m[!] Invalid address format. Exiting.\033[0m"
          exit 1
        fi
        mkdir -p "\$CONFIG_DIR"
        printf 'VALOPER=%s\n' "\$VALOPER_ADDR" > "\$CONFIG_FILE"
        echo -e "\033[32m[OK] Address saved & starting monitor...\033[0m"
        screen -dmS \$SCREEN_NAME python3 \$MONITOR_PATH "\$VALOPER_ADDR"
      fi
    fi

    sleep 0.8
    if screen -list 2>/dev/null | grep -q "\$SCREEN_NAME"; then
      echo -e "\033[32m[OK] Berjalan! Attach dengan:\033[0m  latmon attach"
    else
      echo -e "\033[31m[FAIL] Gagal start. Coba manual:\033[0m  python3 \$MONITOR_PATH"
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
    echo -e "${RED}       DANGER: CLEAN UNINSTALLATION           ${NC}"
    echo -e "${RED}======================================================${NC}"
    echo -e "This will completely remove the La Tanda Node, PM2 routines,"
    echo -e "Blockchain Data, and ${RED}ALL YOUR SAVED WALLETS${NC} from this machine."
    echo ""
    echo -e "${YELLOW}CRITICAL REMINDER:${NC}"
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

    echo -e "${GREEN}Uninstallation Complete!${NC}"
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
        echo "5) Validator Rewards (Check / Claim / Restake)"
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
            5) manage_validator_rewards ;;
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
    send) check_binary && send_ltd ;;
    validator) create_validator ;;
    rewards) manage_validator_rewards ;;
    gov) manage_gov ;;
    logs) show_logs ;;
    monitor) 
        if command -v latmon &> /dev/null; then
            latmon attach || latmon "${2:-}"
        else
            echo -e "${RED}Monitor is not installed. Run 'latman' and choose option 8 to install it.${NC}"
        fi
        ;;
    update) self_update "${2:-}" ;;
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
        echo "    rewards     - Check or claim validator rewards"
        echo "    gov         - Manage governance proposals"
        echo "    logs        - View live pm2 logs"
        echo "    monitor [addr] - Attach or start monitor (optionally with validator address)"
        echo "    update [--force] - Check latest script and auto-update latman"
        echo "    install     - Install node and run with PM2"
        echo "    uninstall   - Cleanly wipe the node, data, and CLI manager"
        ;;
    *)
        show_interactive_menu
        ;;
esac
