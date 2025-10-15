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

<img width="1837" height="892" alt="01-workflow-run" src="https://github.com/user-attachments/assets/75dfcc1b-8592-48e4-808d-7153f4802f34" />


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

<img width="1910" height="733" alt="03-rg-overview" src="https://github.com/user-attachments/assets/101b46dd-3f28-46ec-806a-64d6e85a887f" />



Azure’s native deployment history provides immutable confirmation of outcomes:

<img width="1910" height="733" alt="02-azure-deployment-history" src="https://github.com/user-attachments/assets/5930a2f8-cd7c-418b-a4f9-db69ba299c78" />



---

## Secure Pipeline Highlights

**OIDC to Azure.** Short-lived tokens via a federated credential—no client secrets committed or stored.  
<img width="1325" height="622" alt="04-entra-federated-cred" src="https://github.com/user-attachments/assets/db8fa29a-771c-47d8-9c15-ac2c78f5f829" />



**Least privilege.** RBAC is limited to the Resource Group used by this baseline.  
<img width="1492" height="886" alt="05-iam-role-assignments" src="https://github.com/user-attachments/assets/c4abe08c-49c9-494c-b77a-5562a44ed044" />


**Deterministic & idempotent.** Safe to re-run; stable names; predictable outputs.

**Protected flow.** Work lands via PRs and squash merges to keep history linear.

**Evidence-first.** Artifacts and screenshots demonstrate control intent → outcome.  
<img width="1406" height="844" alt="06-evidence-pack" src="https://github.com/user-attachments/assets/2c5b249e-7ebb-45cb-8b21-e646c554852e" />




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
