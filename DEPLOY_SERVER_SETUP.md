# Deploy Server & SSH Setup — Step-by-Step

This guide walks you through setting up deploy servers and SSH keys for the Jenkins pipeline.

**Important:** Deploy is done by **whoever runs the pipeline** (the node shown in the log, e.g. "Running on alma-agent-1"). That node's SSH public key must be in the deploy server's `authorized_keys`. If the agent runs the job, the agent's key goes to the deploy server. If the controller runs it, the controller's key goes to the deploy server.

---

## Option A: Same Machine as Jenkins Agent (Quick Start)

Use this if your Jenkins agent (`alma-agent-1`) can also run the Petclinic app. All steps run **on the Jenkins agent host**. Skip to **Option B** if you use a separate deploy VM.

---

### Step 1: Connect to the Jenkins agent

```bash
ssh your-user@alma-agent-1    # or however you access it
```

### Step 2: Create the deploy user

```bash
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy
# Enter a password (or leave empty for key-only auth)
```

### Step 3: Install Java on the deploy host

```bash
# Alma/RHEL/Rocky
sudo dnf install -y java-21-openjdk
java -version
```

### Step 4: Create the app directory

```bash
sudo mkdir -p /home/deploy/petclinic
sudo chown deploy:deploy /home/deploy/petclinic
```

### Step 5: Generate SSH key for Jenkins

```bash
sudo -u jenkins mkdir -p /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t ed25519 -N "" -f /var/lib/jenkins/.ssh/deploy_key
```

### Step 6: Copy the public key to the deploy user

```bash
# Get the agent's IP (use this as DEPLOY_HOST in Jenkinsfile)
hostname -I | awk '{print $1}'
# Example output: 192.168.1.100

# Copy the key to deploy user on the same machine
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/deploy_key.pub deploy@127.0.0.1
# If prompted for deploy's password, enter it
```

**If SSH to 127.0.0.1 fails**, use the machine's actual IP:

```bash
AGENT_IP=$(hostname -I | awk '{print $1}')
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/deploy_key.pub deploy@${AGENT_IP}
```

### Step 7: Verify SSH works

```bash
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/deploy_key -o StrictHostKeyChecking=no deploy@127.0.0.1 "echo OK"
# Should print: OK
```

(Use the agent IP instead of `127.0.0.1` if that's what you used in Step 6.)

### Step 8: Add credential to Jenkins

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)**
2. **Add Credentials**
3. **Kind:** SSH Username with private key
4. **Scope:** Global
5. **ID:** `deploy-ssh-key`
6. **Username:** `deploy`
7. **Private Key:** Enter directly
   - On the agent: `sudo cat /var/lib/jenkins/.ssh/deploy_key`
   - Paste the full output (including `-----BEGIN...` and `-----END...`)
8. **Add**

### Step 9: Update Jenkinsfile with the deploy host

Edit the `envConfig` block in `Jenkinsfile` (around lines 85–89). For Option A, use the agent's IP for all environments:

```groovy
// Get your agent IP with: hostname -I | awk '{print $1}'
def envConfig = [
    test: [host: '127.0.0.1', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    uat:  [host: '127.0.0.1', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    stage:[host: '127.0.0.1', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    prod: [host: '127.0.0.1', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
]
```

If `127.0.0.1` doesn't work (e.g. Jenkins runs in a container), use the agent's real IP:

```groovy
def envConfig = [
    test: [host: '192.168.1.100', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],  // replace with your agent IP
    uat:  [host: '192.168.1.100', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    stage:[host: '192.168.1.100', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    prod: [host: '192.168.1.100', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
]
```

> **Note:** All four environments pointing to the same host means each new deploy overwrites the previous one. That's fine for testing.

### Step 10: Open port 8080 (if firewall is on)

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## Option B: Separate Deploy VM (Your Setup)

**Your setup:** Deploy VM at `192.168.31.121` (Alma Linux). The **Jenkins agent** (e.g. `alma-agent-1`) runs the pipeline, so the **agent's** SSH public key must be in the deploy server's `authorized_keys`.

### Step 1: On the deploy VM (192.168.31.121)

```bash
# SSH to deploy VM
ssh your-user@192.168.31.121

# Create deploy user
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy

# Install Java
sudo dnf install -y java-21-openjdk
java -version

# Create app directory
sudo mkdir -p /home/deploy/petclinic
sudo chown deploy:deploy /home/deploy/petclinic

# Ensure ~/.ssh exists for deploy user
sudo -u deploy mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
```

### Step 2: On the Jenkins agent (alma-agent-1)

The agent runs the pipeline, so generate the key and add it to Jenkins:

```bash
# SSH to the Jenkins agent (the node that runs your pipeline)
ssh your-user@alma-agent-1

# Generate SSH key (as jenkins user)
sudo -u jenkins mkdir -p /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t ed25519 -N "" -f /var/lib/jenkins/.ssh/deploy_key

# Copy the public key to the deploy VM
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/deploy_key.pub deploy@192.168.31.121
# Enter deploy's password when prompted
```

### Step 3: Verify SSH from agent to deploy VM

```bash
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/deploy_key deploy@192.168.31.121 "echo OK"
# Should print: OK
```

### Step 4: Add credential to Jenkins

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)**
2. **Add Credentials**
3. **Kind:** SSH Username with private key
4. **ID:** `deploy-ssh-key`
5. **Username:** `deploy`
6. **Private Key:** Enter directly
   - On the agent: `sudo cat /var/lib/jenkins/.ssh/deploy_key`
   - Paste the full output (including `-----BEGIN...` and `-----END...`)
7. **Add**

### Step 5: Update Jenkinsfile

The `envConfig` in Jenkinsfile is already set to use `192.168.31.121` for test. For a single deploy VM, point all environments to it:

```groovy
def envConfig = [
    test: [host: '192.168.31.121', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    uat:  [host: '192.168.31.121', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    stage:[host: '192.168.31.121', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
    prod: [host: '192.168.31.121', user: 'deploy', creds: 'deploy-ssh-key', port: 8080],
]
```

### Step 6: Firewall on deploy VM (192.168.31.121)

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

### Summary: Who does what?

| Machine | Role |
|---------|------|
| **Jenkins agent** (alma-agent-1) | Runs the pipeline, executes deploy via SSH. Generate key here, add private key to Jenkins. |
| **Deploy VM** (192.168.31.121) | Receives the JAR, runs the app. Add agent's public key to `deploy` user's `authorized_keys`. |

---

## Required Jenkins plugins

Make sure these are installed:

- **SSH Agent** (for `sshagent` in the pipeline)
- **Pipeline** (core)

Check: **Manage Jenkins** → **Plugins** → **Installed**

---

## Quick checklist

- [ ] `deploy` user exists on deploy host
- [ ] Java 17+ on deploy host
- [ ] `/home/deploy/petclinic` exists and is owned by `deploy`
- [ ] SSH key generated: `/var/lib/jenkins/.ssh/deploy_key`
- [ ] Public key in `deploy` user's `~/.ssh/authorized_keys`
- [ ] `ssh -i deploy_key deploy@HOST "echo OK"` works
- [ ] Jenkins credential `deploy-ssh-key` added
- [ ] `envConfig` in Jenkinsfile uses correct host IP
- [ ] Port 8080 open on deploy host firewall

---

## Troubleshooting

| Problem | Check |
|--------|-------|
| Permission denied (publickey) | Key in `~/.ssh/authorized_keys`? Permissions: `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys` |
| Connection refused | SSH daemon: `sudo systemctl status sshd`; firewall allows SSH |
| Health check fails | App listening on 0.0.0.0? Firewall allows 8080? |
| Jenkins can't find credential | ID must be exactly `deploy-ssh-key` |
