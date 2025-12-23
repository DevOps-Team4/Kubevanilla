# Complete Deployment Guide - From Scratch to Production

[![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![Google Cloud](https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![Ansible](https://img.shields.io/badge/ansible-%231A1918.svg?style=for-the-badge&logo=ansible&logoColor=white)](https://ansible.com)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)

This guide provides the **complete step-by-step process** to deploy the entire infrastructure and application stack from scratch to a fully functional production environment.

## 📋 What You'll Deploy

By following this guide, you'll create:
- **20 GCP resources** including VPC, subnets, firewall rules, and VMs
- **4 Virtual Machines**: Bastion, Frontend, Backend, Database
- **PostgreSQL Database** with proper configuration
- **Docker Containers** running Todo application (frontend + backend)
- **Nginx Reverse Proxy** for web traffic routing
- **Complete Security Setup** with SSH keys and firewall rules

## ⏱️ Deployment Timeline

- **Total Time**: 15-25 minutes
- **Infrastructure**: 5-8 minutes (20 resources)
- **SSH Setup**: 2-3 minutes
- **Application Deployment**: 3-5 minutes
- **Testing & Verification**: 2-3 minutes

## 🚀 Complete Deployment Process

### **Phase 1: Environment Setup** (2-3 minutes)

#### 1.1 Clone Repository and Navigate
```bash
git clone https://github.com/DevOps-Team4/IaC.git
cd IaC/terraform
```

#### 1.2 Authenticate with Google Cloud
```bash
# Login to GCP
gcloud auth login

# Set your project (replace with your actual project ID)
gcloud config set project YOUR-PROJECT-ID
```

**⚠️ Important**: Make sure your `values/stage.tfvars` and `backend/stage.properties` files have the correct project ID and bucket name.

---

### **Phase 2: Production Infrastructure Setup** (5-8 minutes)

#### 2.1 Run Production Setup Script
This script creates service account, enables APIs, and sets up GCS bucket:
```bash
# Make script executable
chmod +x startscript.sh

# Execute setup (creates service account, bucket, enables APIs)
./startscript.sh
```

**What this creates:**
- ✅ Service account with required permissions
- ✅ GCS bucket for Terraform state
- ✅ All required GCP APIs enabled
- ✅ Database credentials in Secret Manager

#### 2.2 Set Service Account Credentials
```bash
export GOOGLE_APPLICATION_CREDENTIALS=terraform-sa-key.json
```

---

### **Phase 3: Deploy Infrastructure** (5-8 minutes)

#### 3.1 Initialize Terraform Backend
```bash
terraform init -backend-config=backend/stage.properties
```

#### 3.2 Plan and Deploy Infrastructure
```bash
# Preview what will be created (20 resources)
terraform plan -var-file=values/stage.tfvars

# Deploy infrastructure
terraform apply -var-file=values/stage.tfvars
```

**Infrastructure Created:**
- VPC network with public/private subnets
- NAT Gateway for private subnet internet access
- 6 Firewall rules for security
- 4 VM instances (bastion, frontend, backend, database)
- Cloud Router for NAT functionality

---

### **Phase 4: SSH Configuration** (2-3 minutes)

#### 4.1 Create SSH Directory and Copy Key
```bash
# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Copy provisioning key from terraform directory
cp .ssh/provisioning_key ~/.ssh/provisioning_key
chmod 600 ~/.ssh/provisioning_key
```

#### 4.2 Get Bastion IP from Terraform Output
```bash
# Get the bastion public IP
terraform output | grep bastion
# Note the IP address (e.g., 34.185.197.27)
```

#### 4.3 Create SSH Config File
```bash
nano ~/.ssh/config
```

Add the following content (replace `BASTION_IP` with actual IP):
```
Host bastion
  HostName BASTION_IP
  User provisioning
  IdentityFile ~/.ssh/provisioning_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host 10.1.*
  User provisioning
  IdentityFile ~/.ssh/provisioning_key
  IdentitiesOnly yes
  ProxyJump bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

#### 4.4 Set SSH Config Permissions
```bash
chmod 600 ~/.ssh/config
```

---

### **Phase 5: Configure Ansible** (1-2 minutes)

#### 5.1 Navigate to Ansible Directory
```bash
cd ../ansible
```

#### 5.2 Update Ansible Configuration
```bash
# Get your username
echo $USER

# Edit ansible.cfg
nano ansible.cfg
```

Update line 9 with your username:
```
ssh_args = -F /home/YOUR_USERNAME/.ssh/config -o ControlMaster=auto -o ControlPersist=60s
```

#### 5.3 Set Up GHCR Credentials
```bash
# Set GitHub Container Registry credentials
export GHCR_USER="your-github-username"
export GHCR_TOKEN="your-github-personal-access-token"
```

**Note**: You need a GitHub Personal Access Token with `read:packages` permission.

---

### **Phase 6: Test SSH Connectivity** (1 minute)

#### 6.1 Test Bastion Connection
```bash
ssh bastion
# Should connect without password, then exit
exit
```

#### 6.2 Test Private Host Connection
```bash
ssh provisioning@10.1.1.2
# Should connect via ProxyJump, then exit
exit
```

#### 6.3 Test Ansible Connectivity
```bash
ansible all -m ping --vault-password-file=.vault_pass
```

Expected output:
```
bastion | SUCCESS => {"ping": "pong"}
backend | SUCCESS => {"ping": "pong"}
frontend | SUCCESS => {"ping": "pong"}
database | SUCCESS => {"ping": "pong"}
```

---

### **Phase 7: Deploy Applications** (3-5 minutes)

#### 7.1 Run Complete Application Deployment
```bash
ansible-playbook -i inventory.ini playbooks/site.yml --vault-password-file=.vault_pass -v
```

**What this deploys:**
- ✅ Server preparation (Docker installation, security setup)
- ✅ Team user accounts on bastion host
- ✅ PostgreSQL database configuration
- ✅ Backend container deployment with database connection
- ✅ Frontend container deployment
- ✅ Nginx reverse proxy configuration

---

### **Phase 8: Verify Deployment** (1-2 minutes)

#### 8.1 Check Running Containers
```bash
ansible frontend,backend -i inventory.ini -m shell -a "docker ps" --vault-password-file=.vault_pass
```

Expected output:
```
frontend | CHANGED | rc=0 >>
CONTAINER ID   IMAGE                                        PORTS                     NAMES
cd0681c8aaa4   ghcr.io/devops-team4/todo-frontend:01c3a57   0.0.0.0:3000->80/tcp     frontend

backend | CHANGED | rc=0 >>
CONTAINER ID   IMAGE                                       PORTS                     NAMES
93fbc64713b0   ghcr.io/devops-team4/todo-backend:01c3a57   0.0.0.0:8080->8080/tcp   backend
```

#### 8.2 Get Frontend Public IP
```bash
# Go back to terraform directory to get frontend IP
cd ../terraform
terraform output | grep frontend
# Or check GCP Console -> Compute Engine -> VM instances
```

#### 8.3 Test Web Application
Open browser and navigate to:
```
http://FRONTEND_PUBLIC_IP
```

You should see the Todo application running!

---

## 📋 Quick Command Summary

For experienced users, here's the complete command sequence:

```bash
# === PHASE 1: SETUP ===
git clone https://github.com/DevOps-Team4/IaC.git
cd IaC/terraform
gcloud auth login
gcloud config set project YOUR-PROJECT-ID

# === PHASE 2: INFRASTRUCTURE ===
chmod +x startscript.sh && ./startscript.sh
export GOOGLE_APPLICATION_CREDENTIALS=terraform-sa-key.json
terraform init -backend-config=backend/stage.properties
terraform apply -var-file=values/stage.tfvars

# === PHASE 3: SSH SETUP ===
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cp .ssh/provisioning_key ~/.ssh/provisioning_key && chmod 600 ~/.ssh/provisioning_key
# Edit ~/.ssh/config with bastion IP from terraform output
chmod 600 ~/.ssh/config

# === PHASE 4: ANSIBLE ===
cd ../ansible
# Edit ansible.cfg with your home directory path
export GHCR_USER="your-username" && export GHCR_TOKEN="your-token"

# === PHASE 5: DEPLOYMENT ===
ansible all -m ping --vault-password-file=.vault_pass
ansible-playbook -i inventory.ini playbooks/site.yml --vault-password-file=.vault_pass -v

# === PHASE 6: VERIFY ===
ansible frontend,backend -i inventory.ini -m shell -a "docker ps" --vault-password-file=.vault_pass
# Access http://FRONTEND_PUBLIC_IP in browser
```

## 🎯 Final Architecture

After successful deployment:

```
┌─── Public Subnet (10.1.1.0/24) ────┐    ┌─── Private Subnet (10.1.2.0/24) ───┐
│                                     │    │                                     │
│  🖥️  Bastion Host                   │    │  🖥️  Backend Server                │
│      - SSH Gateway                  │    │      - Todo API (port 8080)        │
│      - Team user accounts           │    │      - Docker container             │
│                                     │    │                                     │
│  🌐 Frontend Server                 │    │  🗄️  Database Server               │
│      - Todo Web App                 │    │      - PostgreSQL                  │
│      - Nginx Reverse Proxy          │    │      - User: postgres              │
│      - Docker container             │    │      - DB: appdb                   │
│                                     │    │                                     │
└─────────────────────────────────────┘    └─────────────────────────────────────┘
         │                                           │
   Internet Gateway                          NAT Gateway
         │                                           │
    🌍 Internet                                 🌍 Internet
```

## ✅ Success Criteria

Your deployment is successful when:
- [ ] All 20 Terraform resources are created
- [ ] All 4 VMs are running and accessible
- [ ] SSH connectivity works to all hosts
- [ ] All Ansible playbooks execute without errors
- [ ] Frontend and backend containers are running
- [ ] Web application is accessible via browser
- [ ] API endpoints respond correctly

## 🚨 Troubleshooting

### Common Issues and Solutions

**1. Permission Denied - SSH Key**
```bash
chmod 600 ~/.ssh/provisioning_key
chmod 600 ~/.ssh/config
```

**2. Ansible SSH Connection Failed**
```bash
# Test SSH manually first
ssh bastion
ssh provisioning@10.1.1.2

# Check ansible.cfg has correct home directory path
grep ssh_args ansible/ansible.cfg
```

**3. Container Pull Failed**
```bash
# Check GHCR credentials
echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USER --password-stdin
```

**4. Web App Not Accessible**
```bash
# Check containers are running
ansible frontend,backend -i inventory.ini -m shell -a "docker ps" --vault-password-file=.vault_pass

# Check nginx is running
ansible frontend -i inventory.ini -m shell -a "systemctl status nginx" --vault-password-file=.vault_pass
```

### Getting Help

1. **Check Logs**: All commands show detailed output
2. **Validate Each Phase**: Don't proceed if previous phase failed
3. **Test Connectivity**: Use SSH tests before running Ansible
4. **Review Documentation**: Check main README.md for detailed configuration

## 🧹 Cleanup

To destroy everything:
```bash
cd terraform
terraform destroy -var-file=values/stage.tfvars
```

This will remove all infrastructure but keep:
- Service account (for future deployments)
- GCS bucket (with state history)
- SSH keys in ~/.ssh directory

---

## 🎉 Congratulations!

You now have a **fully functional, production-ready infrastructure** with:
- ✅ Secure networking and firewall rules
- ✅ Multi-tier application architecture
- ✅ Database with proper connectivity
- ✅ Containerized application deployment
- ✅ Load balancing and reverse proxy
- ✅ Team SSH access management

Your Todo application should be running at `http://FRONTEND_PUBLIC_IP` and ready for use! 🚀