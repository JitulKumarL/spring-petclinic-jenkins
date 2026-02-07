# Production-Grade Jenkins Pipeline — Complete Setup Guide

This guide walks you through installing, configuring, and running the production-grade Jenkins pipeline from scratch on RHEL/Alma Linux (controller) and Rocky Linux (deploy targets). The pipeline is defined in this repository (`Jenkinsfile` + `jenkins/scripts/`).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Jenkins Controller Setup (RHEL/Alma Linux)](#3-jenkins-controller-setup-rhealma-linux)
4. [Deploy Host Setup (Rocky Linux)](#4-deploy-host-setup-rocky-linux)
5. [Jenkins Plugins](#5-jenkins-plugins)
6. [Credentials Configuration](#6-credentials-configuration)
7. [Pipeline Job Creation](#7-pipeline-job-creation)
8. [Multi-Environment Configuration](#8-multi-environment-configuration)
9. [Stage View & Blue Ocean](#9-stage-view--blue-ocean)
10. [Running the Pipeline](#10-running-the-pipeline)
11. [Testing Rollback](#11-testing-rollback)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Architecture Overview

```
┌─────────────────────┐     SSH / SCP      ┌─────────────────────┐
│  Jenkins Controller │ ─────────────────► │  Deploy Hosts       │
│  (RHEL/Alma Linux)  │                     │  (Rocky Linux)      │
│                     │                     │                     │
│  - Build (Maven)    │                     │  test: 192.168.31.121│
│  - Test             │                     │  uat:  192.168.31.122│
│  - Deploy trigger   │                     │  stage:192.168.31.123│
│  - Health check     │                     │  prod: 192.168.31.124│
└─────────────────────┘                     └─────────────────────┘
```

**Pipeline flow:**
```
Environment Setup → Checkout → Static Analysis → Unit Tests → Build Artifact →
Store Artifact → [Docker Build] → [Push Registry] → Deploy → Smoke/Health Tests
                                                                    ↓
                                                            (fail → Rollback)
```

---

## 2. Prerequisites

### Controller (RHEL/Alma Linux)

| Component | Version | Purpose |
|-----------|---------|---------|
| RHEL / Alma Linux | 8+ | Jenkins controller |
| Java | 21 | Jenkins + Maven |
| Git | 2.x | Checkout |
| Docker | 20+ | If using Docker deploy method |

### Deploy Hosts (Rocky Linux)

| Component | Version | Purpose |
|-----------|---------|---------|
| Rocky Linux | 8+ | Application runtime |
| Java | 21 | Run Spring Boot JAR |
| SSH | OpenSSH | Remote deployment |

### Network

- Jenkins controller/agent can reach deploy hosts (192.168.31.x)
- Deploy hosts can reach Jenkins (if agent runs on controller)

---

## 3. Jenkins Controller Setup (RHEL/Alma Linux)

### 3.1 Install Java 21

```bash
sudo dnf install -y java-21-openjdk-devel
java -version
```

### 3.2 Install Jenkins

```bash
# Add Jenkins repo (Alma/RHEL 8)
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Install
sudo dnf install -y jenkins

# Start and enable
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins
```

### 3.3 Initial Unlock

1. Open `http://<controller-ip>:8080`
2. Retrieve initial admin password:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. Complete setup wizard, install suggested plugins

### 3.4 Install Git (if not present)

```bash
sudo dnf install -y git
```

---

## 4. Deploy Host Setup (Rocky Linux)

Repeat for each environment host (test, uat, stage, prod).

### 4.1 Create deploy user

```bash
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy   # or use SSH keys only
```

### 4.2 Install Java 21

```bash
sudo dnf install -y java-21-openjdk
java -version
```

### 4.3 Create app directory

```bash
mkdir -p /home/deploy/petclinic
chown deploy:deploy /home/deploy/petclinic
```

### 4.4 Configure SSH (passwordless)

On the **Jenkins agent** (controller or separate agent):

```bash
# Generate key (run as jenkins user or agent user)
sudo -u jenkins ssh-keygen -t ed25519 -N "" -f /var/lib/jenkins/.ssh/deploy_key

# Copy to each deploy host
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/deploy_key.pub deploy@192.168.31.121
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/deploy_key.pub deploy@192.168.31.122
# ... repeat for uat, stage, prod hosts
```

### 4.5 Verify SSH

```bash
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/deploy_key deploy@192.168.31.121 "echo OK"
```

---

## 5. Jenkins Plugins

1. **Manage Jenkins** → **Plugins** → **Available**
2. Search and install:

| Plugin | Purpose |
|--------|---------|
| Pipeline | Core pipeline support |
| **Multibranch Pipeline** | Branch discovery, branch-to-env |
| **Pipeline: Stage View** | Stage grid (columns=stages, rows=builds) |
| **GitHub** | Webhook endpoint for push-triggered builds |
| Docker Pipeline | Docker build/push |
| Git | Git checkout |
| JUnit | Test reports |
| Copy Artifact | Copy artifacts from previous builds |
| SSH Agent | SSH credentials for deploy |
| Blue Ocean | Modern pipeline UI (optional) |
| SonarQube Scanner | Code quality (optional) |
| JaCoCo | Coverage (optional) |

3. Restart Jenkins if prompted.

---

## 6. Credentials Configuration

### 6.1 SSH credentials for deploy

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. **Add Credentials**
3. Kind: **SSH Username with private key**
4. Scope: **Global**
5. ID: `deploy-ssh-key`
6. Username: `deploy`
7. Private Key: **Enter directly**
   - Paste the contents of `/var/lib/jenkins/.ssh/deploy_key`
   - Or: **From a file on Jenkins controller** → `/var/lib/jenkins/.ssh/deploy_key`

### 6.2 (Optional) Docker registry

For Docker deploy with registry:

1. Add **Username with password** credential
2. ID: `docker-registry-credentials`
3. Username / Password: your registry login

### 6.3 (Optional) GitHub

For private app repos:

1. Add **Username with password** or **SSH**
2. ID: `github-credentials`

---

## 7. Multibranch Pipeline Job Creation

### 7.1 Create multibranch pipeline job

1. **New Item**
2. Name: `petclinic-pipeline` (or your choice)
3. Type: **Multibranch Pipeline** (not "Pipeline")
4. **OK**

### 7.2 Configure branch sources

The multibranch pipeline points to **this repository** (Spring Petclinic). The Jenkinsfile and `jenkins/scripts/` live here.

1. **Branch Sources** → **Add source** → **Git**
2. **Repository URL**: `https://github.com/<your-org>/spring-petclinic.git` (this repo or your fork)
3. **Credentials**: leave empty for public; select `github-credentials` for private
4. **Behaviours** (optional):
   - **Discover branches** (default)
   - **Filter by name (regular expression)**: `main|master|stage|uat|test|develop|dev` (to limit branches)

### 7.3 Build configuration

1. **Build Configuration** → Mode: **by Jenkinsfile**
2. **Script Path**: `Jenkinsfile`

### 7.4 Save and scan

1. **Save**
2. Click **Scan Multibranch Pipeline Now**
3. Jenkins discovers branches and creates a sub-job per branch

### 7.5 Branch-to-environment mapping

| Branch | Deploys to |
|--------|------------|
| `main` / `master` | prod |
| `stage` | stage |
| `uat` | uat |
| `test` / `develop` / `dev` | test |
| Other | test (default) |

### 7.6 GitHub Webhook (auto-build on push)

Install the **GitHub** plugin (Manage Jenkins → Plugins), then add the webhook in GitHub:

#### Step 1: In GitHub

1. Open your repo → **Settings** → **Webhooks** → **Add webhook**

2. **Payload URL:**
   ```
   https://<your-jenkins-host>/github-webhook/
   ```
   Example: `https://jenkins.mycompany.com/github-webhook/`

3. **Content type:** `application/json`

4. **Secret** (optional): Leave empty, or generate one and add the same in Jenkins (Manage Jenkins → Configure System → GitHub → Advanced)

5. **Which events:** Select **Just the push event**

6. **Active:** Checked

7. **Add webhook**

#### Step 2: Verify

- After adding, GitHub sends a ping. Check **Recent deliveries** for status 200.
- Push a commit to any branch; Jenkins should trigger a scan and build within seconds.

#### Step 3: Firewall / Cloudflare

If Jenkins is behind Cloudflare or a firewall, allow GitHub's webhook IP ranges. See [GitHub meta API](https://api.github.com/meta) → `hooks` section.

#### Troubleshooting

| Issue | Check |
|-------|-------|
| 404 on ping | Verify URL ends with `/github-webhook/` and GitHub plugin is installed |
| Connection refused | Jenkins must be reachable from the internet (or GitHub's IPs) |
| No build triggered | Ensure the Multibranch job uses the same repo URL; run **Scan Multibranch Pipeline Now** manually first |

#### Alternative: GitHub Branch Source

For tighter integration, use **GitHub** as the branch source instead of **Git**:

1. **Branch Sources** → **Add source** → **GitHub**
2. Add **GitHub** connection (or use "GitHub" credentials)
3. **Credentials**: add a Personal Access Token (repo scope) or GitHub App
4. **Repository**: select your org/repo
5. Jenkins can auto-register the webhook when you save (if it has admin access), or add the webhook manually as above

### 7.7 First run parameters

When you **Build with Parameters** (or first automatic run):

| Parameter | Recommended |
|-----------|-------------|
| SKIP_SONAR | `true` |
| PUSH_TO_REGISTRY | `false` |
| DEPLOY_METHOD | `jar` |
| SSH_CREDENTIALS_ID | `deploy-ssh-key` |

---

## 8. Multi-Environment Configuration

**Branch-to-environment** is automatic. Edit the Jenkinsfile (Environment Setup stage):

**Branch mapping:**
```groovy
def branchToEnv = [
    'main': 'prod', 'master': 'prod',
    'stage': 'stage', 'uat': 'uat',
    'test': 'test', 'develop': 'test', 'dev': 'test',
]
```

**Host config:**
```groovy
def envConfig = [
    test: [host: '192.168.31.121', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    uat:  [host: '192.168.31.122', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    stage:[host: '192.168.31.123', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    prod: [host: '192.168.31.124', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
]
```

- **host**: IP or hostname of the deploy server
- **user**: SSH user
- **creds**: Jenkins credential ID for SSH
- **port**: App port (default 8080 for Spring Boot)

Prod deployments require manual approval (input step) when building from `main`.

---

## 9. Stage View & Blue Ocean

### Stage View

1. Install **Pipeline: Stage View**
2. Open the pipeline job
3. The **Stage View** appears on the job page:
   - **Columns**: Environment Setup, Checkout, Static Code Analysis, Unit Tests, Build Artifact, Store Artifact, Docker Image Build, Push Image to Registry, Deploy to Environment, Smoke / Health Tests
   - **Rows**: Each build (#63, #62, #61...)
   - **Cells**: Status (success/failed/aborted) + duration
   - **Average stage times**: Below the grid

No changes to the Jenkinsfile are required; the plugin uses existing `stage()` blocks.

### Blue Ocean

1. Install **Blue Ocean**
2. Open the pipeline job
3. Click **Open in Blue Ocean**
4. Use the visual pipeline view and stage logs

---

## 10. Running the Pipeline

### 10.1 Multibranch: automatic and manual

- **Auto**: Push to `main`, `stage`, `uat`, `test`, etc. triggers build (with webhook)
- **Manual**: Open the branch (e.g. **main**), click **Build Now** or **Build with Parameters**

### 10.2 Build with parameters (optional)

1. Open the branch job (e.g. `petclinic-pipeline/main`)
2. **Build with Parameters**
3. Set SKIP_SONAR, DEPLOY_METHOD, etc. (DEPLOY_ENV is derived from branch)

### 10.3 Monitor

- **Stage View**: See stage progress and durations per branch
- **Console Output**: Full logs
- **Build** → **Stage View**: Per-stage view

### 10.4 Expected stages

| Stage | Typical duration |
|-------|------------------|
| Environment Setup | < 1s |
| Checkout | 5–15s |
| Static Code Analysis | 10–60s |
| Unit Tests | 20–60s |
| Build Artifact | 30–90s |
| Store Artifact | 1–2s |
| Docker Image Build | 30–60s (if docker) |
| Push Image to Registry | 10–30s (if enabled) |
| Deploy to Environment | 5–15s |
| Smoke / Health Tests | 5–30s |

---

## 11. Testing Rollback

### 11.1 Successful build

1. Push to `test` branch (or run build on `test`) → deploys to test env
2. Confirm all stages succeed (Build #1)
3. App is deployed and healthy on the target host

### 11.2 Simulate health failure

1. Run build again on the same branch with **FORCE_ROLLBACK_TEST** = `true`
2. Health check stage fails
3. Post-failure: rollback runs
4. Previous build's artifact is deployed to the same host
5. Rollback completion appears in logs

### 11.3 Verify rollback

```bash
# On deploy host
ssh deploy@192.168.31.121 "ps aux | grep java"
curl http://192.168.31.121:8080/actuator/health
```

---

## 12. Troubleshooting

### SSH connection refused

- Ensure SSH is running on deploy host: `sudo systemctl status sshd`
- Check firewall: `sudo firewall-cmd --list-all`
- Verify key: `ssh -i ~/.ssh/deploy_key -v deploy@192.168.31.121`

### Permission denied (publickey)

- Ensure `deploy_key` is added to deploy user's `~/.ssh/authorized_keys`
- Check file permissions: `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`

### Health check timeout

- App may not be listening on 0.0.0.0; check `server.address` in Spring Boot config
- Firewall may block 8080: `sudo firewall-cmd --add-port=8080/tcp --permanent`
- Increase `HEALTH_CHECK_TIMEOUT` in Jenkinsfile

### Copy Artifact fails during rollback

- **Copy Artifact** plugin must be installed
- Previous build must have succeeded and archived artifacts
- Check that the job name matches (`env.JOB_NAME`)

### Stage View not showing

- Install **Pipeline: Stage View**
- Pipeline must use Declarative `stage()` blocks (already in place)
- Refresh the job page

### Maven / Java not found

- Ensure Java 21 is on the agent: `java -version`
- Pipeline uses Maven wrapper (`./mvnw`); no separate Maven install needed

### Docker build fails (Docker method)

- Docker must be installed on the agent
- Agent user must be in `docker` group: `sudo usermod -aG docker jenkins`

---

## Appendix A: Pipeline Stages Reference

| Stage | Purpose |
|-------|---------|
| Environment Setup | Set DEPLOY_HOST, HEALTH_CHECK_URL per env |
| Checkout | Clone this repo (contains Jenkinsfile + app code) |
| Static Code Analysis | Checkstyle + optional SonarQube |
| Unit Tests | Maven test, JUnit reports |
| Build Artifact | `mvn package`, produce JAR |
| Store Artifact | Archive JAR, prepare for rollback |
| Docker Image Build | Build container (if docker method) |
| Push Image to Registry | Push to registry (if enabled) |
| Deploy to Environment | SSH + deploy (JAR or Docker) |
| Smoke / Health Tests | Poll `/actuator/health` |
| Rollback (post) | On health failure, deploy previous build |

---

## Appendix B: File Structure (this repo)

```
spring-petclinic/
├── Jenkinsfile              # Main pipeline
├── SETUP_GUIDE.md           # This guide
├── README.md
├── pom.xml                  # Maven build
├── mvnw / mvnw.cmd          # Maven wrapper
└── jenkins/
    └── scripts/
        ├── deploy.sh        # Deploy (JAR or Docker)
        ├── health-check.sh  # Smoke test
        └── rollback.sh      # Rollback to previous build
```

---

## Appendix C: Quick Reference

| Item | Value |
|------|-------|
| Health endpoint | `/actuator/health` |
| Default port | 8080 |
| SSH credential ID | `deploy-ssh-key` |
| Deploy user | `deploy` |
| App directory (remote) | `/home/deploy/petclinic` |
