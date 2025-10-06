# Fedlin Azure Secure CI/CD (Self-Contained)

[An open-source pipeline that uses **GitHub Actions + Azure OIDC** to deploy an **AlmaLinux 9 Gen2** VM on Azure and wire it to **Log Analytics** via **Azure Monitor Agent (AMA)** and a **Data Collection Rule (DCR)**.  
This project focuses on **clean deployment + telemetry**. The follow-on project will cover **hardening / compliance** (CIS, OpenSCAP + Ansible).]

- Azure CLI ≥ 2.60 (`az version`)
- GitHub repo admin to add OIDC IDs + secrets
- One-time RBAC rights at RG scope (Owner or User Access Administrator) to grant the Service Principal **Contributor**


---

## Highlights

- **Credentialless deploy** with `azure/login` (OIDC).
- Resources: RG, VNet/Subnet, NIC + Public IP, VM (default `Standard_B1s`).
- **NSG attached** (defaults only; inbound closed by default in this project).
- **LAW + AMA + DCR** → syslog routed to Log Analytics.
- **Evidence pack** uploaded as a GitHub Actions artifact.
- **GitLab mirror** (non-blocking) on every push.

---

## What it creates

- **Resource Group**: `fedlin-rg` (prefix configurable)
- **Network**: VNet/Subnet, NSG attached to NIC
- **Compute**: AlmaLinux 9 Gen2 VM
- **Monitoring**: LAW, DCR (syslog), AMA extension on the VM
- **Artifacts**: sanitized evidence pack (`fedlin-evidence-pack`)

> Hardening (CIS `/32`, JIT/Bastion, OpenSCAP + Ansible) will be showcased in the **next** repo.

---

## Configure & Run

1. **Azure OIDC**: App Registration + Federated Credential for your GitHub repo.  
   Capture **Tenant ID**, **Client ID**, **Subscription ID**.

2. **Repo → Settings → Secrets and variables → Actions**  
   - **Secrets**
     - `SSH_PUBLIC_KEY` — your public key (single line).
   - **Variables** (or secrets if you prefer)
     - `REGION` (e.g., `eastus` or `centralus`)
     - `RESOURCE_PREFIX` (e.g., `fedlin`)
     - `VM_SIZE` (default `Standard_B1s`)
     - `ENABLE_HTTP` (`false`)
     - *(optional)* `MY_IP` (e.g., `203.0.113.45/32`) — not used to open ports in this project.

3. **Run the workflow**  
   Push to `main` (or trigger **Run workflow**). The job deploys infra + VM, installs AMA, creates & associates DCR, uploads artifacts, and mirrors to GitLab.

---

## Evidence (Screenshots)

> You provided these; paths below assume you commit them under `docs/media/`.  
> We intentionally **skip** NSG rule screenshots and Azure Monitor *pipelines (preview)* since they’re not part of this baseline.

- **GitHub Actions – successful run**  
<img width="1838" height="902" alt="Screenshot from 2025-10-05 18-54-44" src="https://github.com/user-attachments/assets/7d03f395-fa3e-4866-847d-9bdeac0a487e" />


- **Azure VM Overview (list)**  
 <img width="1838" height="902" alt="Screenshot from 2025-10-05 18-56-03" src="https://github.com/user-attachments/assets/53f23d47-f185-4de7-a085-8dcec7d755c2" />


- **Log Analytics Workspaces (list)**  
<img width="1907" height="929" alt="Screenshot from 2025-10-05 22-26-38" src="https://github.com/user-attachments/assets/dc724697-62d2-468a-b940-88df4d032a3f" />


- **GitLab mirror — repository view**  
<img width="1907" height="929" alt="Screenshot from 2025-10-05 22-33-55" src="https://github.com/user-attachments/assets/31b80db8-f223-42ed-9eba-dacd6e5d4bff" />


> The workflow also uploads a sanitized artifact named **`fedlin-evidence-pack`** for download from the Actions run.

---

## Mirror Security (Summary)

- GitLab project visibility: **Private**.
- `main` is **Protected** (push/merge: **Maintainers**, no force-push).
- GitHub Actions uses a token limited to **`write_repository`**.
- Optional: push rules to block obvious secret patterns.

---

## Costs & Cleanup

- VM size defaults to **free-tier-friendly** `Standard_B1s`.  
- Syslog ingestion typically low volume; still subject to LAW pricing.  
- Cleanup:
  ```bash
  az group delete -n fedlin-rg --yes --no-wait
