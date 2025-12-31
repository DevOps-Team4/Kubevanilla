# Infrastructure Creation - Step by Step Technical Guide

## 📐 Overview

This document explains exactly how the infrastructure gets created, what happens at each step, and the order of resource creation in Google Cloud Platform using Terraform.

---

## 🔄 Infrastructure Creation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. Terraform Initialization                   │
│                    terraform init                                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    2. Network Layer Creation                     │
│              VPC → Subnets → Routes → NAT                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    3. Security Layer Creation                    │
│                    Firewall Rules (10 rules)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    4. SSH Key Generation                         │
│              TLS Private Key → Local Files                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    5. Compute Instances Creation                 │
│        Bastion → Master → Workers → Database (parallel)         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    6. Inventory Generation                       │
│           Kubespray hosts.yaml + SSH key export                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📝 Step-by-Step Execution

### Step 1: Terraform Initialization (terraform init)

**What happens:**
```bash
cd terraform
terraform init -backend-config=backend/stage.properties
```

**Behind the scenes:**
1. **Downloads provider plugins:**
   - `google` provider (hashicorp/google) ~5.x
   - `tls` provider (hashicorp/tls) ~4.x
   - `local` provider (hashicorp/local) ~2.x

2. **Configures remote backend:**
   - Reads `backend/stage.properties`:
     ```properties
     bucket = "terraform-11-12-2025-sytoss-bucket"
     prefix = "terraform/state/stage"
     ```
   - Connects to GCS bucket: `gs://terraform-11-12-2025-sytoss-bucket/terraform/state/stage/`
   - Downloads existing state file (if any) or creates new one

3. **Initializes modules:**
   - `module.network` → `modules/network/`
   - `module.firewall` → `modules/firewall/`
   - `module.nat_gateway` → `modules/nat-gateway/`
   - `module.instances` → `modules/instance/`
   - `module.db` → `modules/db/`

**Files created:**
```
terraform/.terraform/
terraform/.terraform.lock.hcl
```

**Duration:** ~10-30 seconds

---

### Step 2: Network Layer Creation

**Execution order:**

#### 2.1 Enable Compute API
```hcl
google_project_service.compute_api
```
**Action:** Enables `compute.googleapis.com` API for the GCP project  
**Duration:** ~1-2 seconds (usually already enabled)

#### 2.2 Create VPC Network
```hcl
module.network.module.vpc.module.vpc.google_compute_network.network
```
**Resource:** `k8s-vpc-stage`  
**Configuration:**
- Type: Custom VPC
- Auto-create subnets: `false` (manual subnet creation)
- Routing mode: `REGIONAL`
- MTU: 1460 (default)

**GCP API Call:**
```
POST https://compute.googleapis.com/compute/v1/projects/terraform-test-480809/global/networks
{
  "name": "k8s-vpc-stage",
  "autoCreateSubnetworks": false,
  "routingConfig": {
    "routingMode": "REGIONAL"
  }
}
```

**Duration:** ~5-10 seconds

#### 2.3 Create Subnets (Parallel)

**Public Subnet:**
```hcl
module.network.module.vpc.module.subnets.google_compute_subnetwork.subnetwork["europe-west3/k8s-vpc-public-stage"]
```
**Configuration:**
- Name: `k8s-vpc-public-stage`
- Region: `europe-west3`
- IP CIDR: `10.1.1.0/24` (254 usable IPs)
- Private Google Access: `enabled` (for GCP APIs)
- Flow Logs: `enabled` (5sec interval, 50% sampling)

**IP Range Breakdown:**
```
10.1.1.0   - Network address
10.1.1.1   - Gateway (GCP reserved)
10.1.1.2   - Master node
10.1.1.3   - Bastion host
10.1.1.4-254 - Available for future use
10.1.1.255 - Broadcast address
```

**Private Subnet:**
```hcl
module.network.module.vpc.module.subnets.google_compute_subnetwork.subnetwork["europe-west3/k8s-vpc-private-stage"]
```
**Configuration:**
- Name: `k8s-vpc-private-stage`
- Region: `europe-west3`
- IP CIDR: `10.1.2.0/24` (254 usable IPs)
- Private Google Access: `enabled`
- Flow Logs: `enabled`

**IP Range Breakdown:**
```
10.1.2.0   - Network address
10.1.2.1   - Gateway (GCP reserved)
10.1.2.2   - Database
10.1.2.3   - Worker 1
10.1.2.4   - Worker 2
10.1.2.5-254 - Available for future workers
10.1.2.255 - Broadcast address
```

**Duration:** ~10-15 seconds each (parallel)

#### 2.4 Create Cloud Router
```hcl
module.nat_gateway.google_compute_router.router[0]
```
**Resource:** `k8s-vpc-router-stage`  
**Purpose:** Required for Cloud NAT (private instances internet access)  
**Configuration:**
- Network: `k8s-vpc-stage`
- Region: `europe-west3`
- BGP ASN: `64514`
- Keepalive interval: `20s`

**Duration:** ~3-5 seconds

#### 2.5 Create Cloud NAT Gateway
```hcl
module.nat_gateway.google_compute_router_nat.nat_gateway[0]
```
**Resource:** `k8s-vpc-nat-stage`  
**Purpose:** Allows private instances (workers, database) to reach internet  
**Configuration:**
- NAT IP allocation: `AUTO_ONLY` (GCP assigns IPs automatically)
- Source subnets: `k8s-vpc-private-stage` only
- IP ranges to NAT: `ALL_IP_RANGES` in private subnet
- Min ports per VM: Dynamic
- Logging: `ERRORS_ONLY`

**What it enables:**
- Worker nodes can pull Docker images from internet registries
- Database can download packages (apt, pip)
- Instances can reach GCP APIs
- **Outbound only** - no inbound connections to private instances

**Duration:** ~10-15 seconds

#### 2.6 Create Default Route
```hcl
module.network.module.vpc.module.routes.google_compute_route.route["egress-internet-stage"]
```
**Resource:** `egress-internet-stage`  
**Purpose:** Default route to internet gateway for public subnet  
**Configuration:**
- Destination: `0.0.0.0/0` (all internet traffic)
- Next hop: `default-internet-gateway`
- Priority: `1000`
- Network tags: `internet-stage`

**Duration:** ~2-3 seconds

---

### Step 3: Security Layer (Firewall Rules)

**All firewall rules created in parallel (~10-15 seconds total)**

#### 3.1 Bastion SSH Access
```hcl
module.firewall.google_compute_firewall.bastion_ssh
```
**Rule:** `fw-bastion-ssh-stage`  
**Purpose:** Allow SSH to bastion from anywhere  
**Configuration:**
```
Direction: INGRESS
Source: 0.0.0.0/0 (internet)
Target tags: bastion
Protocol/Ports: tcp/22
Priority: 1000
```
**Security note:** Bastion is the ONLY entry point with public SSH access

#### 3.2 Kubernetes API External Access
```hcl
module.firewall.google_compute_firewall.k8s_api_external
```
**Rule:** `fw-k8s-api-external-stage`  
**Purpose:** Allow kubectl/API access to master from internet  
**Configuration:**
```
Direction: INGRESS
Source: 0.0.0.0/0
Target tags: k8s-master
Protocol/Ports: tcp/6443
Priority: 1000
```

#### 3.3 SSH from Bastion to All Nodes
```hcl
module.firewall.google_compute_firewall.k8s_ssh_from_bastion
```
**Rule:** `fw-k8s-ssh-from-bastion-stage`  
**Purpose:** Allow SSH from bastion to all cluster nodes  
**Configuration:**
```
Direction: INGRESS
Source tags: bastion
Target tags: k8s-master, k8s-worker, postgres
Protocol/Ports: tcp/22
Priority: 1000
```
**Security note:** Private nodes ONLY accept SSH from bastion

#### 3.4 Database Access
```hcl
module.firewall.google_compute_firewall.database_access
```
**Rule:** `fw-database-access-stage`  
**Purpose:** Allow PostgreSQL access from k8s nodes  
**Configuration:**
```
Direction: INGRESS
Source tags: kubernetes
Target tags: postgres
Protocol/Ports: tcp/5432
Priority: 1000
```

#### 3.5 Master Internal Communication
```hcl
module.firewall.google_compute_firewall.k8s_master_internal
```
**Rule:** `fw-k8s-master-internal-stage`  
**Purpose:** Allow etcd and control plane communication between masters  
**Configuration:**
```
Direction: INGRESS
Source tags: k8s-master
Target tags: k8s-master
Protocol/Ports: tcp/2379,2380,10250,10251,10252
Priority: 1000
```
**Ports explained:**
- 2379-2380: etcd client/peer communication
- 10250: kubelet API
- 10251: kube-scheduler
- 10252: kube-controller-manager

#### 3.6 Master to Worker Communication
```hcl
module.firewall.google_compute_firewall.k8s_master_to_worker
```
**Rule:** `fw-k8s-master-to-worker-stage`  
**Configuration:**
```
Direction: INGRESS
Source tags: k8s-master
Target tags: k8s-worker
Protocol/Ports: tcp/10250
Priority: 1000
```
**Purpose:** Master sends commands to worker kubelets

#### 3.7 Worker to Master Communication
```hcl
module.firewall.google_compute_firewall.k8s_worker_to_master
```
**Rule:** `fw-k8s-worker-to-master-stage`  
**Configuration:**
```
Direction: INGRESS
Source tags: k8s-worker
Target tags: k8s-master
Protocol/Ports: tcp/6443
Priority: 1000
```
**Purpose:** Workers connect to API server

#### 3.8 NodePort Services
```hcl
module.firewall.google_compute_firewall.k8s_nodeport
```
**Rule:** `fw-k8s-nodeport-stage`  
**Configuration:**
```
Direction: INGRESS
Source: 0.0.0.0/0
Target tags: kubernetes
Protocol/Ports: tcp/30000-32767
Priority: 1000
```
**Purpose:** Allow external access to NodePort services

#### 3.9 Internal Kubernetes Traffic
```hcl
module.firewall.google_compute_firewall.k8s_internal_all
```
**Rule:** `fw-k8s-internal-all-stage`  
**Configuration:**
```
Direction: INGRESS
Source tags: kubernetes
Target tags: kubernetes
Protocol/Ports: ALL
Priority: 1000
```
**Purpose:** Allow all traffic between k8s nodes (pods, overlay network)

#### 3.10 HTTPS to Workers
```hcl
module.firewall.google_compute_firewall.k8s_https
```
**Rule:** `fw-k8s-https-stage`  
**Configuration:**
```
Direction: INGRESS
Source: 0.0.0.0/0
Target tags: k8s-worker
Protocol/Ports: tcp/443
Priority: 1000
```
**Purpose:** Allow HTTPS traffic to ingress controllers

---

### Step 4: SSH Key Generation

#### 4.1 Generate TLS Private Key
```hcl
tls_private_key.provisioning_key
```
**Action:** Generates 4096-bit RSA key pair in memory  
**Algorithm:** RSA  
**Bits:** 4096 (high security)  

**Generated keys:**
- Private key: PEM format
- Public key: OpenSSH format

**Duration:** ~1-2 seconds

#### 4.2 Save Private Key to Local File
```hcl
local_file.provisioning_private_key
```
**File:** `terraform/.ssh/provisioning_key`  
**Permissions:** `0600` (read/write for owner only)  
**Content:** PEM-encoded private key  

**Example key structure:**
```
-----BEGIN RSA PRIVATE KEY-----
MIIJKAIBAAKCAgEAnt4Blt6o59YYyKeWRWYPe6poirwl...
[4096 bits of encrypted key data]
-----END RSA PRIVATE KEY-----
```

**Duration:** <1 second

---

### Step 5: Compute Instances Creation

**All instances created in parallel (~30-60 seconds total)**

#### 5.1 Bastion Host
```hcl
module.instances.google_compute_instance.vm["bastion-host"]
```

**Specifications:**
```yaml
Name: bastion-host
Zone: europe-west3-a
Machine Type: e2-micro (2 vCPU shared, 1GB RAM)
Boot Disk:
  Image: ubuntu-2204-jammy (Ubuntu 22.04 LTS)
  Size: 10GB
  Type: pd-standard (HDD)
Network:
  Subnet: k8s-vpc-public-stage
  Internal IP: 10.1.1.3 (static)
  External IP: Auto-assigned (ephemeral)
Tags: [bastion]
```

**Metadata:**
```yaml
enable-oslogin: "FALSE"
ssh-keys: "provisioning:ssh-rsa AAAAB3Nza..."
startup-script: |
  #!/bin/bash
  apt-get update
  apt-get install -y python3 python3-pip
```

**Startup sequence:**
1. Instance boots with Ubuntu 22.04
2. Startup script runs as root
3. Updates package lists
4. Installs Python 3 (required for Ansible)
5. SSH key is authorized for `provisioning` user

**API Call:**
```
POST https://compute.googleapis.com/compute/v1/projects/terraform-test-480809/zones/europe-west3-a/instances
```

**Duration:** ~20-30 seconds

#### 5.2 Kubernetes Master
```hcl
module.instances.google_compute_instance.vm["k8s-master-1"]
```

**Specifications:**
```yaml
Name: k8s-master-1
Zone: europe-west3-a
Machine Type: e2-standard-2 (2 vCPU, 8GB RAM)
Boot Disk:
  Image: ubuntu-2204-jammy
  Size: 20GB
  Type: pd-standard
Network:
  Subnet: k8s-vpc-public-stage
  Internal IP: 10.1.1.2 (static)
  External IP: Auto-assigned
Tags: [k8s-master, kubernetes]
```

**Why public subnet:**
- External API access (kubectl from internet)
- Can be converted to internal-only with load balancer later
- Firewall restricts to port 6443 only

**Resource allocation:**
- CPU: 2 vCPU (sufficient for control plane)
- RAM: 8GB (etcd + api-server + controller-manager + scheduler)
- Disk: 20GB (container images, etcd data, logs)

**Duration:** ~30-40 seconds

#### 5.3 Kubernetes Worker 1
```hcl
module.instances.google_compute_instance.vm["k8s-worker-1"]
```

**Specifications:**
```yaml
Name: k8s-worker-1
Zone: europe-west3-b (different zone for HA)
Machine Type: e2-standard-2 (2 vCPU, 8GB RAM)
Boot Disk:
  Image: ubuntu-2204-jammy
  Size: 20GB
  Type: pd-standard
Network:
  Subnet: k8s-vpc-private-stage
  Internal IP: 10.1.2.3 (static)
  External IP: none (NAT for internet)
Tags: [k8s-worker, kubernetes]
```

**Network access:**
- ✅ Outbound internet via NAT gateway
- ✅ SSH via bastion (ProxyJump)
- ❌ No direct inbound from internet

**Duration:** ~30-40 seconds

#### 5.4 Kubernetes Worker 2
```hcl
module.instances.google_compute_instance.vm["k8s-worker-2"]
```

**Specifications:**
```yaml
Name: k8s-worker-2
Zone: europe-west3-c (different zone for HA)
Machine Type: e2-standard-2 (2 vCPU, 8GB RAM)
Boot Disk:
  Image: ubuntu-2204-jammy
  Size: 20GB
  Type: pd-standard
Network:
  Subnet: k8s-vpc-private-stage
  Internal IP: 10.1.2.4 (static)
  External IP: none
Tags: [k8s-worker, kubernetes]
```

**Zone distribution:**
- Master: zone-a
- Worker-1: zone-b
- Worker-2: zone-c
- **Purpose:** Survive zonal failures

**Duration:** ~30-40 seconds

#### 5.5 PostgreSQL Database
```hcl
module.db.google_compute_instance.postgres
```

**Specifications:**
```yaml
Name: postgres-db
Zone: europe-west3-a
Machine Type: e2-micro (2 vCPU shared, 1GB RAM)
Boot Disk:
  Image: ubuntu-2204-jammy
  Size: 20GB
  Type: pd-standard
Network:
  Subnet: k8s-vpc-private-stage
  Internal IP: 10.1.2.2 (static)
  External IP: none
Tags: [postgres]
```

**Startup script:**
```bash
#!/bin/bash
apt-get update
apt-get install -y postgresql-14 python3
systemctl enable postgresql
systemctl start postgresql
```

**Duration:** ~25-35 seconds

---

### Step 6: Post-Creation Configuration

#### 6.1 Generate Kubespray Inventory
```hcl
local_file.kubespray_inventory
```

**Action:** Creates Ansible inventory for Kubespray deployment  
**File:** `kubespray/inventory/k8s-cluster/hosts.yaml`  

**Template rendering process:**
1. Reads `terraform/kubespray-inventory.tpl`
2. Extracts IPs from instance resources:
   ```hcl
   bastion_ip = module.instances.vm_instances["bastion-host"].network_interface[0].access_config[0].nat_ip
   master_ip = module.instances.vm_instances["k8s-master-1"].network_interface[0].network_ip
   worker1_ip = module.instances.vm_instances["k8s-worker-1"].network_interface[0].network_ip
   worker2_ip = module.instances.vm_instances["k8s-worker-2"].network_interface[0].network_ip
   ```
3. Substitutes variables in template
4. Writes final YAML file

**Generated inventory structure:**
```yaml
all:
  hosts:
    k8s-master-1:
      ansible_host: 10.1.1.2
      ansible_user: provisioning
      ansible_ssh_private_key_file: ~/.ssh/provisioning_key
      ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p -q provisioning@34.40.119.219"'
    k8s-worker-1:
      ansible_host: 10.1.2.3
      # ... same SSH config
    k8s-worker-2:
      ansible_host: 10.1.2.4
      # ... same SSH config
  children:
    kube_control_plane:
      hosts:
        k8s-master-1: {}
    kube_node:
      hosts:
        k8s-worker-1: {}
        k8s-worker-2: {}
    etcd:
      hosts:
        k8s-master-1: {}
    k8s_cluster:
      children:
        kube_control_plane: {}
        kube_node: {}
```

**Duration:** <1 second

#### 6.2 Output Display
Terraform displays all outputs:
```
Outputs:

all_instance_ips = {
  "bastion-host" = "10.1.1.3"
  "k8s-master-1" = "10.1.1.2"
  "k8s-worker-1" = "10.1.2.3"
  "k8s-worker-2" = "10.1.2.4"
}
bastion_host_ip = "34.40.119.219"
kubernetes_master_ips = {
  "k8s-master-1" = "35.198.108.205"
}
kubernetes_worker_ips = {
  "k8s-worker-1" = "10.1.2.3"
  "k8s-worker-2" = "10.1.2.4"
}
kubespray_inventory_path = "./../kubespray/inventory/k8s-cluster/hosts.yaml"
vpc_network_name = "k8s-vpc-stage"
```

#### 6.3 State File Update
```
Local actions:
- Save state to: .terraform/terraform.tfstate (local)
- Upload state to: gs://terraform-11-12-2025-sytoss-bucket/terraform/state/stage/default.tfstate
- Create state backup: terraform.tfstate.backup
```

**Duration:** ~2-3 seconds

---

## 📊 Complete Resource Creation Order

**Detailed dependency graph:**

```
1. google_project_service.compute_api
   ↓
2. google_compute_network.network (VPC)
   ↓
3. ├─ google_compute_subnetwork (public)
   └─ google_compute_subnetwork (private)
   ↓
4. ├─ google_compute_router
   │  ↓
   │  google_compute_router_nat
   └─ google_compute_route (internet route)
   ↓
5. google_compute_firewall (all 10 rules in parallel)
   ↓
6. tls_private_key.provisioning_key
   ↓
7. ├─ google_compute_instance (bastion)
   ├─ google_compute_instance (master)
   ├─ google_compute_instance (worker-1)
   ├─ google_compute_instance (worker-2)
   └─ google_compute_instance (postgres)
   ↓
8. ├─ local_file.provisioning_private_key
   └─ local_file.kubespray_inventory
```

---

## ⏱️ Total Creation Time

**Breakdown by phase:**

| Phase | Duration | Notes |
|-------|----------|-------|
| Terraform Init | 10-30s | First time only, cached after |
| Network Layer | 20-30s | VPC + subnets + NAT |
| Firewall Rules | 10-15s | All 10 rules in parallel |
| SSH Keys | 1-2s | Local generation |
| Compute Instances | 40-60s | All 5 instances in parallel |
| Inventory Generation | 1-2s | Local file operations |
| State Upload | 2-3s | Upload to GCS |
| **TOTAL** | **~2-3 minutes** | From `terraform apply` to complete |

**Factors affecting duration:**
- ✅ Faster: Empty project (no existing resources)
- ✅ Faster: Resources in same region
- ✅ Faster: Parallel creation
- ❌ Slower: GCP API rate limits
- ❌ Slower: Large boot disk images
- ❌ Slower: First run (image caching)

---

## 🔍 What Gets Created in GCP Console

### After `terraform apply`, you can verify in GCP Console:

**VPC Networks (Networking → VPC network):**
```
k8s-vpc-stage
├── Subnets
│   ├── k8s-vpc-public-stage (10.1.1.0/24)
│   └── k8s-vpc-private-stage (10.1.2.0/24)
├── Routes
│   └── egress-internet-stage (0.0.0.0/0 → internet gateway)
└── Firewall rules
    └── (10 rules with prefix fw-*-stage)
```

**Cloud NAT (Networking → Cloud NAT):**
```
k8s-vpc-router-stage
└── k8s-vpc-nat-stage (NAT gateway for private subnet)
```

**Compute Engine (Compute Engine → VM instances):**
```
INSTANCE NAME    ZONE              INTERNAL IP   EXTERNAL IP       STATUS
bastion-host     europe-west3-a    10.1.1.3     34.40.119.219     RUNNING
k8s-master-1     europe-west3-a    10.1.1.2     35.198.108.205    RUNNING
k8s-worker-1     europe-west3-b    10.1.2.3     (via NAT)         RUNNING
k8s-worker-2     europe-west3-c    10.1.2.4     (via NAT)         RUNNING
postgres-db      europe-west3-a    10.1.2.2     (via NAT)         RUNNING
```

**Firewall Rules (VPC network → Firewall):**
```
fw-bastion-ssh-stage
fw-k8s-api-external-stage
fw-k8s-ssh-from-bastion-stage
fw-database-access-stage
fw-k8s-master-internal-stage
fw-k8s-master-to-worker-stage
fw-k8s-worker-to-master-stage
fw-k8s-nodeport-stage
fw-k8s-internal-all-stage
fw-k8s-https-stage
```

---

## 🧪 Verification Commands

### Verify Network Creation
```bash
# List VPC networks
gcloud compute networks list --project=terraform-test-480809

# List subnets
gcloud compute networks subnets list --network=k8s-vpc-stage --project=terraform-test-480809

# List routes
gcloud compute routes list --filter="network:k8s-vpc-stage" --project=terraform-test-480809

# Check NAT gateway
gcloud compute routers nats list --router=k8s-vpc-router-stage --region=europe-west3 --project=terraform-test-480809
```

### Verify Firewall Rules
```bash
# List all firewall rules for VPC
gcloud compute firewall-rules list --filter="network:k8s-vpc-stage" --project=terraform-test-480809

# Describe specific rule
gcloud compute firewall-rules describe fw-bastion-ssh-stage --project=terraform-test-480809
```

### Verify Instances
```bash
# List all instances
gcloud compute instances list --project=terraform-test-480809

# Get instance details
gcloud compute instances describe bastion-host --zone=europe-west3-a --project=terraform-test-480809

# Check instance can reach internet (from private subnet)
gcloud compute ssh k8s-worker-1 --zone=europe-west3-b --tunnel-through-iap --project=terraform-test-480809 --command="curl -s https://www.google.com -o /dev/null -w '%{http_code}'"
```

### Verify SSH Keys
```bash
# Check private key was created
ls -lah terraform/.ssh/provisioning_key

# Verify key permissions
stat -c "%a %n" terraform/.ssh/provisioning_key
# Should output: 600 terraform/.ssh/provisioning_key

# Test SSH to bastion
ssh -i terraform/.ssh/provisioning_key provisioning@<BASTION_IP> "echo 'SSH working'"
```

### Verify Inventory File
```bash
# Check inventory was created
cat kubespray/inventory/k8s-cluster/hosts.yaml | head -20

# Verify inventory syntax
ansible-inventory -i kubespray/inventory/k8s-cluster/hosts.yaml --list
```

---

## 🎯 Key Terraform Concepts Used

### 1. Module Composition
```hcl
module "network" {
  source = "./modules/network"
  # ... variables
}

module "instances" {
  source = "./modules/instance"
  depends_on = [module.network]
  # ... variables
}
```
**Purpose:** Reusable, testable infrastructure components

### 2. Resource Dependencies
```hcl
# Explicit dependency
resource "google_compute_instance" "vm" {
  depends_on = [google_compute_network.vpc]
}

# Implicit dependency (via reference)
network_interface {
  subnetwork = google_compute_subnetwork.public.self_link
}
```

### 3. Dynamic Resource Creation
```hcl
# Create multiple instances from map
resource "google_compute_instance" "vm" {
  for_each = var.vm_instances
  name     = each.key
  machine_type = each.value.machine_type
}
```

### 4. Template Rendering
```hcl
# Generate config files from templates
resource "local_file" "kubespray_inventory" {
  content = templatefile("kubespray-inventory.tpl", {
    bastion_ip = module.instances.vm_instances["bastion-host"].network_interface[0].access_config[0].nat_ip
    master_ip  = module.instances.vm_instances["k8s-master-1"].network_interface[0].network_ip
  })
}
```

### 5. State Management
```hcl
terraform {
  backend "gcs" {
    bucket = "terraform-11-12-2025-sytoss-bucket"
    prefix = "terraform/state/stage"
  }
}
```
**Purpose:** Remote state for team collaboration, locking, versioning

---

## 📚 Files Created During Infrastructure Creation

### In `terraform/` directory:
```
terraform/
├── .terraform/                    # Provider plugins & modules (created by init)
│   ├── providers/
│   │   ├── registry.terraform.io/hashicorp/google/
│   │   ├── registry.terraform.io/hashicorp/local/
│   │   └── registry.terraform.io/hashicorp/tls/
│   └── modules/
├── .terraform.lock.hcl           # Provider version lock file
├── terraform.tfstate             # Local state (if no remote backend)
├── terraform.tfstate.backup      # Previous state backup
└── .ssh/
    └── provisioning_key          # Generated SSH private key (4096-bit RSA)
```

### In `kubespray/` directory:
```
kubespray/inventory/k8s-cluster/
└── hosts.yaml                    # Generated Ansible inventory
```

### In GCS bucket:
```
gs://terraform-11-12-2025-sytoss-bucket/
└── terraform/state/stage/
    └── default.tfstate           # Remote state file (JSON)
```

---

## 🔐 Security Considerations

### SSH Key Management
- ✅ Key generated by Terraform (4096-bit RSA)
- ✅ Private key stored with `0600` permissions
- ✅ Key added to `.gitignore`
- ❌ Key not encrypted with passphrase (consider adding)
- ⚠️ Key stored in Terraform state (encrypted at rest in GCS)

### Network Security
- ✅ Private subnet for workers (no public IPs)
- ✅ NAT gateway for outbound-only internet
- ✅ Bastion as single SSH entry point
- ✅ Firewall rules with least privilege
- ✅ Flow logs enabled for auditing

### Instance Security
- ✅ OS Login disabled (SSH key-based only)
- ✅ Automatic security updates enabled
- ✅ No default service accounts
- ⚠️ Startup scripts run as root (potential risk)
- ⚠️ Instances accessible from internet on specific ports

---

## 🚨 Common Issues & Solutions

### Issue: "Error creating instances: Quota exceeded"
**Cause:** GCP project has insufficient quota  
**Solution:**
```bash
# Check current quotas
gcloud compute project-info describe --project=terraform-test-480809

# Request quota increase in GCP Console:
# IAM & Admin → Quotas → Filter by "CPUs" → Request increase
```

### Issue: "Error creating VPC: already exists"
**Cause:** Previous Terraform run left orphaned resources  
**Solution:**
```bash
# Import existing VPC into state
terraform import module.network.module.vpc.module.vpc.google_compute_network.network projects/terraform-test-480809/global/networks/k8s-vpc-stage

# Or destroy manually
gcloud compute networks delete k8s-vpc-stage --project=terraform-test-480809
```

### Issue: "Instances created but SSH not working"
**Cause:** Firewall rules not applied yet or SSH key not propagated  
**Solution:**
```bash
# Wait 30-60 seconds for metadata propagation
sleep 60

# Verify firewall rule exists
gcloud compute firewall-rules describe fw-bastion-ssh-stage --project=terraform-test-480809

# Test with verbose SSH
ssh -vvv -i terraform/.ssh/provisioning_key provisioning@<BASTION_IP>
```

### Issue: "NAT gateway not working for private instances"
**Cause:** Cloud Router or NAT configuration incorrect  
**Solution:**
```bash
# Verify NAT configuration
gcloud compute routers nats describe k8s-vpc-nat-stage --router=k8s-vpc-router-stage --region=europe-west3 --project=terraform-test-480809

# Check NAT logs
gcloud logging read "resource.type=nat_gateway" --limit=50 --format=json
```

---

## 📈 Scaling Considerations

### Adding More Workers
```hcl
# In terraform/values/stage.tfvars
vm_instances = {
  # ... existing instances
  "k8s-worker-3" = {
    name           = "k8s-worker-3"
    machine_type   = "e2-standard-2"
    zone           = "europe-west3-a"
    subnet         = "private"
    disk_size      = 20
    external_ip    = false
    tags           = ["k8s-worker", "kubernetes"]
  }
}
```

Then run:
```bash
terraform plan -var-file=values/stage.tfvars
terraform apply -var-file=values/stage.tfvars
```

### Multi-Master Setup
Requires:
1. Add more master instances (odd number: 3, 5, 7)
2. Configure load balancer for API server
3. Update etcd cluster configuration
4. Modify firewall rules for master-to-master communication

---

## 🎓 Learning Resources

- [Terraform Google Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GCP VPC Network Documentation](https://cloud.google.com/vpc/docs)
- [GCP Cloud NAT Documentation](https://cloud.google.com/nat/docs)
- [Terraform Module Best Practices](https://www.terraform.io/docs/language/modules/develop/index.html)

---

**Last Updated:** December 29, 2025  
**Terraform Version:** >= 1.0  
**GCP Provider Version:** ~> 5.0  
