# La Tanda Chain Node Manager

This repository provides an interactive, easy-to-use manager for deploying and maintaining a La Tanda Chain (`latanda-testnet-1`) node. It acts as an interactive command-line dashboard that simplifies all standard Cosmos SDK operations for node operators.

## Requirements

- OS: Linux (Ubuntu 22.04 or 24.04 recommended)
- Hardware: 2 CPU, 4GB RAM, 50GB SSD minimum (4 CPU, 8GB RAM, 100GB SSD recommended)

## Quick Start Installation

Run this one-line command sequence in your terminal to securely install the interactive CLI (`latman`) system-wide:

```bash
sudo wget -q https://raw.githubusercontent.com/skyhazee/La-Tanda-Chain-Testnet/main/latanda.sh -O /usr/local/bin/latman && sudo chmod +x /usr/local/bin/latman && latman
```

## Global Subcommands

This dashboard can be launched fully interactively by just typing `latman`, but it also supports direct quick-actions via subcommands from anywhere in your server:

- `latman status` : Check node sync progress and validation status.
- `latman wallet` : Jump straight into wallet creation & balance checker.
- `latman validator` : Create a validator instantly.
- `latman rewards` : Check validator rewards with auto-detected validator wallet/address.
- `latman gov`   : View beautifully formatted active proposals and cast your vote.
- `latman logs`   : Stream real-time node outputs via PM2.
- `latman monitor`: Attach to the advanced Python monitor UI.
- `latman uninstall`: Safely stop processes and wipe the node completely.

## Step-by-Step Guide for Beginners

### 1. Install and Sync Your Node
- Launch the interactive manager using `latman`.
- Select **Option 1 (Install Node & Run)**. The script will automatically download the required dependencies, Go, the `latandad` binary, and set up the genesis file. It will start the node in the background using PM2.
- Wait for the node to fully catch up to the network. Check the progress by selecting **Option 2 (Check Node Status)**. **Do not proceed** to validator creation until the "Catching Up" status shows as "False".

### 2. Set Up a Wallet
- Once your node is synced, open the manager and select **Option 3 (Wallet Management)**, then choose **Option 1 (Create New Wallet)**.
- Input a wallet name and securely back up your 24-word mnemonic phrase.
- Copy your generated wallet address (starts with `ltd1...`).
- To check balance, use **Option 4 (Check Wallet Balance)** and choose either:
  - manual address input, or
  - select from saved wallets.
- Join the official La Tanda Discord server and post your address in the appropriate channel to request testnet funds (LTD tokens) needed to become a validator.

### 3. Join as a Validator
- After your wallet is funded, open the manager and select **Option 4 (Create Validator)**.
- The script automatically handles the complex `validator.json` configuration for you, pulling your node's public key internally and configuring standard parameters (10% commission rate, correct fees, minimum self-delegation).
- Provide your wallet name and your desired validator moniker (public name).
- The transaction will be securely broadcasted, and you should now be active on the network.

### 4. Check Validator Rewards
After your validator is active, you can check rewards directly from the manager:

- Use **Option 5 (Check Validator Rewards)** from the main menu, or run `latman rewards`.
- The script auto-detects the registered validator wallet/address from your local keyring.
- Reward query command used:

```bash
latandad query distribution rewards <auto-detected-ltd-address> --home ~/.latanda
```

### 5. Advanced Monitor Setup
This script includes an advanced Python-based dashboard providing real-time analytics on your validator's performance, including uptime, signing rate, block sync score, and backfill scanning.

- To configure it, select **Option 8 (Install & Run Advanced Monitor)** from the main menu.
- The script will configure everything and create a native command on your server called `latmon`.
- To view the dashboard, return to your normal server terminal and type: `screen -r latmon`
- To safely detach from the dashboard without closing it, press **Ctrl+A** followed by **D**.
- If you need to stop or restart the monitor process, you can use the commands `latmon stop` or `latmon restart`.

## Community & Resources

For testnet participation, testnet token requests, and troubleshooting, join the La Tanda community:
- Discord: https://discord.gg/Ve9M2ZSYC2
- Telegram: https://t.me/latandahn
- Explorer: https://latanda.online/chain/

License: MIT
