#!/usr/bin/env bash
set -euo pipefail

# Region pinned to Central US for consistency with your timezone
LOCATION="centralus"

# Resource names
RG="fedlin-lab-rg"
LAW="fedlin-law"
DCR="fedlin-dcr"
VNET="fedlin-vnet"
SUBNET="fedlin-subnet"
NSG="fedlin-nsg"
VMNAME="fedlin-cisvm"
ADMINUSER="azureuser"
IMAGEREF="almalinux:almalinux:9-gen2:latest"
SIZE="Standard_B1s"

# Guardrails: fail if region/size are wrong
[ "${LOCATION}" = "centralus" ] || { echo "ERROR: LOCATION must be centralus"; exit 2; }
[ "${SIZE}" = "Standard_B1s" ] || { echo "ERROR: SIZE must be Standard_B1s"; exit 2; }

# Resource Group
az group create -n "$RG" -l "$LOCATION" -o none

# Log Analytics
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" -o none

# Networking: VNet/Subnet
az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.10.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefix 10.10.1.0/24 -o none

# NSG with least-privileged inbound (22 only from a single public IP, 443 open)
MYIP=$(curl -s https://ifconfig.me || echo "0.0.0.0")
az network nsg create -g "$RG" -n "$NSG" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow_ssh_myip \
  --priority 1000 --access Allow --protocol Tcp --direction Inbound \
  --source-address-prefixes "${MYIP}/32" --destination-port-ranges 22 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow_https \
  --priority 1010 --access Allow --protocol Tcp --direction Inbound \
  --source-address-prefixes "*" --destination-port-ranges 443 -o none

# NIC
NIC_ID=$(az network nic create -g "$RG" -n "${VMNAME}-nic" \
  --vnet-name "$VNET" --subnet "$SUBNET" --network-security-group "$NSG" \
  --query "NewNIC.id" -o tsv)

# SSH key (pipeline-safe: generate if missing on the runner)
SSH_PUB="$HOME/.ssh/fedlin_azure.pub"
if [ ! -f "$SSH_PUB" ]; then
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$HOME/.ssh/fedlin_azure" -N "" -q
fi

# VM (Rocky 9, B1s)
az vm create -g "$RG" -n "$VMNAME" \
  --image "$IMAGEREF" --size "$SIZE" \
  --admin-username "$ADMINUSER" \
  --ssh-key-values "$SSH_PUB" \
  --nics "$NIC_ID" --public-ip-sku Basic \
  --storage-sku Standard_LRS -o none

# AMA + DCR to send syslog to LAW (authpriv, daemon)
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)
az vm extension set --publisher Microsoft.Azure.Monitor --name AzureMonitorLinuxAgent \
  --resource-group "$RG" --vm-name "$VMNAME" -o none

cat > /tmp/dcr.json <<JSON
{
  "location": "$LOCATION",
  "properties": {
    "dataSources": { "syslog": [ { "name": "syslogSource",
      "streams": ["Microsoft-Syslog"],
      "facilityNames": ["authpriv","daemon"],
      "logLevels": ["Info","Warning","Error","Critical","Alert","Emergency","Debug","Notice"] } ] },
    "destinations": { "logAnalytics": [ { "name": "toLAW", "workspaceResourceId": "$LAW_ID" } ] },
    "dataFlows": [ { "streams": ["Microsoft-Syslog"], "destinations": ["toLAW"] } ]
  }
}
JSON

az monitor data-collection rule create -g "$RG" -n "$DCR" --location "$LOCATION" \
  --rule-file /tmp/dcr.json -o none

VM_ID=$(az vm show -g "$RG" -n "$VMNAME" --query id -o tsv)
DCR_ID=$(az monitor data-collection rule show -g "$RG" -n "$DCR" --query id -o tsv)
az monitor data-collection rule association create --name "${DCR}-assoc" \
  --rule-id "$DCR_ID" --resource "$VM_ID" -o none

# Output public IP (used by next project)
IP=$(az vm list-ip-addresses -g "$RG" -n "$VMNAME" --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)
echo "PUBLIC_IP=$IP"
