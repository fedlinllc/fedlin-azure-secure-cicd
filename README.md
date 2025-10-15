# Project 0 – Azure Secure CI/CD Baseline

**Repo:** `fedlin-azure-secure-cicd` • **Branch strategy:** protected `main`, squash merges  
**Auth:** GitHub OIDC → Azure (no long-lived client secrets)

> #### Preconfigured (one-time manual)
> - Protect `main` (PRs + squash merges).
> - Entra ID **federated credential** for this repo/workflow; **RG-scoped RBAC** only.
> - GitHub repo **secrets** for Azure OIDC where applicable (no secrets in code).
> - Evidence screenshots stored under `docs/img/`.

---

## Summary

Passwordless, least-privileged deployment path to Azure using **GitHub OIDC** and a minimal, idempotent pipeline that exports outputs for downstream labs (Sentinel, Hardening/OpenSCAP, Purview DLP). The pipeline run below demonstrates the baseline working end-to-end:

<img width="1019" height="883" alt="01-pipeline-run" src="https://github.com/user-attachments/assets/01831993-b46c-4865-954d-eab97c35adff" />

---

## Architecture at a Glance

This repo provisions a shared baseline Resource Group and telemetry primitives consumed by later projects.

```
GitHub Actions (OIDC federated)
│
▼
Azure Resource Group: fedlin-rg
├─ Log Analytics Workspace:  fedlin-law
├─ Data Collection Rule:     fedlin-dcr
└─ Data Collection Endpoint: fedlin-evidence-dce
    ├─ Project 1: Sentinel Vulnerability & Compliance Lab
    ├─ Project 2: Hardening & Remediation (Ansible/OpenSCAP)
    └─ Project 3: Purview DLP Lab
```

RG state after a successful deployment:

<img width="1910" height="733" alt="03-rg-overview" src="https://github.com/user-attachments/assets/9ffad273-3ac4-4a3a-99e3-1c3adc0f5a3a" />


Azure’s native deployment history provides immutable confirmation of outcomes:

<img width="1910" height="733" alt="02-azure-deployment-history" src="https://github.com/user-attachments/assets/4702f615-c9e8-42fb-bab6-f9c79aeda1e2" />


---

## Secure Pipeline Highlights

**OIDC to Azure.** Short-lived tokens via a federated credential—no client secrets committed or stored.  
<img width="1910" height="733" alt="02-azure-deployment-history" src="https://github.com/user-attachments/assets/381f5f9e-9480-403e-98e5-cd74e09ee47f" />


**Least privilege.** RBAC is limited to the Resource Group used by this baseline.  
<img width="1492" height="886" alt="05-iam-role-assignments" src="https://github.com/user-attachments/assets/4a064f34-c83a-4e4e-b384-8c59c45fa253" />

**Deterministic & idempotent.** Safe to re-run; stable names; predictable outputs.

**Protected flow.** Work lands via PRs and squash merges to keep history linear.

**Evidence-first.** Artifacts and screenshots demonstrate control intent → outcome.  
<img width="1406" height="844" alt="06-evidence-pack" src="https://github.com/user-attachments/assets/78b80763-9f8c-44e0-95b7-d8d39e395ae9" />



---

## Run It

**GitHub UI:** Actions → run the deploy workflow on `main` (or a PR branch).

**CLI:**
```bash
gh workflow run deploy-azure.yml --ref main
gh run watch --exit-status
```

**Expected results**
- Workflow completes without secrets in logs.
- Azure **Deployments** blade shows **Succeeded** for this run (see screenshot above).
- Downstream projects can consume this repo’s `outputs.json` as needed.

---

## Clean Up

- Remove temporary branches after merge:
```bash
git push origin :<branch-name>
```
- Resource teardown is handled in downstream labs when appropriate; this baseline is intended to persist for reuse.

---

## Appendix — One-time manual configuration performed

- **GitHub**
  - Protected `main` (PRs required; squash merges enabled).
  - Added necessary secrets only for Azure OIDC usage (kept out of code).

- **Azure / Entra**
  - Created a **federated credential** tied to this repo/workflow.
  - Applied **RG-scoped** role assignments to enforce least privilege.

**Notes**
- No subscription IDs, tenant IDs, or tokens are exposed in docs or logs.
- All images are under `docs/img/` for portability across clones/forks.
- This baseline is the prerequisite for Projects 1–3 (SIEM, hardening, DLP).

## Evidence & Telemetry

The pipeline and baseline Azure configuration are validated with the following screenshots (stored under `docs/img/`):

1. **GitHub Actions pipeline run**  
   ![Pipeline run](docs/img/01-workflow-run.png)

2. **Azure Resource Group — Deployments history**  
   ![RG deployments](docs/img/02-azure-deployment-history.png)

3. **Azure Resource Group — Overview**  
   ![RG overview](docs/img/03-rg-overview.png)

4. **Microsoft Entra — Federated credentials (OIDC)**  
   ![Entra federated credentials](docs/img/04-entra-federated-cred.png)

   > **Note on extra federated credentials**  
   > You may see additional rows for other repos/branches that belong to later projects.  
   > For this project, ensure there’s a federated credential whose **Subject** matches this repo/branch:  
   > `repo:<org>/<repo>:ref:refs/heads/<branch>`

5. **Azure RBAC — Role assignments (service principal / OIDC app)**  
   ![IAM role assignments](docs/img/05-iam-role-assignments.png)

6. **Evidence Pack artifact (workflow output)**  
   ![Evidence pack](docs/img/06-evidence-pack.png)
