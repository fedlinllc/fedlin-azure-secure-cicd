#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
REGION="centralus"
VM_SIZE="Standard_B1s"
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

# For CI/CD runners we allow SSH from anywhere; later we lock to your IP
MY_IP="*"
SSH_PORT=22
HTTPS_PORT=443

echo "Validating region and VM size..."
[[ "$REGION" == "centralus" ]] || { echo "ERROR: Region must be 'centralus'."; exit 1; }
[[ "$VM_SIZE" == "Standard_B1s" ]] || { echo "ERROR: Size must be 'Standard_B1s'."; exit 2; }

# --- Helper: resolve a valid Rocky Linux 9 Gen2 image URN in this region ---
resolve_rocky_urn() {
  local loc="$1"
  # Known/current candidates (publisher:offer:sku)
  local candidates=(
    "erockyenterprisesoftwarefoundationinc1653071250513:rockylinux-9:rockylinux-9-gen2"
    "erockyenterprisesoftwarefoundationinc1653071250513:rockylinux-9:rockylinux-9"
    "erockyenterprisesoftwarefoundationinc1653071250513:rockylinux:rockylinux-9-gen2"
    "erockyenterprisesoftwarefoundationinc1653071250513:rockylinux:rockylinux-9"
    "resf:rockylinux:9-gen2"
    "resf:rockylinux:9-lvm"
  )
  for urn in "${candidates[@]}"; do
    if az vm image show --urn "${urn}:latest" --location "$loc" >/dev/null 2>&1; then
      echo "${urn}:latest"
      return 0
    fi
  done

  # Fallback: query everything and pick a Rocky 9 Gen2-ish entry if present
  local found
  found="$(az vm image list --all --location "$loc" \
      --query "[?contains(urn, 'rocky') && contains(urn, '9') && contains(urn, 'gen2')][0].urn" -o tsv || true)"
  if [[ -n "$found" ]]; then
    echo "${found}:latest"
    return 0
  fi
  return 1
}

echo "Resolving Rocky Linux 9 Gen2 image in region $LOCATION..."
if ! VM_IMAGE="$(resolve_rocky_urn "$LOCATION")"; then
  echo "ERROR: Could not find a valid Rocky Linux 9 Gen2 image in $LOCATION."
  echo "Hint: az vm image list --all --location $LOCATION --query \"[?contains(urn, 'rocky') && contains(urn, '9')][].urn\" -o tsv"
  exit 3
fi
echo "Using VM image: $VM_IMAGE"

# --- Resource Group ---
echo "Creating resource group ($RG)..."
az group create --name "$RG" --location "$LOCATION" --output none

# --- Log Analytics Workspace ---
echo "Creating Log Analytics Workspace ($LAW)..."
az monitor log-analytics workspace create \
  --resource-group "$RG" --workspace-name "$LAW" --location "$LOCATION" --output none
LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"

# --- VNet & Subnet ---
echo "Creating VNet and Subnet..."
az network vnet create --resource-group "$RG" --name "$VNET" \
  --address-prefixes "10.0.0.0/16" --subnet-name "$SUBNET" --subnet-prefix "10.0.1.0/24" --output none

# --- NSG: Allow SSH (temp) + HTTPS ---
echo "Configuring NSG ($NSG)..."
az network nsg create --resource-group "$RG" --name "$NSG" --output none
az network nsg rule create -g "$RG" --nsg-name "$NSG" --name "Allow-SSH-CI" \
  --priority 100 --source-address-prefixes "$MY_IP" --destination-port-ranges "$SSH_PORT" \
  --protocol Tcp --direction Inbound --access Allow --output none
az network nsg rule create -g "$RG" --nsg-name "$NSG" --name "Allow-HTTPS" \
  --priority 110 --source-address-prefixes "*" --destination-port-ranges "$HTTPS_PORT" \
  --protocol Tcp --direction Inbound --access Allow --output none
# (No explicit deny; NSGs default-deny everything else.)

# --- NIC ---
echo "Creating Network Interface ($NIC)..."
SUBNET_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" --name "$SUBNET" --query id -o tsv)"
az network nic create --resource-group "$RG" --name "$NIC" --subnet "$SUBNET_ID" --network-security-group "$NSG" --output none

# --- VM ---
echo "Deploying VM ($VM)..."
az vm create --resource-group "$RG" --name "$VM" \
  --image "$VM_IMAGE" --size "$VM_SIZE" \
  --admin-username "fedlinuser" --generate-ssh-keys \
  --nics "$NIC" --public-ip-sku Basic --storage-sku Standard_LRS --output none

# --- Azure Monitor Agent ---
echo "Installing Azure Monitor Agent (AMA)..."
az vm extension set --resource-group "$RG" --vm-name "$VM" \
  --name "$AMA_NAME" --publisher "Microsoft.Azure.Monitor" --output none

# --- Data Collection Rule (syslog -> LAW) ---
echo "Configuring Data Collection Rule (DCR)..."
DCR_FILE="$(mktemp)"
cat > "$DCR_FILE" <<JSON
{
  "location": "$LOCATION",
  "properties": {
    "dataSources": {
      "syslog": [
        {
          "name": "syslogSource",
          "streams": ["Microsoft-Syslog"],
          "facilityNames": ["authpriv","daemon"],
          "logLevels": ["Info","Warning","Error","Critical","Alert","Emergency","Debug","Notice"]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        { "name": "toLAW", "workspaceResourceId": "$LAW_ID" }
      ]
    },
    "dataFlows": [
      { "streams": ["Microsoft-Syslog"], "destinations": ["toLAW"] }
    ]
  }
}
JSON

az monitor data-collection rule create -g "$RG" -n "$DCR" --location "$LOCATION" --rule-file "$DCR_FILE" --output none

# Associate DCR to VM
VM_ID="$(az vm show --resource-group "$RG" --name "$VM" --query id -o tsv)"
DCR_ID="$(az monitor data-collection rule show -g "$RG" -n "$DCR" --query id -o tsv)"
az monitor data-collection rule association create --name "${VM}-dcr-assoc" \
  --rule-id "$DCR_ID" --resource "$VM_ID" --output none

# --- Output Public IP ---
PUBLIC_IP="$(az vm list-ip-addresses -g "$RG" -n "$VM" --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)"
echo "PUBLIC_IP=$PUBLIC_IP"
echo "Deployment complete."
