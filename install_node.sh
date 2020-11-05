#!/bin/bash

# Discussion, issues and change requests at:
#   https://t.me/INTDevelopment
#
# Script to install the INT testnet onto a
# Debian or Ubuntu system.
#
# Usage: wget -qO- https://raw.githubusercontent.com/avalonslab/int-misc/master/install_testnet4.sh | bash -

cat << 'FIG'
 _  __    _     ____   __  __     _
| |/ /   / \   |  _ \ |  \/  |   / \
| ' /   / _ \  | |_) || |\/| |  / _ \
| . \  / ___ \ |  _ < | |  | | / ___ \
|_|\_\/_/   \_\|_| \_\|_|  |_|/_/   \_\

 INT12kokQgcogRnGGguN6TpTfHY4FV8YrdQSq
FIG

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

LOG_FILE="${HOME}/install_int_node.log"
GO_VERSION="1.15.3"
#CHAIN_ID="intchain"
CHAIN_ID="testnet"
RPC_PORT="8555"
RPC_URL="http://localhost:{RPC_PORT}/${CHAIN_ID}"
#SNAPSHOT="https://files.avalonslab.dev/testnet4_bootstrap.tar.gz"

#if [ "$1" == "testnet" ]; then
#    CHAIN_ID="testnet"
#fi

echo
echo "Checking user and access permissions"
if [ $(whoami) != 'root' ]; then
    echo "Please login as 'root' user, the script will now be terminated."
    exit 1
fi

# System Upgrade
echo "System Upgrade, please wait..."
apt update -y >> $LOG_FILE 2>&1
apt upgrade -y >> $LOG_FILE 2>&1

# Dependencies
if ! [ -x "$(command -v curl)" ]; then
    echo "'curl' not found > installing"
    apt install curl -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v wget)" ]; then
    echo "'wget' not found > installing"
    apt install wget -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v jq)" ]; then
    echo "'jq' not found > installing"
    apt install jq -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v gcc)" ]; then
    echo "'gcc' not found > installing"
    apt install gcc -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v g++)" ]; then
    echo "'g++' not found > installing"
    apt install g++ -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v make)" ]; then
    echo "'make' not found > installing"
    apt install make -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v git)" ]; then
    echo "'git' not found > installing"
    apt install git -y >> $LOG_FILE 2>&1
fi
if ! [ -x "$(command -v ufw)" ]; then
    echo "'ufw' not found > installing"
    apt install ufw >> $LOG_FILE 2>&1
fi
if ! [ -d /etc/fail2ban ]; then
    echo "'fail2ban' not found > installing"
    apt install fail2ban -y >> $LOG_FILE 2>&1
    echo "Start 'fail2ban'"
    service fail2ban start >> $LOG_FILE 2>&1
fi

# Firewall Configuration
echo "Configure Firewall"
ufw allow ssh/tcp >> $LOG_FILE 2>&1
ufw limit ssh/tcp >> $LOG_FILE 2>&1
ufw allow 8550/tcp >> $LOG_FILE 2>&1
ufw allow 8550/udp >> $LOG_FILE 2>&1
ufw allow ${RPC_PORT}/tcp >> $LOG_FILE 2>&1
ufw allow ${RPC_PORT}/udp >> $LOG_FILE 2>&1
ufw logging on >> $LOG_FILE 2>&1
ufw --force enable >> $LOG_FILE 2>&1

# Install Golang
echo "Downloading Golang Version ${GO_VERSION}"
wget -q --show-progress "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" -P "/tmp/"
echo "Extracting Golang"
tar -C /usr/local -xzf "/tmp/go${GO_VERSION}.linux-amd64.tar.gz" >> $LOG_FILE 2>&1
mkdir -p "${HOME}/go/bin"
echo "export GOPATH=${HOME}/go" >> "${HOME}/.profile"
echo "export GOBIN=${HOME}/go/bin" >> "${HOME}/.profile"
echo "export PATH=$PATH:${HOME}/go/bin:/usr/local/go/bin" >> "${HOME}/.profile"
source "${HOME}/.profile"

# Install intchain
if [ "${CHAIN_ID}" == "testnet" ]; then
        intchain_exec="intchain --testnet"
        echo "Cloning 'intchain testnet' to '${HOME}/intchain'"
        git clone --branch testnet https://github.com/intfoundation/intchain "${HOME}/intchain" >> $LOG_FILE 2>&1
else
        intchain_exec="intchain"
        echo "Cloning 'intchain mainnet' to '${HOME}/intchain'"
        git clone https://github.com/intfoundation/intchain "${HOME}/intchain" >> $LOG_FILE 2>&1
fi

echo "Compile 'intchain'"
cd "${HOME}/intchain"
make intchain >> $LOG_FILE 2>&1

# Blockchain snapshot
#if [ "${IMPORT_SNAPSHOT}" == "true" ]; then
#    echo "Downloading blockchain snapshot from $SNAPSHOT"
#    wget -q --show-progress "$SNAPSHOT" -P "/tmp/"
#    mkdir -p "${HOME}/.intchain/"
#    echo "Extracting '/tmp/testnet4_bootstrap.tar.gz' to '${HOME}/.intchain/'"
#    tar -C "${HOME}/.intchain/" -xzf "/tmp/testnet4_bootstrap.tar.gz" >> $LOG_FILE 2>&1
#fi

# Systemd setup
echo "Configure '/etc/systemd/system/intchain.service'"
cat << EOF > /etc/systemd/system/intchain.service
[Unit]
Description=INT Node

[Service]
User=root
KillMode=process
KillSignal=SIGINT
WorkingDirectory=${HOME}/intchain
ExecStart=${HOME}/go/bin/$intchain_exec \
--datadir ${HOME}/.intchain \
--rpc \
--rpcapi personal,int,net,web3 \
--rpcport ${RPC_PORT} \
--verbosity 3
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable Node
systemctl daemon-reload
systemctl enable intchain.service >> $LOG_FILE 2>&1
echo "Start intchain.service"
systemctl start intchain.service >> $LOG_FILE 2>&1

# Health Monitor
echo "Setup health monitor '${HOME}/intchain/health_monitor.sh'"
touch "${HOME}/intchain/health_monitor.sh"
chmod +x "${HOME}/intchain/health_monitor.sh"

cat << EOF >> "${HOME}/intchain/health_monitor.sh"
#!/bin/bash
CHAIN_ID="${CHAIN_ID}"
RPC_URL="http://localhost:${RPC_PORT}/${CHAIN_ID}"
EOF

cat << 'EOF' >> "${HOME}/intchain/health_monitor.sh"

timestamp ()
{
    date +"%Y-%m-%d %T"
}

restart_service ()
{
    systemctl daemon-reload

    if systemctl restart intchain.service; then
        echo "$(timestamp) intchain.service: Restart successful"
        sleep 20
    else
        echo "$(timestamp) intchain.service: Restart failure"
        exit 1
    fi
}

echo
status_code=$(timeout 5m curl --silent --write-out %{http_code} ${RPC_URL} --output /dev/null)
if [ "${status_code}" -eq 200 ]; then
    echo "$(timestamp) HTTP-Status: ${status_code} OK"
else
    echo "$(timestamp) HTTP-Status: ${status_code} ERROR > Restarting the node"
    restart_service
fi

sync_status=$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"int_syncing","params":[],"id":1}' -H 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
if [ -n "${sync_status}" -a "${sync_status}" != "false" ]; then
    currentBlock=$(echo ${sync_status} | jq --raw-output '.currentBlock')
    highestBlock=$(echo ${sync_status} | jq --raw-output '.highestBlock')
    echo "$(timestamp) Sync Status: Node is syncing > Block: $((currentBlock))/$((highestBlock))"
    exit 0
fi

current_block_height=$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"int_getBlockByNumber","params":["latest", true],"id":1}' -H 'content-type:application/json;' ${RPC_URL} | jq --raw-output '.result.number')
if [ "${current_block_height}" -ge 0 ]; then

    if [ -e "${HOME}/intchain/old_height" ]; then
	    old_height=$(cat "${HOME}/intchain/old_height")
    else
        old_height=0
    fi

    if [ "$((current_block_height))" -gt "${old_height}" ]; then
        echo "$(timestamp) Current Block Height: $((current_block_height))"
        echo "$((current_block_height))" > "${HOME}/intchain/old_height"
    else
	    echo "$(timestamp) Sync Status: Blockchain stuck at block $((current_block_height)) > Restarting the node"
        restart_service
    fi
else
    echo "$(timestamp) Current Block Height: Cannot fetch current block height"
    exit 1
fi

peers=$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' -H 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
if [ "$((peers))" -ge 0 ]; then
    echo "$(timestamp) Peers: $((peers))"
fi

miner_status=$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"int_mining","params":[],"id":1}' -H 'content-type: application/json;' ${RPC_URL} | jq --raw-output '.result')
if [ "${miner_status}" == "true" ]; then
        echo "$(timestamp) Miner Status: Is mining"
else
        echo "$(timestamp) Miner Status: Is NOT mining"
fi

hdd=$(df -Ph | sed s/%//g | awk '{ if($5 > 90 ) print $0;}' | wc -l)
if [ "${hdd}" -gt 1 ]; then
    echo "$(timestamp) Hard Disc Space: Capacity over 90% > Please expand your storage"
fi

if ! [ -e "${HOME}/.intchain/${CHAIN_ID}/priv_validator.json" ]; then
    echo "$(timestamp) priv_validator.json: Does not exist"
fi
EOF

# Crontab Configuration
echo "Create and import crontab"
echo "*/3 * * * * ${HOME}/intchain/health_monitor.sh >> /var/log/health_monitor.log 2>&1" >> "/tmp/newCrontab"
crontab -u root "/tmp/newCrontab" >> $LOG_FILE 2>&1

echo
echo "##### Installation completed! #####"
echo "If you have found this tutorial useful, please consider delegating some of your votes to the KARMA validator node: INT12kokQgcogRnGGguN6TpTfHY4FV8YrdQSq"
echo
echo "Type 'cat ${LOG_FILE}' to view the install log file."
echo "Type 'journalctl -f -u intchain' to view the log file of your node."
echo "Type 'cat /var/log/health_monitor.log' to view the health monitor log file."
