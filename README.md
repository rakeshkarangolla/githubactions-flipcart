# githubactions-flipcart
# FlipkartClone — End-to-End DevOps Capstone

.NET Razor Pages · GitHub Actions CI/CD · Terraform IaC · Azure App Service

Source code → CI build → Infrastructure as Code → automated Azure deployment.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Phase 1 — Source Code & Version Control](#phase-1--source-code--version-control-setup)
- [Phase 2 — CI Pipeline with GitHub Actions](#phase-2--ci-pipeline-with-github-actions)
- [Phase 3 — Terraform & Azure Infrastructure](#phase-3--terraform--azure-infrastructure)
- [Phase 4 — Debugging & Production Readiness](#phase-4--debugging-fixes--production-readiness)
- [Getting Started](#getting-started)
- [Troubleshooting Reference](#troubleshooting-reference)
- [Key Concepts Learned](#key-concepts-learned)
- [Final Result](#final-result)
- [Planning](#planning)

---

## Overview

This repo takes a .NET Razor Pages application from local development to a publicly accessible, automatically deployed Azure Web App, with no manual steps in the Azure Portal by the time the pipeline is finished.

It was built in four phases:

| Phase | Focus | Outcome |
|:---:|---|---|
| 1 | Source code & Git hygiene | Clean, version-controlled app pushed to GitHub |
| 2 | Continuous Integration | Every push builds via GitHub Actions |
| 3 | Infrastructure as Code | Azure resources defined and validated with Terraform |
| 4 | Deployment automation | Full pipeline, live on Azure |

Along the way this hit the same problems most people run into automating a real cloud deployment for the first time — region quota limits, Linux vs. Windows App Service behavior, a missing `web.config` — so those are documented below along with how each was fixed, not just the happy path.

---

## Architecture

```
Developer (VS Code)
        │  git push
        ▼
GitHub Repository
        │  triggers
        ▼
GitHub Actions (deploy.yml)
   1. Checkout code
   2. Setup .NET 8
   3. terraform init / apply
   4. dotnet publish
   5. Azure ZIP Deploy
        │  authenticates via AZURE_CREDENTIALS
        │  (Service Principal)
        ▼
Microsoft Azure
   Resource Group
     └─ App Service Plan (Windows)
          └─ Windows Web App (ASP.NET Core 8, IIS)
```

---

## Tech Stack

| Category | Tool / Technology |
|---|---|
| Application | ASP.NET Core Razor Pages (.NET 8 LTS) |
| Version Control | Git + GitHub |
| CI/CD | GitHub Actions |
| Infrastructure as Code | Terraform (`azurerm` provider `~> 3.100`) |
| Cloud Platform | Microsoft Azure (App Service, Windows hosting) |
| Authentication | Azure Service Principal (`az ad sp create-for-rbac`) |
| Deployment Method | ZIP Deploy to Azure Web App |
| Local Tooling | Visual Studio, VS Code, Azure CLI, dotnet CLI |

---

## Repository Structure

```
githubactions-flipcart/
├── .github/
│   └── workflows/
│       ├── ci.yml                # CI: restore & build validation (manual trigger)
│       └── deploy.yml            # CD: Terraform apply + publish + Azure deploy (on push to main)
├── Pages/                        # Razor Pages (UI)
│   ├── Index.cshtml / .cs
│   ├── Privacy.cshtml / .cs
│   ├── Error.cshtml / .cs
│   └── Shared/_Layout.cshtml
├── Properties/
│   └── launchSettings.json
├── wwwroot/                      # Static assets (css, js, bootstrap, jquery)
├── terraform/
│   ├── main.tf                   # Azure resource definitions
│   ├── variable.tf               # Configurable inputs
│   ├── outputs.tf                # Terraform outputs (webapp name/url)
│   └── .terraform.lock.hcl
├── Program.cs
├── FlipkartClone.csproj
├── FlipkartClone.sln
├── appsettings.json / appsettings.Development.json
├── .gitignore
└── README.md
```

The `.gitignore` keeps `.vs/`, `bin/`, `obj/`, OS artifacts (`.DS_Store`, `Thumbs.db`), and Terraform state/cache (`.terraform/`, `*.tfstate`, `*.tfstate.*`, `terraform.tfvars`) out of the repo.

---

## Phase 1 — Source Code & Version Control Setup

Goal: get the application running locally and the repo into good shape before touching CI/CD.

### What was done
- Built an ASP.NET Core Razor Pages app — a simple Flipkart-style homepage
- Targeted .NET 8 (LTS) for Azure compatibility
- Verified the app runs locally via Visual Studio, VS Code, and `dotnet run`
- Confirmed local tooling: .NET SDK, Terraform, Azure CLI, Git
- Initialized a Git repository with a proper `.gitignore`
- Pushed clean code to GitHub

### Errors faced and how they were fixed

<details>
<summary>MSBUILD error MSB1009 — Project file does not exist</summary>

Command: `dotnet run --project .\FlipkartClone`

Root cause: already inside the project folder, so `--project` was pointing at a subfolder that didn't exist.

Fix:
```bash
dotnet run
# or
dotnet run --project FlipkartClone.csproj
```
</details>

<details>
<summary>Git permission denied on the .vs folder</summary>

Error: `open(".vs/...vsidx"): Permission denied` → `fatal: adding files failed`

Root cause: Visual Studio's `.vs/` cache folder contains locked IDE files, and there was no `.gitignore` yet to keep it out.

Fix:
```bash
git rm -r --cached .vs
git add .
git commit -m "Initial Razor Pages app with gitignore"
```
</details>

### `.gitignore`
```gitignore
# Visual Studio
.vs/
*.user
*.suo

# Build output
bin/
obj/

# OS files
.DS_Store
Thumbs.db
```

### `.csproj` — Azure-ready configuration
```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <!-- IMPORTANT FOR AZURE WINDOWS APP SERVICE -->
    <PublishIISAssets>true</PublishIISAssets>
  </PropertyGroup>
</Project>
```

Why it matters: GitHub Actions runners don't have Visual Studio and don't need `.vs/`, `bin/`, or `obj/` — everything gets built from source. A clean repo builds faster and doesn't fail for reasons that have nothing to do with the code.

---

## Phase 2 — CI Pipeline with GitHub Actions

Goal: automate build validation on every push. No Azure yet — this phase is just Continuous Integration.

### Step 2.1 — Create the GitHub repository
1. New repository → name: `githubactions-flipcart`
2. Visibility: Public
3. Don't add a README, `.gitignore`, or license — the local repo already has these, and adding them on GitHub too just causes merge conflicts
4. Create repository

### Step 2.2 — Connect the local repo to GitHub
```bash
git remote add origin git@github.com:rakeshkarangolla/githubactions-flipcart.git
git branch -M main
git push -u origin main
```

### Step 2.3 — Confirm GitHub Actions is enabled
Open the repo's Actions tab — it's on by default, nothing to configure.

### Step 2.4–2.5 — First CI workflow

`.github/workflows/ci.yml` is a lightweight build check: checkout, install .NET 8, `dotnet restore`, then `dotnet build --configuration Release`. It's set to manual dispatch only — the `push` trigger is commented out in the file — so it doesn't run twice alongside the deploy pipeline added in Phase 4.

### Step 2.6 — Commit and push
```bash
git add .github
git commit -m "Add CI workflow for .NET build"
git push
```

### Step 2.7 — Watch it run
Actions → CI - Build .NET App → Run workflow. Runner starts, .NET installs, restore succeeds, build succeeds.

### Common errors

| Issue | Reason | Fix |
|---|---|---|
| Workflow not running | Wrong branch | Confirm push targets `main` |
| Build fails | Wrong .NET version | Use `8.0.x` |
| Actions tab empty | No workflow committed | Push the YAML file |

---

## Phase 3 — Terraform & Azure Infrastructure

Goal: define the Azure infrastructure as code and set up secure authentication for GitHub Actions. No application deployment yet.

### Azure resources defined
1. Resource Group
2. App Service Plan
3. Azure Web App (configured for .NET 8)

### Step 1 — Azure account setup
```bash
az login
az account show
az account show --query id -o tsv     # get subscription ID
```

### Step 2 — Create a Service Principal for automation
Terraform and GitHub Actions need to authenticate to Azure without a human logging in, so this uses a Service Principal:
```bash
az ad sp create-for-rbac \
  --name gha-flipkart-sp \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth
```
This returns a JSON object with `clientId`, `clientSecret`, `tenantId`, `subscriptionId`, and the Azure endpoints. Keep it as-is for the next step.

### Step 3 — Store credentials in GitHub Secrets
1. Repo Settings → Secrets and variables → Actions → New repository secret
2. Name: `AZURE_CREDENTIALS`
3. Value: the entire JSON output from the Service Principal command

This secret is what both Terraform and the deployment step use later — nothing sensitive ever lives in source code, Terraform files, or the workflow YAML itself.

### Step 4 — Terraform configuration

The infrastructure is split across three files in `terraform/` (the actual code lives in the repo):

- `main.tf` declares the `azurerm` provider and three resources: `azurerm_resource_group`, `azurerm_service_plan` (Windows, `B1` tier), and `azurerm_windows_web_app` configured with the `dotnetcore` stack on `v8.0`. Each resource references the one before it so Terraform creates them in the right order.
- `variable.tf` defines four inputs with defaults: `resource_group_name` (`rg-flipkart-gha`), `location` (`canadacentral`), `app_service_plan_name` (`asp-flipkart-gha`), and `web_app_name` (`flipkart-gha-webapp-demo`). Using variables instead of hardcoding values keeps the config reusable.
- `outputs.tf` exposes `webapp_name` and `webapp_url` (the `default_hostname`) after `apply`, so the deployed URL is easy to grab without opening the Azure Portal.

### Step 5 — Validate locally
```bash
cd terraform
terraform init
terraform plan
```
Expected: `Plan: 3 to add, 0 to change, 0 to destroy`

Don't run `terraform apply` locally in this phase — provisioning happens through GitHub Actions in the next one.

### Step 6 — How GitHub Actions uses this
- `azure/login` reads the `AZURE_CREDENTIALS` secret
- Terraform authenticates automatically — no manual `az login` on the runner
- Infrastructure gets created without ever touching the Azure Portal

By the end of this phase: Azure account verified, Service Principal created, GitHub secret configured, Terraform code structured with variables in place, and a local `plan` that runs clean.

---

## Phase 4 — Debugging, Fixes & Production Readiness

Goal: get the deployment actually working end-to-end, and stay working.

### GitHub Actions — deployment stage

Building on Phase 3, a second workflow — `.github/workflows/deploy.yml` — runs on every push to `main` and handles the full provision-and-deploy flow in one job:

1. Checkout the repository
2. Azure Login via `azure/login`, using the `AZURE_CREDENTIALS` secret from Phase 3
3. Setup Terraform, then `terraform init` and `terraform apply -auto-approve` inside `terraform/` — this is what actually provisions the Resource Group, App Service Plan, and Web App
4. Setup .NET 8, then `dotnet publish FlipkartClone.csproj -c Release -o publish`
5. Deploy to Azure Web App using `azure/webapps-deploy@v2`, pointing at the `publish` folder and the target `app-name`

One thing worth knowing: `app-name` in the deploy step is hardcoded to match the Terraform `web_app_name` default (`flipkart-gha-webapp-demo`). If that variable ever changes, the workflow needs updating too — Terraform's output doesn't currently feed back into this step automatically.

### Real issues hit along the way

| Issue | Root cause | Resolution |
|---|---|---|
| GitHub push failures | Large Terraform provider binaries got committed by accident | Cleaned Git history, enforced `.gitignore` for `.terraform/` |
| 401 quota errors | Azure region quota limitations | Switched region / plan tier |
| 404 App Service errors | Linux vs. Windows App Service behavior mismatch | Standardized on Windows Web App for stability |
| App not starting | Missing startup configuration | Corrected `site_config` / startup command |
| IIS hosting failure | Missing `web.config` | Enabled `PublishIISAssets` in `.csproj` |
| Terraform state drift | No remote backend configured | Manual resource cleanup for now; remote state is on the list below |

### Verification
Deployment was confirmed by checking Azure Kudu logs (`https://<app-name>.scm.azurewebsites.net`) for runtime startup and IIS bindings.

By the end of this phase the app runs reliably on Azure and the deployment process was actually understood, not just copy-pasted.

---

## Getting Started

### Prerequisites
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Git](https://git-scm.com/)
- [Terraform](https://developer.hashicorp.com/terraform/downloads), compatible with the `~> 3.100` azurerm provider
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- An active Azure subscription (free tier works)

### 1. Clone and run locally
```bash
git clone https://github.com/rakeshkarangolla/githubactions-flipcart.git
cd githubactions-flipcart
dotnet restore
dotnet run
```

### 2. Set up Azure authentication
```bash
az login
az account show --query id -o tsv
az ad sp create-for-rbac --name gha-flipkart-sp --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> --sdk-auth
```
Add the JSON output as a GitHub repository secret named `AZURE_CREDENTIALS`.

### 3. Provision and deploy
Push to `main` and GitHub Actions takes it from there:
```bash
git add .
git commit -m "Deploy"
git push origin main
```
Watch the pipeline in the Actions tab. On success, the app is live at:
```
https://<web_app_name>.azurewebsites.net
```

---

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `MSB1009: Project file does not exist` | Wrong `--project` path | Run `dotnet run` from the project root |
| `Permission denied` on `.vs/` | No `.gitignore`, locked IDE cache | `git rm -r --cached .vs` + add `.gitignore` |
| Workflow doesn't trigger | Push isn't on `main` | Check branch name in `on.push.branches` |
| CI build fails | .NET version mismatch | Pin `dotnet-version: '8.0.x'` |
| Actions tab shows nothing | Workflow YAML not committed or pushed | `git add .github && git push` |
| 401 errors during provisioning | Azure region/quota limits | Choose a supported region or upgrade quota |
| 404 after deployment | OS mismatch (Linux vs. Windows plan) | Use Windows App Service Plan + Web App |
| App won't start post-deploy | Missing startup config / `web.config` | Set `PublishIISAssets=true`; check Kudu logs |
| Terraform state issues | No remote backend | Clean up manually; add a remote backend (see Planning) |

---

## Key Concepts Learned

**Application**
Razor Pages fundamentals, choosing an LTS runtime, local dev validation across IDEs.

**Git & DevOps hygiene**
Project vs. solution paths, `.gitignore` strategy, separating IDE artifacts from source code.

**CI/CD**
GitHub Actions triggers (`push`, `workflow_dispatch`), runners, job/step structure.

**Infrastructure as Code**
Terraform providers, resources, variables and outputs, `plan` vs. `apply`, idempotent infrastructure.

**Cloud & security**
Service Principal authentication, GitHub Secrets, Azure App Service hosting models, region/quota constraints.

---

## Final Result

By the end of this project:

- A real .NET web application (Razor Pages)
- Fully automated CI/CD via GitHub Actions
- Infrastructure as Code with Terraform
- A live Azure App Service deployment, publicly accessible
- Practical experience with cloud quotas, Linux vs. Windows hosting models, and debugging a deployment pipeline for real

---

## Planning

- [ ] Add a Terraform remote backend (Azure Storage) for team-safe state management
- [ ] Split CI and CD into separate workflows with environment approvals
- [ ] Add automated tests to the CI pipeline
- [ ] Introduce staging vs. production deployment slots
- [ ] Add monitoring/alerting via Azure Application Insights

---

Built as a hands-on DevOps capstone — from `dotnet run` to a live Azure deployment.
