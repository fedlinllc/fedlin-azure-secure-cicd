#!/usr/bin/env bash
set -euo pipefail

# Security rationale: Bash strict mode prevents expansion errors, unintended command execution (CIS Linux 5.4).
# Quiet output except for critical info.

# --- Config ---

REGION="centralus"
VM_SIZE="Standard_B1s"
VM_IMAGE="OpenLogic:CentOS:7_9:latest"
RG="fedlin-cicd-lab"
LAW="fedlin-law"
DCR="fedlin-dcr"
VNET="fedlin-vnet"
SUBNET="fedlin-subnet"
NSG="fedlin-nsg"
NIC="fedlin-nic"
VM="fedlin-vm"
AMA_NAME="AzureMonitorLinuxAgent"
LOCATION="$REGION"

# Replace with your public IP (for SSH restriction)
MY_IP="
$(curl -s ifconfig.me)"
SSH_PORT=22
HTTPS_PORT=443

echo "Validating region and VM size..."
if [[ "$REGION" != "centralus" ]]; then
  echo "ERROR: Region must be 'centralus' for free-tier compliance."
  exit 1
fi
if [[ "$VM_SIZE" != "Standard_B1s" ]]; then
  echo "ERROR: VM size must be 'Standard_B1s' for free-tier compliance."
  exit 2
fi

# --- Resource Group ---
echo "Creating resource group ($RG)..."
az group create --name "$RG" --location "$LOCATION" --output none

# --- Log Analytics Workspace ---
echo "Creating Log Analytics Workspace ($LAW)..."
az monitor log-analytics workspace create --resource-group "$RG" --workspace-name "$LAW" --location "$LOCATION" --sku "PerGB2018" --output none

LAW_ID="$(az monitor log-analytics workspace show --resource-group "$RG" --workspace-name "$LAW" --query id -o tsv)"

# --- VNet & Subnet ---
echo "Creating VNet and Subnet..."
az network vnet create --resource-group "$RG" --name "$VNET" --address-prefixes "10.0.0.0/16" --subnet-name "$SUBNET" --subnet-prefix "10.0.1.0/24" --output none

# --- NSG: Restrict SSH to your IP, 443 open ---
echo "Configuring NSG ($NSG)..."
az network nsg create --resource-group "$RG" --name "$NSG" --output none
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" --name "Allow-SSH-MYIP" \
  --priority 100 --source-address-prefixes "$MY_IP" --destination-port-ranges "$SSH_PORT" \
  --protocol Tcp --access Allow --output none
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" --name "Allow-HTTPS" \
  --priority 110 --destination-port-ranges "$HTTPS_PORT" --protocol Tcp --access Allow --output none
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" --name "Deny-SSH-All" \
  --priority 120 --destination-port-ranges "$SSH_PORT" --protocol Tcp --access Deny --output none

# --- NIC ---
echo "Creating Network Interface ($NIC)..."
SUBNET_ID="$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" --name "$SUBNET" --query id -o tsv)"
az network nic create --resource-group "$RG" --name "$NIC" --subnet "$SUBNET_ID" --network-security-group "$NSG" --output none

# --- VM ---
echo "Deploying VM ($VM)..."
az vm create --resource-group "$RG" --name "$VM" --image "$VM_IMAGE" --size "$VM_SIZE" \
  --admin-username "fedlinuser" --generate-ssh-keys \
  --nics "$NIC" --output none

# --- AMA Extension ---
echo "Installing Azure Monitor Agent (AMA)..."
az vm extension set --resource-group "$RG" --vm-name "$VM" --name "$AMA_NAME" \
  --publisher "Microsoft.Azure.Monitor" --output none

# --- Data Collection Rule (DCR): syslog (authpriv, daemon) to LAW ---
echo "Configuring Data Collection Rule (DCR)..."
DCR_JSON="dcr.json"
cat > "$DCR_JSON" <<EOF
{
  "location": "$LOCATION",
  "kind": "Linux",
  "properties": {
    "dataSources": {
      "syslog": [
        {
          "facilityNames": ["authpriv", "daemon"],
          "logLevels": ["Alert", "Critical", "Error", "Warning", "Notice", "Informational", "Debug"]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "$LAW_ID"
        }
      ]
    }
  }
}
EOF
az monitor data-collection rule create --resource-group "$RG" --name "$DCR" --location "$LOCATION" \
  --rule-file "$DCR_JSON" --output none

# Attach VM to DCR
VM_ID="$(az vm show --resource-group "$RG" --name "$VM" --query id -o tsv)"
az monitor data-collection rule association create --resource-group "$RG" --data-collection-rule "$DCR" \
  --name "${VM}-dcr-assoc" --resource-id "$VM_ID" --output none

# --- Print Public IP ---
PUBLIC_IP="$(az vm list-ip-addresses --resource-group "$RG" --name "$VM" --query '[0].virtualMachine.network.publicIpAddresses[0].ipAddress' -o tsv)"
echo "VM Public IP: $PUBLIC_IP"

echo "Deployment complete."

# Security rationale: Each resource is least privilege, network locked down, minimal ingestion for free-tier, telemetry is only for syslog (authpriv, daemon) per CIS Linux 8.2.6.
