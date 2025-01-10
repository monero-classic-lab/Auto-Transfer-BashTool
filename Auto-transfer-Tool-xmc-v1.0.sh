#!/bin/bash

# Configurable variables
RPC_URL="http://127.0.0.1:18182/json_rpc" # YOUR MONEROCLASSIC RPC
DESTINATION_ADDRESS=${1:-"YOUR_XMC_ADDRESS"}  # Accept from command line
TRANSFER_AMOUNT=${2:-300}  # Default to 300 XMC
TRANSACTIONS_PER_BLOCK=${3:-5}  # Default to 5 transactions per block
LOG_FILE="transfer_log.txt"

# Convert XMC to piconero
AMOUNT_PICONERO=$(echo "$TRANSFER_AMOUNT * (10^12)" | bc)

# Function: Log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function: Get balance
get_balance() {
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","id":"0","method":"get_balance"}' "$RPC_URL")
    if [[ -z "$RESPONSE" || "$RESPONSE" == "null" ]]; then
        log "Error: Failed to connect to RPC server in get_balance."
        exit 1
    fi
    echo "$RESPONSE"
    AVAILABLE_BALANCE=$(echo "$RESPONSE" | jq -r '.result.balance')
    if [[ "$AVAILABLE_BALANCE" == "null" ]]; then
        log "Error: Failed to parse balance response."
        exit 1
    fi
    #echo "$AVAILABLE_BALANCE"
}

# Function: Get block height
get_block_height() {
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","id":"0","method":"get_height"}' "$RPC_URL")
    if [[ -z "$RESPONSE" || "$RESPONSE" == "null" ]]; then
        log "Error: Failed to connect to RPC server in get_block_height."
        exit 1
    fi
    #echo "$RESPONSE"
    HEIGHT=$(echo "$RESPONSE" | jq -r '.result.height')
    if [[ "$HEIGHT" == "null" ]]; then
        log "Error: Failed to parse block height response."
        exit 1
    fi
    echo "$HEIGHT"
}

# Function: Send transfer
send_transfer() {
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","id":"0","method":"transfer","params":{"destinations":[{"amount":'$AMOUNT_PICONERO',"address":"'$DESTINATION_ADDRESS'"}],"priority":2,"ring_size":11}}' "$RPC_URL")
    if [[ -z "$RESPONSE" || "$RESPONSE" == "null" ]]; then
        log "Error: Failed to connect to RPC server in send_transfer."
        return 1
    fi

    ERROR=$(echo "$RESPONSE" | jq -r '.error.message')
    if [[ "$ERROR" != "null" ]]; then
        log "RPC error in send_transfer: $ERROR"
        return 1
    fi

    TX_HASH=$(echo "$RESPONSE" | jq -r '.result.tx_hash')
    if [[ "$TX_HASH" != "null" ]]; then
        log "Transaction succeeded! txHash: $TX_HASH"
        return 0
    else
        log "Transaction failed! Response: $RESPONSE"
        return 1
    fi
}

# Initialize last block height
LAST_BLOCK_HEIGHT=$(get_block_height)

# Main loop
while true; do
    CURRENT_BLOCK_HEIGHT=$(get_block_height)
    log "--current block height: $CURRENT_BLOCK_HEIGHT"

    if [[ "$CURRENT_BLOCK_HEIGHT" -gt "$LAST_BLOCK_HEIGHT" ]]; then
        log "New block detected: $CURRENT_BLOCK_HEIGHT"

        AVAILABLE_BALANCE=$(get_balance)
        REQUIRED_BALANCE=$(echo "$AMOUNT_PICONERO * $TRANSACTIONS_PER_BLOCK" | bc)

        if (( $(echo "$AVAILABLE_BALANCE < $REQUIRED_BALANCE" | bc) )); then
            log "Insufficient balance. Current balance: $(echo "$AVAILABLE_BALANCE / (10^12)" | bc -l) XMC"
            exit 1
        fi

        for ((i=1; i<=TRANSACTIONS_PER_BLOCK; i++)); do
            if ! send_transfer; then
                log "Retrying transaction $i..."
                sleep 2
                send_transfer || exit 1
            fi
            sleep 1
        done

        LAST_BLOCK_HEIGHT=$CURRENT_BLOCK_HEIGHT
    fi

    sleep 5
done
