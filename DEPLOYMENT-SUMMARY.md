# Kubernetes Cluster Deployment Summary

## 🎯 Overview

This document provides a complete guide for deploying and accessing a self-managed Kubernetes cluster on Google Cloud Platform using Terraform and Kubespray.

**Cluster Details:**
- **Environment**: Stage
- **Kubernetes Version**: v1.34.3
- **Container Runtime**: containerd 2.1.6
- **Network Plugin**: Calico
- **Nodes**: 1 Master + 2 Workers
- **Region**: europe-west3 (Frankfurt)

---

## 📋 Infrastructure Components

### Created Resources (25 total)

| Resource | Type | Specs | IP Address |
|----------|------|-------|------------|
| **Bastion Host** | e2-micro | 1 vCPU, 1GB RAM | Public: 34.40.119.219<br>Private: 10.1.1.3 |
| **K8s Master** | e2-standard-2 | 2 vCPU, 8GB RAM | Public: 35.198.108.205<br>Private: 10.1.1.2 |
| **K8s Worker 1** | e2-standard-2 | 2 vCPU, 8GB RAM | Private: 10.1.2.3 |
| **K8s Worker 2** | e2-standard-2 | 2 vCPU, 8GB RAM | Private: 10.1.2.4 |
| **PostgreSQL DB** | e2-micro | 1 vCPU, 1GB RAM | Private: 10.1.2.2 |

### Network Configuration
- **VPC**: k8s-vpc-stage
- **Public Subnet**: 10.1.1.0/24 (bastion, master)
- **Private Subnet**: 10.1.2.0/24 (workers, database)
- **NAT Gateway**: Enabled for private instances internet access
- **Firewall Rules**: 10 rules configured for secure cluster communication

---

## 🔧 Prerequisites

### Required Tools
```bash
# On your local machine
- Terraform >= 1.0
- Ansible >= 2.17.3
- Python 3.12+
- kubectl (optional for local access)
- gcloud CLI (for GCP authentication)
```

### Required Ansible Collections
```bash
# Install required Ansible collections (run after activating virtual environment)
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general:8.6.1
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install ansible.utils
```

### GCP Setup
1. Service account key: `terraform/terraform-sa-key.json`
2. Backend bucket: `terraform-11-12-2025-sytoss-bucket`
3. Project ID: `terraform-test-480809`

---

## 🚀 Deployment Steps

### Step 1: Initialize Git Submodules

Kubespray is included as a git submodule and must be initialized:

```bash
cd /path/to/Kubevanilla
git submodule update --init --recursive
```

**Verify:**
```bash
ls -la ansible/kubespray/
# Should show Kubespray files, not an empty directory
```

---

### Step 2: Setup Python Virtual Environment

```bash
cd /path/to/Kubevanilla

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install required Ansible version
pip install 'ansible-core>=2.17.3,<2.18.0'

# Install required Python libraries for Ansible filters
pip install netaddr

# Verify installation
ansible --version
# Should show: ansible [core 2.17.x]
```

---

### Step 3: Provision Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform with stage backend
terraform init -backend-config=backend/stage.properties

# Review the deployment plan
terraform plan -var-file=values/stage.tfvars

# Apply the configuration (creates 25 resources)
terraform apply -var-file=values/stage.tfvars

# Expected output:
# - all_instance_ips (internal IPs)
# - bastion_host_ip (public IP)
# - kubernetes_master_ips (public IP)
# - kubespray_inventory_path
```

**⏱️ Duration**: ~3-5 minutes

**Verify:**
```bash
# Check if instances are running
gcloud compute instances list --project=terraform-test-480809

# Test SSH to bastion
ssh -i ~/.ssh/provisioning_key provisioning@<BASTION_PUBLIC_IP> "echo 'Connected!'"
```

---

### Step 4: Setup SSH Configuration

Terraform automatically:
1. Generates SSH key pair at `terraform/.ssh/provisioning_key`
2. Creates Kubespray inventory at `kubespray/inventory/k8s-cluster/hosts.yaml`

**Copy SSH key to your home directory:**
```bash
mkdir -p ~/.ssh
cp terraform/.ssh/provisioning_key ~/.ssh/
chmod 600 ~/.ssh/provisioning_key
```

**Create SSH config** (`~/.ssh/config`):
```bash
# Bastion host
Host bastion
    HostName 34.40.119.219
    User provisioning
    IdentityFile ~/.ssh/provisioning_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Kubernetes Master (via bastion)
Host k8s-master k8s-master-1
    HostName 10.1.1.2
    User provisioning
    IdentityFile ~/.ssh/provisioning_key
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Kubernetes Workers (via bastion)
Host k8s-worker-1
    HostName 10.1.2.3
    User provisioning
    IdentityFile ~/.ssh/provisioning_key
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host k8s-worker-2
    HostName 10.1.2.4
    User provisioning
    IdentityFile ~/.ssh/provisioning_key
    ProxyJump bastion
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

**Test connectivity:**
```bash
ssh bastion "echo 'Bastion OK'"
ssh k8s-master-1 "echo 'Master OK'"
ssh k8s-worker-1 "echo 'Worker 1 OK'"
ssh k8s-worker-2 "echo 'Worker 2 OK'"
```

---

### Step 5: Deploy Kubernetes with Kubespray

```bash
cd /path/to/Kubevanilla
source .venv/bin/activate

cd ansible/kubespray

# Install required Ansible collections for root user
ansible-galaxy collection install --force ansible.posix community.general kubernetes.core ansible.utils

# Deploy Kubernetes cluster
ansible-playbook \
  -i ../../kubespray/inventory/k8s-cluster/hosts.yaml \
  --become \
  --become-user=root \
  cluster.yml
```

**⏱️ Duration**: ~15-30 minutes

**What happens:**
1. Bootstrap OS packages on all nodes
2. Install container runtime (containerd)
3. Setup Kubernetes control plane on master
4. Join worker nodes to cluster
5. Deploy Calico network plugin
6. Install cluster addons (CoreDNS, metrics-server, etc.)

**Monitor progress:**
The playbook shows task execution with timestamps. Key phases:
- `Bootstrap hosts for Ansible` (~5 min)
- `Install container runtime` (~3 min)
- `Set up control plane` (~10 min)
- `Join nodes to cluster` (~5 min)
- `Deploy network plugin` (~7 min)

---

### Step 6: Setup Bastion with kubectl

```bash
cd ansible

# Install kubectl on bastion and configure team access
ansible-playbook \
  -i inventory.ini \
  playbooks/bastion.yml \
  --vault-password-file .vault_pass
```

**⏱️ Duration**: ~2 minutes

**What this does:**
- Installs kubectl v1.32.0 on bastion
- Configures kubectl bash completion
- Sets up team user accounts (if configured)

---

### Step 7: Copy kubeconfig to Bastion

```bash
# From your local machine
ssh k8s-master-1 "sudo cat /etc/kubernetes/admin.conf" | \
  ssh bastion "mkdir -p ~/.kube && cat > ~/.kube/config && chmod 600 ~/.kube/config"

# Verify
ssh bastion "kubectl get nodes"
```

**Expected output:**
```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master-1   Ready    control-plane   41m   v1.34.3
k8s-worker-1   Ready    <none>          40m   v1.34.3
k8s-worker-2   Ready    <none>          40m   v1.34.3
```

---

## ✅ Verification Commands

### Check Infrastructure
```bash
# From local machine
cd terraform

# View all outputs
terraform output

# Check specific IPs
terraform output bastion_host_ip
terraform output kubernetes_master_ips
terraform output kubernetes_worker_ips
```

### Check Kubernetes Cluster
```bash
# SSH to bastion first
ssh bastion

# Then run kubectl commands
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl version
```

### Verify Network Connectivity
```bash
# From local machine

# Test bastion
ssh bastion "hostname && date"

# Test master (through bastion)
ssh k8s-master-1 "hostname && date"

# Test workers (through bastion)
ssh k8s-worker-1 "hostname && date"
ssh k8s-worker-2 "hostname && date"

# Test Ansible connectivity
cd ansible
ansible all -i ../kubespray/inventory/k8s-cluster/hosts.yaml -m ping
```

### Check Cluster Components
```bash
# From bastion
ssh bastion

# Check all system pods
kubectl get pods -n kube-system

# Expected pods:
# - calico-* (network plugin)
# - coredns-* (DNS)
# - kube-apiserver-* (API server)
# - kube-controller-manager-* (controller)
# - kube-scheduler-* (scheduler)
# - kube-proxy-* (network proxy)

# Check cluster info
kubectl cluster-info dump | grep -i "cluster-info"
```

---

## 📁 Important Files & Their Purpose

### Terraform Files
```
terraform/
├── main.tf                          # Main infrastructure definition
├── variables.tf                     # Variable declarations
├── outputs.tf                       # Output definitions
├── values/stage.tfvars              # Stage environment configuration
├── backend/stage.properties         # Terraform state backend config
├── terraform-sa-key.json            # GCP service account key (gitignored)
├── .ssh/provisioning_key            # Generated SSH private key (gitignored)
└── modules/                         # Reusable Terraform modules
    ├── network/                     # VPC, subnets, routes
    ├── firewall/                    # Security rules
    ├── nat-gateway/                 # NAT for private instances
    ├── instance/                    # VM instances
    └── db/                          # Database instance

Generated by Terraform:
kubespray/inventory/k8s-cluster/hosts.yaml  # Kubespray inventory
```

### Ansible Files
```
ansible/
├── ansible.cfg                      # Ansible configuration
├── inventory.ini                    # Main inventory (for bastion setup)
├── .vault_pass                      # Ansible vault password (gitignored)
├── playbooks/
│   ├── bastion.yml                  # Bastion setup + kubectl install
│   ├── kubernetes.yml               # Kubernetes deployment wrapper
│   ├── prepare-servers.yml          # Server preparation tasks
│   └── site.yml                     # Master playbook
└── group_vars/
    └── k8s_cluster/
        ├── k8s-cluster.yml          # Kubernetes configuration
        └── addons.yml               # Cluster addons config

Kubespray (submodule):
ansible/kubespray/                   # Kubespray repository
└── cluster.yml                      # Main Kubespray playbook
```

### Configuration Files
```
.gitignore                           # Git ignore rules
.gitmodules                          # Git submodule configuration
~/.ssh/config                        # SSH configuration (on your machine)
~/.ssh/provisioning_key              # SSH private key (on your machine)
~/.kube/config-sytoss-stage          # Kubernetes config (local reference)
```

---

## 🔒 Security Notes

### SSH Access
- **Bastion**: Only entry point with public SSH access (port 22)
- **Master**: Has public IP but SSH only from bastion (firewall restricted)
- **Workers**: No public IP, only accessible via bastion
- **Database**: No public IP, only accessible from k8s nodes

### Firewall Rules
1. `fw-bastion-ssh-stage`: Allow SSH (22) to bastion from anywhere
2. `fw-k8s-api-external-stage`: Allow k8s API (6443) to master from anywhere
3. `fw-k8s-ssh-from-bastion-stage`: Allow SSH from bastion to all nodes
4. `fw-database-access-stage`: Allow PostgreSQL (5432) from k8s nodes
5. `fw-k8s-master-internal-stage`: Master-to-master communication
6. `fw-k8s-master-to-worker-stage`: Master-to-worker communication
7. `fw-k8s-worker-to-master-stage`: Worker-to-master communication
8. `fw-k8s-nodeport-stage`: NodePort services (30000-32767)
9. `fw-k8s-internal-all-stage`: All internal k8s communication
10. `fw-k8s-https-stage`: HTTPS (443) to workers

### Kubernetes API Access
- **From Internet**: https://35.198.108.205:6443 (requires valid kubeconfig)
- **From Bastion**: https://10.1.1.2:6443 (internal IP, TLS verified)
- **Certificate**: Valid for 10.233.0.1, 10.1.1.2, 127.0.0.1 (not public IP)

---

## 🔄 Update Procedures

### Update Kubernetes Configuration
```bash
# Edit configuration
vim ansible/group_vars/k8s_cluster/k8s-cluster.yml

# Apply changes
cd ansible/kubespray
ansible-playbook -i ../../kubespray/inventory/k8s-cluster/hosts.yaml upgrade-cluster.yml
```

### Update Infrastructure
```bash
cd terraform

# Make changes to *.tfvars or *.tf files

# Preview changes
terraform plan -var-file=values/stage.tfvars

# Apply changes
terraform apply -var-file=values/stage.tfvars

# Regenerate inventory if IPs changed
terraform apply -var-file=values/stage.tfvars -target=local_file.kubespray_inventory
```

### Update Bastion Configuration
```bash
cd ansible

# Edit playbooks/bastion.yml if needed

# Apply changes
ansible-playbook -i inventory.ini playbooks/bastion.yml --vault-password-file .vault_pass
```

---

## 🗑️ Cleanup / Destroy

### Destroy Everything
```bash
cd terraform

# Review what will be destroyed
terraform plan -destroy -var-file=values/stage.tfvars

# Destroy all resources
terraform destroy -var-file=values/stage.tfvars

# Confirm: yes
```

**⏱️ Duration**: ~5 minutes

**What gets deleted:**
- All VM instances (bastion, master, workers, database)
- VPC network and subnets
- NAT gateway and router
- Firewall rules
- Generated SSH keys (local files remain)

---

## 🐛 Troubleshooting

### Issue: Cannot SSH to Bastion
```bash
# Check bastion IP in GCP
gcloud compute instances describe bastion-host \
  --project=terraform-test-480809 \
  --zone=europe-west3-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'

# Update SSH config with correct IP
vim ~/.ssh/config

# Test connection with verbose output
ssh -vvv bastion
```

### Issue: Cannot Access Kubernetes Cluster
```bash
# Verify nodes are running
ssh bastion "kubectl get nodes"

# Check component status
ssh bastion "kubectl get componentstatuses"

# Check pod status
ssh bastion "kubectl get pods -A | grep -v Running"

# View logs of failing pods
ssh bastion "kubectl logs -n kube-system <pod-name>"
```

### Issue: Ansible Cannot Connect to Nodes
```bash
# Test connectivity
cd ansible
ansible all -i ../kubespray/inventory/k8s-cluster/hosts.yaml -m ping -vvv

# Check SSH config
cat ~/.ssh/config

# Test direct SSH
ssh -vvv k8s-master-1
```

### Issue: Terraform State Issues
```bash
cd terraform

# Refresh state from actual infrastructure
terraform refresh -var-file=values/stage.tfvars

# Import existing resource (if needed)
terraform import -var-file=values/stage.tfvars \
  google_compute_instance.vm["bastion-host"] \
  projects/terraform-test-480809/zones/europe-west3-a/instances/bastion-host
```

### Issue: Ansible Collection Module Not Found
```bash
# If you see errors like "couldn't resolve module/action 'ansible.posix.mount'"
# or "couldn't resolve module/action 'community.general.ini_file'"

# Install required collections for root user (if running as root)
ansible-galaxy collection install --force ansible.posix community.general kubernetes.core ansible.utils

# Verify collections are installed
ansible-galaxy collection list | grep -E "(posix|general|kubernetes|utils)"
```

### Issue: Ansible Filter Not Available
```bash
# If you see "Could not load 'ansible.utils.ipaddr'" error

# Install the ansible.utils collection
ansible-galaxy collection install ansible.utils

# Install required Python library
pip install netaddr

# Verify filter is available
ansible -m debug -a "msg={{ '127.0.0.1' | ansible.utils.ipaddr }}" localhost
```

### Issue: Python Library Missing for Ansible Filters
```bash
# If you see "Failed to import the required Python library (netaddr)"

# Install netaddr in your virtual environment
source .venv/bin/activate
pip install netaddr

# Verify installation
python3 -c "import netaddr; print('netaddr available')"
```

---

## 📚 Additional Resources

### Official Documentation
- [Kubespray](https://github.com/kubernetes-sigs/kubespray)
- [Kubernetes](https://kubernetes.io/docs/)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Ansible](https://docs.ansible.com/)

### Key Configuration Files
- Kubernetes version: `ansible/group_vars/k8s_cluster/k8s-cluster.yml` → `kube_version`
- Network CIDRs: `ansible/group_vars/k8s_cluster/k8s-cluster.yml` → `kube_service_addresses`, `kube_pods_subnet`
- VM specs: `terraform/values/stage.tfvars` → `vm_instances`
- Cluster addons: `ansible/group_vars/k8s_cluster/addons.yml`

---

## 👥 Team Collaboration

### For New Team Members

1. **Clone the repository:**
   ```bash
   git clone https://github.com/DevOps-Team4/Kubevanilla.git
   cd Kubevanilla
   git checkout integration-yn
   ```

2. **Initialize submodules:**
   ```bash
   git submodule update --init --recursive
   ```

3. **Get SSH key from team lead:**
   - Ask for `provisioning_key` file
   - Place in `~/.ssh/provisioning_key`
   - Set permissions: `chmod 600 ~/.ssh/provisioning_key`

4. **Setup SSH config:**
   - Copy the SSH config example above to `~/.ssh/config`
   - Update bastion IP if changed

5. **Access the cluster:**
   ```bash
   ssh bastion
   kubectl get nodes
   ```

### Sharing Access

**Option 1: Add user to bastion** (Recommended)
```bash
# Add user SSH key to ansible/group_vars/all/secret.yml
# Then run:
cd ansible
ansible-playbook -i inventory.ini playbooks/bastion.yml --vault-password-file .vault_pass
```

**Option 2: Share kubeconfig** (For kubectl from local machine)
```bash
# User needs to set up port forwarding
ssh -L 6443:10.1.1.2:6443 bastion -N &

# Then use kubeconfig with:
# server: https://localhost:6443
```

---

## 📊 Cluster Specifications

### Kubernetes Configuration
- **Version**: v1.34.3
- **Container Runtime**: containerd 2.1.6
- **Network Plugin**: Calico
- **Service CIDR**: 10.233.0.0/18
- **Pod CIDR**: 10.233.64.0/18
- **DNS**: CoreDNS with NodeLocalDNS
- **Metrics**: metrics-server enabled
- **Ingress**: nginx-ingress enabled

### Installed Addons
- ✅ CoreDNS (cluster DNS)
- ✅ NodeLocalDNS (DNS caching)
- ✅ metrics-server (resource metrics)
- ✅ nginx-ingress (ingress controller)
- ✅ Helm v3.13.0
- ✅ local-path-provisioner (persistent volumes)

### Resource Limits
- Master node: 2 vCPU, 8GB RAM
- Worker nodes: 2 vCPU, 8GB RAM each
- Maximum pods per node: 110
- Memory requirements: 900MB minimum (configured for current setup)

---

## 🎓 What We Accomplished

### Infrastructure as Code
✅ Modular Terraform setup with separate modules for network, firewall, instances
✅ Backend state stored in GCS bucket
✅ Environment-specific tfvars files (stage, prod)
✅ Automated SSH key generation and distribution
✅ Dynamic inventory generation for Kubespray

### Ansible Automation
✅ Kubespray integrated as git submodule
✅ Custom playbooks for bastion and cluster setup
✅ Automated kubectl installation
✅ Proper SSH proxy configuration via bastion
✅ Ansible vault for secrets management

### Kubernetes Cluster
✅ Self-managed Kubernetes cluster (not GKE)
✅ High availability ready (can scale to 3 masters)
✅ Production-grade network setup with Calico
✅ Security-first approach with bastion host
✅ Metrics and monitoring enabled

### Security Best Practices
✅ Bastion host as single entry point
✅ Private subnets for workers and database
✅ Firewall rules limiting access
✅ SSH key-based authentication only
✅ TLS certificate validation for k8s API

---

## 📝 Notes

- This cluster is deployed in **europe-west3 (Frankfurt)** region
- All times are in **UTC**
- Terraform state is stored remotely in GCS
- SSH keys are auto-generated by Terraform
- The cluster uses **private IPs** for internal communication
- Public IP on master is **only for k8s API access** (port 6443)

---

**Deployed on**: December 29, 2025  
**Branch**: integration-yn  
**Repository**: DevOps-Team4/Kubevanilla  

---

*For questions or issues, contact the DevOps team or check the troubleshooting section above.*
