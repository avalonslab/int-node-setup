#!/bin/bash

# Script to register a INT validator node
#
# Discussion, issues and change requests at:
#   https://t.me/INTDevelopment
#
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/avalonslab/int-misc/master/register_validator_testnet4.sh)

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

KEYSTORE_PATH="${HOME}/.intchain/testnet/keystore/"
RPC_URL="http://localhost:8555/testnet"
#SECURITY_DEPOSIT="0xDE0B6B3A7640000" # 1 INT
#BALANCE_NEEDED="0xF43FC2C04EE0000" # 1.1 INT
SECURITY_DEPOSIT="0xD3C21BCECCEDA1000000" # 1000000 INT
BALANCE_NEEDED="0xD3C229AF83A148640000" # 1000001 INT
PREFIX="0x"
COMMISSION=10

generate_wallet_data () {
cat << EOF
{
    "jsonrpc":"2.0",
    "method":"personal_newAccount",
    "params":["${WALLET_PASSWORD}"],
    "id":1
}
EOF
}

generate_blskey_data () {
cat << EOF
{
    "jsonrpc":"2.0",
    "method":"int_createValidator",
    "params":["${WALLET_ADDRESS}"],
    "id":1
}
EOF
}

generate_balance_data () {
    cat << EOF
{
    "jsonrpc":"2.0",
    "method":"int_getBalance",
    "params":["${WALLET_ADDRESS}",
               "latest"],
    "id":1
}
EOF
}

generate_unlock_data () {
    cat << EOF
{
    "jsonrpc":"2.0",
    "method":"personal_unlockAccount",
    "params":["${WALLET_ADDRESS}",
              "${WALLET_PASSWORD}",
              3600],
    "id":1
}
EOF
}

generate_sign_data () {
  cat << EOF
{
    "jsonrpc":"2.0",
    "method":"int_signAddress",
    "params":["${WALLET_ADDRESS}",
              "${SIGN_HASH}"],
    "id":1
}
EOF
}

generate_validator_data () {
  cat << EOF
{
    "jsonrpc":"2.0",
    "method":"int_register",
    "params":["${WALLET_ADDRESS}",
              "${SECURITY_DEPOSIT}",
              "${CONSENSUS_PUB_KEY}",
              "${SIGNATURE}",
               ${COMMISSION}],
    "id":1
}
EOF
}

check_password () {
    while [ "${WALLET_PASSWORD}" != "${WALLET_PASSWORD_CONFIRM}" ]; do
        echo
        echo "Your password does not match, please try again."
        read -sp "Password: " WALLET_PASSWORD </dev/tty
        echo
        echo "# Please confirm your password!"
        read -sp "Password: " WALLET_PASSWORD_CONFIRM </dev/tty
        echo
    done
}

create_new_wallet () {
    echo "# Create a new wallet, you need to choose a strong password!"
    read -sp "Password: " WALLET_PASSWORD </dev/tty
    echo
    echo "# Please confirm your password!"
    read -sp "Password: " WALLET_PASSWORD_CONFIRM </dev/tty
    echo

    check_password

    WALLET_ADDRESS=$(curl -X POST --silent --data "$(generate_wallet_data)" --header 'Content-Type: application/json;' ${RPC_URL} | jq --raw-output '.result')
    if [ -z "${WALLET_ADDRESS}" ]; then
        echo "Could not create a new wallet, exiting"
        exit 1
    fi
    echo "Wallet Address: ${WALLET_ADDRESS}"
}

create_bls_key () {
    if [ -e "${HOME}/.intchain/testnet/priv_validator.json" ]; then
        PRIV_VALIDATOR_DATA=$(cat "${HOME}/.intchain/testnet/priv_validator.json")
    else
        PRIV_VALIDATOR_DATA=$($(command -v intchain) --testnet create-validator ${WALLET_ADDRESS})
    fi

    if [ -z "${PRIV_VALIDATOR_DATA}" ]; then
        echo "Could not create BLS keys > exiting"
        exit 1
    fi

    CONSENSUS_PRIV_KEY=$(echo $PRIV_VALIDATOR_DATA | jq --raw-output '.consensus_priv_key' | grep -o '".*"' | tr -d '"')
    CONSENSUS_PUB_KEY=$(echo $PRIV_VALIDATOR_DATA | jq --raw-output '.consensus_pub_key' | grep -o '".*"' | tr -d '"')
    echo "BLS Private Key: ${CONSENSUS_PRIV_KEY}"
    echo "BLS Public Key: ${CONSENSUS_PUB_KEY}"
}

unlock_wallet () {
    UNLOCK=$(curl -X POST --silent --data "$(generate_unlock_data)" --header 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
    if [ -z "${UNLOCK}" ] || [ "${UNLOCK}" == "false" ]; then
        echo "Could not unlock your wallet, exiting"
        exit 1
    fi
}

sign_address () {
    SIGN_HASH="${PREFIX}${CONSENSUS_PRIV_KEY}"
    SIGNATURE=$(curl -X POST --silent --data "$(generate_sign_data)" --header 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
    if [ -z "${SIGNATURE}" ]; then
        echo "Could not sign your address, exiting"
        exit 1
    fi
    echo "Signature: ${SIGNATURE}"
}

register_validator () {
    REGISTER_HASH=$(curl -X POST --silent --data "$(generate_validator_data)" --header 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
    if [ -z "${REGISTER_HASH}" ]; then
        echo "Could not register your validator, exiting"
        exit 1
    fi
    echo "Registration Hash: ${REGISTER_HASH}"
}

enough_balance () {
    WALLET_BALANCE=$(curl -X POST --silent --data "$(generate_balance_data)" --header 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
    if [ -z "${WALLET_BALANCE}" ] || [ $((WALLET_BALANCE)) -lt "$((BALANCE_NEEDED))" ]; then
        return 1
    fi
    echo "Wallet Balance: $(expr $((WALLET_BALANCE)) / 1000000000000000000) INT"
}

backup_node () {
    mkdir -p "${HOME}/backup"
    cp "${KEYSTORE_PATH}/UTC"* "${HOME}/backup/"
    cp "${HOME}/.intchain/testnet/priv_validator.json" "${HOME}/backup/"
    echo
    echo "Your priv_validator.json and keystore files were backuped to: ${HOME}/backup"
    echo "Please download these files and keep them somewhere safe. You need these files to restore your node and to access your wallet."
    echo
}

check_existing_wallets () {
    echo "The following wallets were found; select one:"

    PS3="Use number to select a wallet or 'stop' to cancel: "

    select filename in ${HOME}/.intchain/testnet/keystore/UTC*
    do
        if [ "$REPLY" == stop ]; then
            exit
        fi

        if [ "$filename" == "" ]; then
            echo "'$REPLY' is not a valid number"
            continue
        fi

        WALLET_ADDRESS=$(echo ${filename} | sed 's|.*--||')

        echo "# Please type in your wallet password!"
        read -sp "Password: " WALLET_PASSWORD </dev/tty
        echo
        echo "# Please confirm your password!"
        read -sp "Password: " WALLET_PASSWORD_CONFIRM </dev/tty
        echo

        check_password

        echo "Wallet Address: ${WALLET_ADDRESS}"
        break
    done
}

if [[ -n $(find ${KEYSTORE_PATH} -name 'UTC*') ]]; then
    check_existing_wallets
else
    create_new_wallet
fi

if [[ -z "${WALLET_ADDRESS}" ]]; then
    echo "Could not get the address of your wallet > exiting"
    exit 1
else
    #if ! enough_balance; then
    #    echo "There is not enough INT in your wallet ${WALLET_ADDRESS}, please deposit at least 1m + 1 INT and start this script again." # $(expr $((BALANCE_NEEDED)) / 1000000000000000000)
    #    exit 1
    #else
        create_bls_key
        sign_address
        unlock_wallet
        register_validator
        backup_node
        systemctl restart intchain >> /dev/null 2>&1
    #fi
fi
