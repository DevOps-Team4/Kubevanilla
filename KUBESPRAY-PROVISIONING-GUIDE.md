# Kubespray Kubernetes Cluster Provisioning - Step by Step

## 📐 Overview

This document explains exactly how Kubernetes gets deployed on the infrastructure using Kubespray and Ansible, what happens at each step, role by role, and task by task.

---

## 🔄 Kubespray Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              1. Pre-deployment Preparation                       │
│         Ansible Setup → Inventory → SSH Verification            │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              2. Bootstrap / Gather Facts Phase                   │
│      System info → Python → Packages → Hostname setup           │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              3. Container Runtime Installation                   │
│           containerd → runc → CNI plugins → crictl              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              4. Kubernetes Binaries Download                     │
│         kubectl → kubeadm → kubelet → kube-proxy                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              5. Control Plane Initialization                     │
│        etcd → API server → Controller → Scheduler                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              6. Worker Nodes Join                                │
│         Generate tokens → Join workers → Verify nodes            │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              7. Network Plugin Deployment                        │
│              Calico CNI → Network policies setup                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              8. Cluster Addons Installation                      │
│    CoreDNS → metrics-server → nginx-ingress → Dashboard         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│              9. Post-Deployment Configuration                    │
│         Admin kubeconfig → RBAC → Final verification            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📝 Step-by-Step Kubespray Execution

### Step 1: Pre-deployment Preparation

#### 1.1 Virtual Environment Setup
```bash
cd /home/kaliuzhnyi/sytoss/projects/ultimate/Kubevanilla
python3 -m venv .venv
source .venv/bin/activate
```

**What happens:**
- Creates isolated Python environment
- Installs Ansible 2.17.14 (required for Kubespray compatibility)
- Installs dependencies: Jinja2, netaddr, ruamel.yaml

**Why virtual environment:**
- System Ansible (2.16.3) too old for Kubespray
- Kubespray requires: `ansible>=2.17.3,<2.18.0`
- Avoids conflicts with system packages

**Duration:** ~30 seconds

#### 1.2 Inventory Verification
```bash
cat kubespray/inventory/k8s-cluster/hosts.yaml
```

**Generated inventory structure:**
```yaml
all:
  hosts:
    k8s-master-1:
      ansible_host: 10.1.1.2                    # Internal IP
      ip: 10.1.1.2
      access_ip: 10.1.1.2
      ansible_user: provisioning
      ansible_ssh_private_key_file: ~/.ssh/provisioning_key
      ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p -q provisioning@34.40.119.219"'
    
    k8s-worker-1:
      ansible_host: 10.1.2.3
      ip: 10.1.2.3
      access_ip: 10.1.2.3
      # Same SSH config
    
    k8s-worker-2:
      ansible_host: 10.1.2.4
      ip: 10.1.2.4
      access_ip: 10.1.2.4
      # Same SSH config

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
        k8s-master-1: {}          # etcd runs on control plane
    
    k8s_cluster:
      children:
        kube_control_plane: {}
        kube_node: {}
    
    calico_rr:                     # Calico route reflectors (empty for small cluster)
      hosts: {}
```

**Key inventory features:**
- **ProxyCommand:** All nodes accessed via bastion (SSH tunnel)
- **Internal IPs:** Uses private network (10.1.x.x) for cluster communication
- **Groups:** Control plane, workers, etcd separated logically
- **SSH key:** Shared key for all nodes

#### 1.3 SSH Connectivity Test
```bash
cd ansible
ansible all -i ../kubespray/inventory/k8s-cluster/hosts.yaml -m ping
```

**What Ansible does:**
1. Reads inventory file
2. Parses SSH connection parameters
3. Opens SSH connection via bastion ProxyCommand
4. Executes simple Python script: `{"changed": false, "ping": "pong"}`
5. Verifies Python interpreter exists on remote hosts

**Expected output:**
```
k8s-master-1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
k8s-worker-1 | SUCCESS => { ... }
k8s-worker-2 | SUCCESS => { ... }
```

**Duration:** ~5-10 seconds

#### 1.4 Start Kubespray Deployment
```bash
cd ansible/kubespray

ansible-playbook \
  -i ../../kubespray/inventory/k8s-cluster/hosts.yaml \
  --become \
  --become-user=root \
  cluster.yml
```

**Command breakdown:**
- `-i`: Inventory file path
- `--become`: Execute tasks with sudo/become
- `--become-user=root`: Become root user (required for system modifications)
- `cluster.yml`: Main Kubespray playbook

---

### Step 2: Bootstrap / Gather Facts Phase

**Kubespray roles executed:** `bootstrap-os` → `gather-facts`

#### 2.1 Gather System Facts (all nodes)
**Role:** `kubernetes-sigs.kubespray.bootstrap-os`

**Tasks executed:**
1. **Gather hardware facts**
   ```yaml
   ansible.builtin.setup:
     gather_subset: hardware
   ```
   **Collects:**
   - CPU cores: 2 (master/workers), 1 (bastion)
   - Memory: 8GB (master/workers), 1GB (bastion)
   - Disk space: 20GB (master/workers), 10GB (bastion)
   - Architecture: x86_64

2. **Gather network facts**
   ```yaml
   ansible.builtin.setup:
     gather_subset: network
   ```
   **Collects:**
   - Network interfaces: eth0 (GCP default)
   - IP addresses: 10.1.1.2, 10.1.2.3, 10.1.2.4
   - Gateway: 10.1.1.1 (public subnet), 10.1.2.1 (private subnet)
   - DNS servers: 169.254.169.254 (GCP metadata server)

3. **Gather OS facts**
   ```yaml
   ansible.builtin.setup:
     gather_subset: virtual
   ```
   **Collects:**
   - OS: Ubuntu 22.04.5 LTS (Jammy)
   - Kernel: 6.8.0-1045-gcp
   - Distribution: Ubuntu
   - Python version: 3.10.12

4. **Check existing Kubernetes installation**
   ```yaml
   ansible.builtin.stat:
     path: /usr/bin/kubelet
   ```
   **Result:** Not found (fresh installation)

**Duration:** ~20-30 seconds per node (parallel execution)

#### 2.2 Setup Package Repositories (all nodes)
**Tasks:**

1. **Update apt cache**
   ```bash
   apt-get update
   ```
   **Downloads:** Package lists from Ubuntu repositories

2. **Install base packages**
   ```bash
   apt-get install -y \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg \
     lsb-release \
     software-properties-common
   ```
   **Purpose:** Required for adding third-party repositories

3. **Add Docker GPG key** (for containerd)
   ```bash
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
   ```

4. **Add Docker repository**
   ```bash
   add-apt-repository "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
   ```

5. **Add Kubernetes repository**
   ```bash
   curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
   ```

6. **Update apt cache again**
   ```bash
   apt-get update
   ```

**Duration:** ~1-2 minutes per node

#### 2.3 Configure System Settings (all nodes)

1. **Disable swap** (Kubernetes requirement)
   ```bash
   swapoff -a
   sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
   ```
   **Why:** Kubernetes requires swap to be disabled for performance and memory management

2. **Load kernel modules**
   ```bash
   modprobe overlay
   modprobe br_netfilter
   ```
   **Purpose:** Required for container networking

3. **Configure sysctl parameters**
   ```bash
   cat > /etc/sysctl.d/99-kubernetes.conf << EOF
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   EOF
   
   sysctl --system
   ```
   **Purpose:** Enable IP forwarding and bridge networking

4. **Configure hostname resolution**
   ```bash
   # Add entries to /etc/hosts
   echo "10.1.1.2 k8s-master-1" >> /etc/hosts
   echo "10.1.2.3 k8s-worker-1" >> /etc/hosts
   echo "10.1.2.4 k8s-worker-2" >> /etc/hosts
   ```

**Duration:** ~30 seconds per node

---

### Step 3: Container Runtime Installation

**Role:** `kubernetes-sigs.kubespray.container-engine/containerd`

#### 3.1 Install containerd (all nodes)
```bash
apt-get install -y containerd.io=1.7.22-1
```

**Version:** containerd 1.7.22 (compatible with Kubernetes 1.34)

**What gets installed:**
- `/usr/bin/containerd` - Container runtime daemon
- `/usr/bin/containerd-shim-runc-v2` - Runtime shim
- `/usr/bin/ctr` - CLI tool for containerd

**Duration:** ~30-45 seconds per node

#### 3.2 Configure containerd

1. **Generate default config**
   ```bash
   mkdir -p /etc/containerd
   containerd config default > /etc/containerd/config.toml
   ```

2. **Modify config for Kubernetes**
   ```toml
   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
     [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
       SystemdCgroup = true        # Use systemd for cgroup management
   
   [plugins."io.containerd.grpc.v1.cri"]
     sandbox_image = "registry.k8s.io/pause:3.9"  # Kubernetes pause container
   
   [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
     [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
       endpoint = ["https://registry-1.docker.io"]
   ```

3. **Enable and start containerd**
   ```bash
   systemctl daemon-reload
   systemctl enable containerd
   systemctl restart containerd
   systemctl status containerd
   ```

**Verification:**
```bash
ctr version
# Client:
#   Version:  1.7.22
# Server:
#   Version:  1.7.22
```

**Duration:** ~15-20 seconds per node

#### 3.3 Install runc (all nodes)
```bash
apt-get install -y runc=1.1.14-1
```

**Purpose:** Low-level container runtime (OCI runtime)  
**Location:** `/usr/bin/runc`

#### 3.4 Install CNI plugins (all nodes)
```bash
mkdir -p /opt/cni/bin
wget https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-amd64-v1.5.1.tgz
tar -xzf cni-plugins-linux-amd64-v1.5.1.tgz -C /opt/cni/bin
```

**Installed plugins:**
- bridge, host-local, loopback (basic networking)
- portmap, bandwidth (network features)
- firewall, tuning (network policies)

**Duration:** ~20-30 seconds per node

#### 3.5 Install crictl (all nodes)
```bash
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.31.1/crictl-v1.31.1-linux-amd64.tar.gz
tar -xzf crictl-v1.31.1-linux-amd64.tar.gz -C /usr/local/bin
```

**Purpose:** CLI tool for CRI-compatible runtimes  
**Usage:** `crictl ps`, `crictl images`, `crictl logs`

**Configure crictl:**
```bash
cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF
```

**Duration:** ~10 seconds per node

---

### Step 4: Kubernetes Binaries Download

**Role:** `kubernetes-sigs.kubespray.kubernetes/preinstall`

#### 4.1 Download Kubernetes binaries (all nodes)

**Binaries downloaded:**

1. **kubectl** (all nodes)
   ```bash
   wget https://dl.k8s.io/release/v1.34.3/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl
   chmod +x /usr/local/bin/kubectl
   ```
   **Size:** ~50MB  
   **Purpose:** Kubernetes CLI tool

2. **kubeadm** (all nodes)
   ```bash
   wget https://dl.k8s.io/release/v1.34.3/bin/linux/amd64/kubeadm -O /usr/local/bin/kubeadm
   chmod +x /usr/local/bin/kubeadm
   ```
   **Size:** ~48MB  
   **Purpose:** Cluster bootstrapping tool

3. **kubelet** (all nodes)
   ```bash
   wget https://dl.k8s.io/release/v1.34.3/bin/linux/amd64/kubelet -O /usr/local/bin/kubelet
   chmod +x /usr/local/bin/kubelet
   ```
   **Size:** ~130MB  
   **Purpose:** Node agent (runs on every node)

**Duration:** ~1-2 minutes per node (parallel download)

#### 4.2 Configure kubelet service (all nodes)

1. **Create kubelet systemd unit**
   ```bash
   cat > /etc/systemd/system/kubelet.service << EOF
   [Unit]
   Description=kubelet: The Kubernetes Node Agent
   Documentation=https://kubernetes.io/docs/
   Wants=network-online.target
   After=network-online.target

   [Service]
   ExecStart=/usr/local/bin/kubelet
   Restart=always
   StartLimitInterval=0
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

2. **Create kubelet config directory**
   ```bash
   mkdir -p /var/lib/kubelet /etc/kubernetes/manifests
   ```

3. **Enable kubelet service** (don't start yet)
   ```bash
   systemctl daemon-reload
   systemctl enable kubelet
   ```

**Duration:** ~10 seconds per node

#### 4.3 Download container images (all nodes)

**Images pre-pulled to speed up cluster init:**

```bash
# On all nodes
kubeadm config images pull --kubernetes-version=v1.34.3

# Images downloaded:
registry.k8s.io/kube-apiserver:v1.34.3              # 35MB
registry.k8s.io/kube-controller-manager:v1.34.3     # 33MB
registry.k8s.io/kube-scheduler:v1.34.3              # 19MB
registry.k8s.io/kube-proxy:v1.34.3                  # 28MB
registry.k8s.io/coredns/coredns:v1.11.3             # 18MB
registry.k8s.io/pause:3.9                           # 514KB
registry.k8s.io/etcd:3.5.15-0                       # 150MB
```

**Total size:** ~283MB per node

**Duration:** ~2-3 minutes per node (parallel)

---

### Step 5: Control Plane Initialization

**Role:** `kubernetes-sigs.kubespray.kubernetes/control-plane`  
**Target:** k8s-master-1 only

#### 5.1 Initialize Kubernetes with kubeadm

**Command executed on master:**
```bash
kubeadm init \
  --kubernetes-version=v1.34.3 \
  --control-plane-endpoint=10.1.1.2:6443 \
  --apiserver-advertise-address=10.1.1.2 \
  --apiserver-bind-port=6443 \
  --service-cluster-ip-range=10.233.0.0/18 \
  --pod-network-cidr=10.233.64.0/18 \
  --service-dns-domain=cluster.local \
  --node-name=k8s-master-1 \
  --ignore-preflight-errors=NumCPU,Mem \
  --skip-token-print
```

**Parameters explained:**
- `--kubernetes-version`: Kubernetes version to install
- `--control-plane-endpoint`: API server endpoint (internal IP)
- `--apiserver-advertise-address`: IP address API server listens on
- `--service-cluster-ip-range`: Virtual IPs for services (ClusterIP)
- `--pod-network-cidr`: IP range for pod network (Calico will use this)
- `--service-dns-domain`: Cluster DNS domain
- `--node-name`: Name of the control plane node
- `--ignore-preflight-errors`: Skip CPU/RAM checks (e2-standard-2 is sufficient)

**What happens during `kubeadm init`:**

1. **[preflight] Pre-flight checks** (~5 seconds)
   - Check if running as root
   - Verify ports 6443, 10250, 10251, 10252, 2379, 2380 are free
   - Check if Docker/containerd is running
   - Validate Kubernetes version

2. **[certs] Generate certificates** (~10 seconds)
   ```
   /etc/kubernetes/pki/
   ├── ca.crt / ca.key                          # Cluster CA
   ├── apiserver.crt / apiserver.key            # API server cert
   ├── apiserver-kubelet-client.crt / .key      # API → kubelet auth
   ├── front-proxy-ca.crt / .key                # Front proxy CA
   ├── front-proxy-client.crt / .key            # Front proxy client
   ├── etcd/
   │   ├── ca.crt / ca.key                      # etcd CA
   │   ├── server.crt / server.key              # etcd server
   │   ├── peer.crt / peer.key                  # etcd peer-to-peer
   │   └── healthcheck-client.crt / .key        # etcd health checks
   └── sa.key / sa.pub                          # Service account signing key
   ```
   **Certificate validity:** 10 years (default)
   **SANs (Subject Alternative Names):**
   - IP: 10.1.1.2 (internal), 10.233.0.1 (service ClusterIP), 127.0.0.1
   - DNS: k8s-master-1, kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local

3. **[kubeconfig] Generate kubeconfig files** (~5 seconds)
   ```
   /etc/kubernetes/
   ├── admin.conf                    # Cluster admin config
   ├── kubelet.conf                  # kubelet config
   ├── controller-manager.conf       # Controller manager config
   └── scheduler.conf                # Scheduler config
   ```

4. **[control-plane] Create static pod manifests** (~5 seconds)
   ```
   /etc/kubernetes/manifests/
   ├── kube-apiserver.yaml           # API server pod
   ├── kube-controller-manager.yaml  # Controller manager pod
   ├── kube-scheduler.yaml           # Scheduler pod
   └── etcd.yaml                     # etcd pod
   ```

5. **[kubelet-start] Start kubelet service** (~5 seconds)
   ```bash
   systemctl start kubelet
   ```
   **Kubelet detects manifests and starts static pods**

6. **[upload-config] Upload kubeadm config to ConfigMap** (~5 seconds)
   ```bash
   kubectl create configmap kubeadm-config -n kube-system --from-file=/etc/kubernetes/kubeadm-config.yaml
   ```

7. **[mark-control-plane] Label and taint master node** (~2 seconds)
   ```bash
   kubectl label node k8s-master-1 node-role.kubernetes.io/control-plane=
   kubectl taint node k8s-master-1 node-role.kubernetes.io/control-plane:NoSchedule
   ```
   **Effect:** Pods won't schedule on master (unless toleration specified)

8. **[bootstrap-token] Generate bootstrap token** (~2 seconds)
   ```
   Token: abcdef.1234567890abcdef
   Valid for: 24 hours
   ```
   **Purpose:** Workers use this token to join the cluster

9. **[upload-certs] Upload certificates to secret** (~3 seconds)
   ```bash
   kubectl create secret generic kubeadm-certs -n kube-system --from-file=/etc/kubernetes/pki/
   ```

**Total duration for kubeadm init:** ~40-60 seconds

**Verification:**
```bash
kubectl get nodes
# NAME           STATUS     ROLES           AGE   VERSION
# k8s-master-1   NotReady   control-plane   1m    v1.34.3
```
**Status: NotReady** (expected - no CNI plugin yet)

#### 5.2 Wait for Control Plane Pods (~30-45 seconds)

**Kubespray waits for these pods to be Running:**
```bash
kubectl get pods -n kube-system

# EXPECTED OUTPUT:
# NAME                                   READY   STATUS    RESTARTS   AGE
# etcd-k8s-master-1                      1/1     Running   0          1m
# kube-apiserver-k8s-master-1            1/1     Running   0          1m
# kube-controller-manager-k8s-master-1   1/1     Running   0          1m
# kube-scheduler-k8s-master-1            1/1     Running   0          1m
```

**What each pod does:**
- **etcd:** Distributed key-value store (cluster state)
- **kube-apiserver:** REST API for Kubernetes
- **kube-controller-manager:** Manages controllers (replication, endpoints, etc.)
- **kube-scheduler:** Schedules pods to nodes

---

### Step 6: Worker Nodes Join

**Role:** `kubernetes-sigs.kubespray.kubernetes/node`  
**Target:** k8s-worker-1, k8s-worker-2

#### 6.1 Generate Join Command (on master)

**Kubespray retrieves join command:**
```bash
# On master node
kubeadm token create --print-join-command

# Output:
# kubeadm join 10.1.1.2:6443 \
#   --token abcdef.1234567890abcdef \
#   --discovery-token-ca-cert-hash sha256:abc123...xyz789
```

**Token components:**
- **Token:** `abcdef.1234567890abcdef` (bootstrap authentication)
- **CA cert hash:** Used to verify API server certificate
- **Control plane endpoint:** `10.1.1.2:6443`

**Duration:** ~5 seconds

#### 6.2 Join Worker Nodes (parallel)

**Command executed on each worker:**
```bash
kubeadm join 10.1.1.2:6443 \
  --token abcdef.1234567890abcdef \
  --discovery-token-ca-cert-hash sha256:abc123...xyz789 \
  --node-name=k8s-worker-1  # or k8s-worker-2
```

**Join process (per worker):**

1. **[preflight] Pre-flight checks** (~5 seconds)
   - Verify containerd is running
   - Check if node already joined
   - Validate token format

2. **[discovery] Discover cluster info** (~10 seconds)
   - Connect to API server at 10.1.1.2:6443
   - Verify API server certificate using CA hash
   - Download cluster-info

3. **[kubelet-start] Configure kubelet** (~5 seconds)
   ```bash
   # Create kubelet config
   cat > /var/lib/kubelet/config.yaml << EOF
   apiVersion: kubelet.config.k8s.io/v1beta1
   kind: KubeletConfiguration
   authentication:
     webhook:
       enabled: true
   authorization:
     mode: Webhook
   clusterDomain: cluster.local
   clusterDNS:
     - 10.233.0.10
   containerRuntime: remote
   containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
   cgroupDriver: systemd
   EOF
   
   # Create kubelet environment file
   echo "KUBELET_EXTRA_ARGS=" > /etc/default/kubelet
   
   # Start kubelet
   systemctl start kubelet
   ```

4. **[kubelet-bootstrap] Bootstrap TLS** (~15 seconds)
   - kubelet requests certificate from API server
   - Uses bootstrap token for authentication
   - API server signs certificate
   - kubelet receives certificate and stores in `/var/lib/kubelet/pki/`

5. **[csr-approve] Approve CSR** (~5 seconds)
   ```bash
   # Kubespray automatically approves CSR on master
   kubectl get csr
   kubectl certificate approve csr-xxxxx
   ```

6. **[node-join] Node appears in cluster** (~5 seconds)
   ```bash
   kubectl get nodes
   # NAME           STATUS     ROLES           AGE   VERSION
   # k8s-master-1   NotReady   control-plane   5m    v1.34.3
   # k8s-worker-1   NotReady   <none>          1m    v1.34.3
   # k8s-worker-2   NotReady   <none>          1m    v1.34.3
   ```

**Total duration per worker:** ~45-60 seconds  
**Workers join in parallel:** ~1 minute total

**Status: NotReady** (expected - no CNI plugin yet)

---

### Step 7: Network Plugin Deployment (Calico)

**Role:** `kubernetes-sigs.kubespray.network_plugin/calico`  
**Target:** Runs on master (applies cluster-wide resources)

#### 7.1 Install Calico Operator

**Kubespray applies Calico operator:**
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml
```

**Resources created:**
```
Namespace: tigera-operator
ServiceAccount: tigera-operator
ClusterRole: tigera-operator
ClusterRoleBinding: tigera-operator
Deployment: tigera-operator
```

**Duration:** ~10 seconds

#### 7.2 Apply Calico Configuration

**Kubespray creates Installation custom resource:**
```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26                       # /26 blocks (64 IPs per node)
      cidr: 10.233.64.0/18                # Pod CIDR
      encapsulation: IPIP                 # IP-in-IP tunneling
      natOutgoing: true                   # SNAT for egress traffic
      nodeSelector: all()
    containerIPForwarding: Enabled
    mtu: 1440                             # GCP recommended MTU
  nodeAddressAutodetectionV4:
    interface: eth0                       # GCP default interface
```

**Duration:** ~20 seconds

#### 7.3 Wait for Calico Pods

**Calico components deployed:**

1. **calico-kube-controllers** (1 replica on master)
   ```bash
   kubectl get deployment -n calico-system calico-kube-controllers
   # NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
   # calico-kube-controllers     1/1     1            1           2m
   ```
   **Purpose:** Watches Kubernetes API, syncs network policies

2. **calico-node** (DaemonSet - 1 per node)
   ```bash
   kubectl get daemonset -n calico-system calico-node
   # NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
   # calico-node   3         3         3       3            3           kubernetes.io/os=linux
   ```
   **Purpose:** Runs on every node, manages routing and networking

3. **calico-typha** (Deployment - optional, for large clusters)
   ```bash
   kubectl get deployment -n calico-system calico-typha
   # NAME            READY   UP-TO-DATE   AVAILABLE   AGE
   # calico-typha    2/2     2            2           2m
   ```
   **Purpose:** Caching layer between calico-node and API server

**Pods running:**
```bash
kubectl get pods -n calico-system

# NAME                                       READY   STATUS    RESTARTS   AGE
# calico-kube-controllers-7d67b9c5d9-abcde   1/1     Running   0          2m
# calico-node-12345                          1/1     Running   0          2m
# calico-node-67890                          1/1     Running   0          2m
# calico-node-abcde                          1/1     Running   0          2m
# calico-typha-6f8b5c9d7f-12345              1/1     Running   0          2m
# calico-typha-6f8b5c9d7f-67890              1/1     Running   0          2m
```

**Duration:** ~1-2 minutes for all pods to be Running

#### 7.4 Verify Node Status (becomes Ready)

```bash
kubectl get nodes

# NAME           STATUS   ROLES           AGE   VERSION
# k8s-master-1   Ready    control-plane   10m   v1.34.3
# k8s-worker-1   Ready    <none>          8m    v1.34.3
# k8s-worker-2   Ready    <none>          8m    v1.34.3
```

**Status: Ready ✅** - Nodes now have CNI plugin configured!

**Duration:** ~30 seconds after Calico pods are Running

---

### Step 8: Cluster Addons Installation

**Role:** `kubernetes-sigs.kubespray.kubernetes-apps/cluster-addons`

#### 8.1 CoreDNS Deployment

**Purpose:** Cluster DNS for service discovery

**CoreDNS deployed automatically by kubeadm:**
```bash
kubectl get deployment -n kube-system coredns

# NAME      READY   UP-TO-DATE   AVAILABLE   AGE
# coredns   2/2     2            2           12m
```

**Kubespray verifies CoreDNS config:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
          max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
```

**CoreDNS Service:**
```bash
kubectl get svc -n kube-system kube-dns

# NAME       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
# kube-dns   ClusterIP   10.233.0.10   <none>        53/UDP,53/TCP,9153/TCP   12m
```

**Duration:** Already running, ~5 seconds verification

#### 8.2 NodeLocalDNS Cache

**Purpose:** DNS caching on each node for performance

**DaemonSet deployed:**
```bash
kubectl get daemonset -n kube-system nodelocaldns

# NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# nodelocaldns    3         3         3       3            3
```

**Configuration:**
- Cache DNS queries locally on each node
- Reduces latency for DNS lookups
- Listens on: `169.254.20.10` (link-local IP)

**Duration:** ~30 seconds

#### 8.3 metrics-server

**Purpose:** Resource metrics API (CPU, memory usage)

**Deployment:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml

kubectl get deployment -n kube-system metrics-server

# NAME             READY   UP-TO-DATE   AVAILABLE   AGE
# metrics-server   1/1     1            1           1m
```

**Configuration:**
```yaml
spec:
  template:
    spec:
      containers:
      - name: metrics-server
        args:
        - --cert-dir=/tmp
        - --secure-port=10250
        - --kubelet-preferred-address-types=InternalIP
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
```

**Verification:**
```bash
kubectl top nodes
# NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# k8s-master-1   350m         17%    1800Mi          22%
# k8s-worker-1   150m         7%     1200Mi          15%
# k8s-worker-2   150m         7%     1200Mi          15%
```

**Duration:** ~1-2 minutes

#### 8.4 nginx-ingress Controller

**Purpose:** HTTP(S) load balancing and ingress

**Deployment:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

kubectl get pods -n ingress-nginx

# NAME                                       READY   STATUS    RESTARTS   AGE
# ingress-nginx-controller-abc123-12345      1/1     Running   0          2m
# ingress-nginx-controller-abc123-67890      1/1     Running   0          2m
```

**Service:**
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller

# NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
# ingress-nginx-controller   LoadBalancer   10.233.10.100   <pending>     80:30080/TCP,443:30443/TCP
```

**Note:** External-IP stays `<pending>` (no cloud load balancer integration in self-managed cluster)  
**Access via:** NodePort 30080 (HTTP) and 30443 (HTTPS)

**Duration:** ~2-3 minutes

#### 8.5 Kubernetes Dashboard (Optional)

**Deployment:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

kubectl get pods -n kubernetes-dashboard

# NAME                                        READY   STATUS    RESTARTS   AGE
# kubernetes-dashboard-7d8b9cc8bf-xxxxx       1/1     Running   0          1m
# dashboard-metrics-scraper-7bc864c59-yyyyy  1/1     Running   0          1m
```

**Access:**
```bash
# Create admin user token
kubectl -n kubernetes-dashboard create token admin-user

# Proxy to dashboard
kubectl proxy

# Access at: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

**Duration:** ~1-2 minutes

---

### Step 9: Post-Deployment Configuration

**Role:** `kubernetes-sigs.kubespray.kubernetes/post-install`

#### 9.1 Copy admin.conf to Bastion

**Command executed:**
```bash
# On master
scp /etc/kubernetes/admin.conf provisioning@10.1.1.3:~/kubeconfig

# On bastion
mkdir -p ~/.kube
mv ~/kubeconfig ~/.kube/config
chmod 600 ~/.kube/config
```

**Kubeconfig structure:**
```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTi...
    server: https://10.1.1.2:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
users:
- name: kubernetes-admin
  user:
    client-certificate-data: LS0tLS1CRUdJTi...
    client-key-data: LS0tLS1CRUdJTi...
```

**Duration:** ~5 seconds

#### 9.2 Configure RBAC

**Default RBAC already configured by kubeadm:**

1. **cluster-admin ClusterRole** (full cluster access)
   ```bash
   kubectl get clusterrole cluster-admin
   ```

2. **system:masters group binding**
   ```bash
   kubectl get clusterrolebinding cluster-admin
   # Binds cluster-admin role to system:masters group
   ```

3. **kubernetes-admin user** (in kubeconfig)
   - Belongs to `system:masters` group
   - Has cluster-admin privileges

**Additional RBAC (if needed):**
```bash
# Create namespace for applications
kubectl create namespace production

# Create ServiceAccount
kubectl create serviceaccount app-deployer -n production

# Create Role
kubectl create role app-deployer --verb=get,list,create,delete --resource=pods,deployments -n production

# Create RoleBinding
kubectl create rolebinding app-deployer --role=app-deployer --serviceaccount=production:app-deployer -n production
```

**Duration:** ~5-10 seconds

#### 9.3 Final Verification

**Check all system pods:**
```bash
kubectl get pods -A

# NAMESPACE              NAME                                       READY   STATUS
# calico-system          calico-kube-controllers-xxx                1/1     Running
# calico-system          calico-node-xxx (x3)                       1/1     Running
# calico-system          calico-typha-xxx (x2)                      1/1     Running
# ingress-nginx          ingress-nginx-controller-xxx (x2)          1/1     Running
# kube-system            coredns-xxx (x2)                           1/1     Running
# kube-system            etcd-k8s-master-1                          1/1     Running
# kube-system            kube-apiserver-k8s-master-1                1/1     Running
# kube-system            kube-controller-manager-k8s-master-1       1/1     Running
# kube-system            kube-proxy-xxx (x3)                        1/1     Running
# kube-system            kube-scheduler-k8s-master-1                1/1     Running
# kube-system            metrics-server-xxx                         1/1     Running
# kube-system            nodelocaldns-xxx (x3)                      1/1     Running
```

**All pods should be Running ✅**

**Check cluster info:**
```bash
kubectl cluster-info

# Kubernetes control plane is running at https://10.1.1.2:6443
# CoreDNS is running at https://10.1.1.2:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**Check component status:**
```bash
kubectl get componentstatuses
# Warning: ComponentStatus is deprecated

kubectl get --raw=/healthz
# ok

kubectl get --raw=/livez
# ok

kubectl get --raw=/readyz
# ok
```

**Verify nodes:**
```bash
kubectl get nodes -o wide

# NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
# k8s-master-1   Ready    control-plane   25m   v1.34.3   10.1.1.2      <none>        Ubuntu 22.04.5 LTS   6.8.0-1045-gcp      containerd://2.1.6
# k8s-worker-1   Ready    <none>          23m   v1.34.3   10.1.2.3      <none>        Ubuntu 22.04.5 LTS   6.8.0-1045-gcp      containerd://2.1.6
# k8s-worker-2   Ready    <none>          23m   v1.34.3   10.1.2.4      <none>        Ubuntu 22.04.5 LTS   6.8.0-1045-gcp      containerd://2.1.6
```

**Test pod deployment:**
```bash
# Deploy test pod
kubectl run nginx --image=nginx:latest --port=80

# Wait for pod
kubectl wait --for=condition=Ready pod/nginx --timeout=60s

# Check pod
kubectl get pods
# NAME    READY   STATUS    RESTARTS   AGE
# nginx   1/1     Running   0          30s

# Test pod networking
kubectl exec nginx -- curl -s http://kubernetes.default.svc.cluster.local
# <html>...</html>

# Cleanup
kubectl delete pod nginx
```

**Duration:** ~2-3 minutes

---

## ⏱️ Total Deployment Time

**Breakdown by phase:**

| Phase | Duration | Description |
|-------|----------|-------------|
| 1. Pre-deployment | 1-2 min | Ansible setup, inventory verification |
| 2. Bootstrap | 2-3 min | System facts, package repos, system config |
| 3. Container Runtime | 2-3 min | containerd, runc, CNI plugins, crictl |
| 4. K8s Binaries | 3-5 min | kubectl, kubeadm, kubelet, container images |
| 5. Control Plane Init | 1-2 min | kubeadm init, etcd, API server startup |
| 6. Worker Join | 1-2 min | Join workers, approve CSRs |
| 7. Network Plugin | 2-3 min | Calico installation, node readiness |
| 8. Cluster Addons | 4-6 min | CoreDNS, metrics, ingress, dashboard |
| 9. Post-Deployment | 1-2 min | Kubeconfig, RBAC, verification |
| **TOTAL** | **17-28 min** | Typical: ~20 minutes |

**Factors affecting duration:**
- ✅ Faster: Pre-downloaded images, good internet speed
- ✅ Faster: Parallel execution on workers
- ❌ Slower: First-time image downloads
- ❌ Slower: NAT gateway latency for private nodes
- ❌ Slower: GCP API rate limits

---

## 📊 Kubespray Roles Execution Order

**Complete role dependency chain:**

```
1. kubernetes-sigs.kubespray.bootstrap-os
   ├─ Gather facts (hardware, network, OS)
   ├─ Update package cache
   ├─ Install base packages
   └─ Configure system settings (swap, sysctl, modules)
   
2. kubernetes-sigs.kubespray.container-engine/containerd
   ├─ Install containerd
   ├─ Install runc
   ├─ Install CNI plugins
   ├─ Install crictl
   └─ Configure and start containerd
   
3. kubernetes-sigs.kubespray.kubernetes/preinstall
   ├─ Download Kubernetes binaries
   ├─ Create kubelet systemd service
   └─ Pre-pull container images
   
4. kubernetes-sigs.kubespray.etcd (master only)
   ├─ Install etcd
   ├─ Configure etcd cluster
   └─ Start etcd service
   
5. kubernetes-sigs.kubespray.kubernetes/control-plane (master only)
   ├─ Run kubeadm init
   ├─ Wait for control plane pods
   ├─ Generate join tokens
   └─ Configure kubectl for admin
   
6. kubernetes-sigs.kubespray.kubernetes/node (workers only)
   ├─ Run kubeadm join
   ├─ Bootstrap kubelet TLS
   ├─ Approve CSRs
   └─ Verify node joined
   
7. kubernetes-sigs.kubespray.network_plugin/calico
   ├─ Install Calico operator
   ├─ Apply Calico configuration
   ├─ Wait for Calico pods
   └─ Verify node network readiness
   
8. kubernetes-sigs.kubespray.kubernetes-apps/cluster-addons
   ├─ Deploy CoreDNS
   ├─ Deploy NodeLocalDNS
   ├─ Deploy metrics-server
   ├─ Deploy nginx-ingress
   └─ Deploy Kubernetes Dashboard (optional)
   
9. kubernetes-sigs.kubespray.kubernetes/post-install
   ├─ Copy admin kubeconfig
   ├─ Configure RBAC
   └─ Final verification
```

---

## 🧪 Verification Checklist

### After Deployment Completes

**1. Verify all nodes are Ready:**
```bash
kubectl get nodes
# All should show STATUS: Ready
```

**2. Verify all system pods are Running:**
```bash
kubectl get pods -A
# All should show STATUS: Running (no CrashLoopBackOff, Error, Pending)
```

**3. Verify API server is accessible:**
```bash
kubectl cluster-info
# Should show: Kubernetes control plane is running at https://10.1.1.2:6443
```

**4. Verify DNS is working:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
# Should resolve to 10.233.0.1
```

**5. Verify pod networking:**
```bash
kubectl run nginx --image=nginx
kubectl expose pod nginx --port=80
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- nginx
# Should return nginx welcome page
kubectl delete pod nginx
kubectl delete svc nginx
```

**6. Verify internet access from pods:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- https://www.google.com
# Should return Google homepage HTML
```

**7. Verify metrics API:**
```bash
kubectl top nodes
kubectl top pods -A
# Should show CPU and memory usage
```

**8. Verify ingress controller:**
```bash
kubectl get pods -n ingress-nginx
# ingress-nginx-controller should be Running
```

**9. Check for any failed pods:**
```bash
kubectl get pods -A --field-selector=status.phase!=Running
# Should return: No resources found
```

**10. Verify certificates:**
```bash
# On master
sudo kubeadm certs check-expiration
# Should show all certs valid for ~10 years
```

---

## 🚨 Common Issues During Provisioning

### Issue: kubeadm init hangs at "[kubelet-check]"
**Cause:** kubelet can't start due to cgroup driver mismatch  
**Solution:**
```bash
# Check containerd cgroup driver
sudo cat /etc/containerd/config.toml | grep SystemdCgroup
# Should be: SystemdCgroup = true

# Check kubelet cgroup driver
sudo cat /var/lib/kubelet/config.yaml | grep cgroupDriver
# Should be: cgroupDriver: systemd

# Restart containerd and kubelet
sudo systemctl restart containerd kubelet
```

### Issue: Nodes stuck in "NotReady" after Calico installation
**Cause:** Calico pods not running or CNI config missing  
**Solution:**
```bash
# Check Calico pods
kubectl get pods -n calico-system

# Check Calico logs
kubectl logs -n calico-system -l app.kubernetes.io/name=calico-node

# Verify CNI config exists
ls -la /etc/cni/net.d/
# Should have: 10-calico.conflist

# Restart calico-node pods
kubectl delete pods -n calico-system -l app.kubernetes.io/name=calico-node
```

### Issue: Worker join fails with "token expired"
**Cause:** Bootstrap token is valid for only 24 hours  
**Solution:**
```bash
# On master, generate new token
kubeadm token create --print-join-command

# Copy and run the new join command on worker
sudo kubeadm join 10.1.1.2:6443 --token <new-token> --discovery-token-ca-cert-hash sha256:<hash>
```

### Issue: CoreDNS pods in CrashLoopBackOff
**Cause:** Loop detected in DNS resolution  
**Solution:**
```bash
# Edit CoreDNS ConfigMap
kubectl edit cm coredns -n kube-system

# Remove or comment out the "loop" plugin
# Change:
#   loop
# To:
#   # loop

# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system
```

### Issue: metrics-server not working
**Cause:** Unable to reach kubelet metrics endpoint  
**Solution:**
```bash
# Check metrics-server logs
kubectl logs -n kube-system deployment/metrics-server

# If certificate error, add flag to deployment:
kubectl edit deployment metrics-server -n kube-system

# Add to args:
#   - --kubelet-insecure-tls

# Restart
kubectl rollout restart deployment metrics-server -n kube-system
```

---

## 📁 Important Files Created During Provisioning

### On Master Node:

```
/etc/kubernetes/
├── admin.conf                              # Cluster admin kubeconfig
├── controller-manager.conf                 # Controller manager kubeconfig
├── kubelet.conf                            # kubelet kubeconfig
├── scheduler.conf                          # Scheduler kubeconfig
├── manifests/                              # Static pod manifests
│   ├── etcd.yaml
│   ├── kube-apiserver.yaml
│   ├── kube-controller-manager.yaml
│   └── kube-scheduler.yaml
└── pki/                                    # PKI certificates
    ├── ca.crt / ca.key
    ├── apiserver.crt / apiserver.key
    ├── apiserver-kubelet-client.crt / .key
    ├── front-proxy-ca.crt / .key
    ├── front-proxy-client.crt / .key
    ├── sa.key / sa.pub
    └── etcd/
        ├── ca.crt / ca.key
        ├── server.crt / server.key
        ├── peer.crt / peer.key
        └── healthcheck-client.crt / .key

/var/lib/kubelet/
├── config.yaml                             # kubelet configuration
├── kubeadm-flags.env                       # kubelet startup flags
└── pki/                                    # kubelet certificates
    ├── kubelet-client-current.pem
    └── kubelet.crt / kubelet.key

/var/lib/etcd/                              # etcd data directory
└── member/
    ├── snap/                               # Cluster state snapshots
    └── wal/                                # Write-ahead log

/etc/cni/net.d/                             # CNI configuration
└── 10-calico.conflist                      # Calico CNI config

/opt/cni/bin/                               # CNI plugins
├── bandwidth
├── bridge
├── calico
├── calico-ipam
├── host-local
├── loopback
└── portmap
```

### On Worker Nodes:

```
/etc/kubernetes/
├── kubelet.conf                            # kubelet kubeconfig (auto-generated)
└── pki/
    └── ca.crt                              # Cluster CA (for verification)

/var/lib/kubelet/
├── config.yaml                             # kubelet configuration
├── kubeadm-flags.env                       # kubelet startup flags
└── pki/                                    # kubelet certificates
    ├── kubelet-client-current.pem
    └── kubelet.crt / kubelet.key

/etc/cni/net.d/
└── 10-calico.conflist                      # Calico CNI config

/opt/cni/bin/                               # CNI plugins (same as master)
```

### On All Nodes:

```
/etc/containerd/
└── config.toml                             # containerd configuration

/usr/local/bin/
├── kubectl                                 # Kubernetes CLI (v1.34.3)
├── kubeadm                                 # Cluster management tool
├── kubelet                                 # Node agent
└── crictl                                  # CRI debugging tool

/etc/systemd/system/
├── kubelet.service                         # kubelet systemd unit
└── containerd.service                      # containerd systemd unit

/var/log/
├── pods/                                   # Pod logs
└── containers/                             # Container logs
```

---

## 🎓 Kubernetes Components Explained

### Control Plane Components (Master):

**1. etcd**
- **Purpose:** Distributed key-value store for cluster state
- **Port:** 2379 (client), 2380 (peer)
- **Data:** All cluster objects (pods, services, deployments, etc.)
- **High Availability:** Requires odd number of replicas (1, 3, 5, 7)

**2. kube-apiserver**
- **Purpose:** REST API server for Kubernetes
- **Port:** 6443 (HTTPS)
- **Functions:** Authentication, authorization, admission control, API routing
- **Access:** kubectl, kubelet, controllers all talk to API server

**3. kube-controller-manager**
- **Purpose:** Runs controller loops
- **Controllers:** Node, Replication, Endpoints, Service Account, Token
- **Functions:** Maintains desired state, reconciliation loops

**4. kube-scheduler**
- **Purpose:** Schedules pods to nodes
- **Algorithm:** Filtering (feasibility) → Scoring (best fit)
- **Factors:** Resource requirements, affinity/anti-affinity, taints/tolerations

### Node Components (All Nodes):

**1. kubelet**
- **Purpose:** Node agent, manages pods
- **Port:** 10250 (metrics/API), 10248 (healthz)
- **Functions:** Pod lifecycle, volume mounting, container health checks

**2. kube-proxy**
- **Purpose:** Network proxy for services
- **Mode:** iptables (default)
- **Functions:** Service ClusterIP → Pod IP translation, load balancing

**3. Container Runtime (containerd)**
- **Purpose:** Runs containers
- **Interface:** CRI (Container Runtime Interface)
- **Functions:** Image pulling, container lifecycle, resource isolation

### Addons:

**1. CoreDNS**
- **Purpose:** Cluster DNS
- **Service:** kube-dns (ClusterIP: 10.233.0.10)
- **Functions:** Service discovery, pod DNS resolution

**2. Calico**
- **Purpose:** Pod networking and network policies
- **Mode:** IPIP tunneling
- **CIDR:** 10.233.64.0/18 (pod IPs)
- **Components:** calico-node (DaemonSet), calico-kube-controllers

**3. metrics-server**
- **Purpose:** Resource metrics API
- **Functions:** CPU/memory usage, horizontal pod autoscaling
- **API:** /apis/metrics.k8s.io/v1beta1

---

## 📚 Kubespray Configuration Files

### Main Kubespray Variables (ansible/group_vars/k8s_cluster/):

**k8s-cluster.yml:**
```yaml
# Kubernetes version
kube_version: v1.34.3

# Network plugin
kube_network_plugin: calico

# Service CIDR
kube_service_addresses: 10.233.0.0/18

# Pod CIDR
kube_pods_subnet: 10.233.64.0/18

# Cluster DNS domain
cluster_name: cluster.local

# DNS Service IP
dns_server: 10.233.0.10

# Container runtime
container_manager: containerd

# Kubelet configuration
kubelet_max_pods: 110
kubelet_cpu_limit: 200m
kubelet_memory_limit: 900M
```

**addons.yml:**
```yaml
# Metrics Server
metrics_server_enabled: true

# Ingress Controller
ingress_nginx_enabled: true

# Dashboard
dashboard_enabled: false

# Helm
helm_enabled: true
helm_version: v3.13.0
```

---

## 🎯 Summary

### What Kubespray Does (High Level):

1. **Prepares all nodes** - Updates packages, configures system
2. **Installs container runtime** - containerd with proper configuration
3. **Downloads Kubernetes** - kubectl, kubeadm, kubelet binaries
4. **Initializes control plane** - etcd, API server, controller, scheduler on master
5. **Joins workers** - Adds worker nodes to cluster
6. **Deploys networking** - Calico CNI for pod-to-pod communication
7. **Installs addons** - CoreDNS, metrics-server, ingress, dashboard
8. **Configures access** - Copies kubeconfig, sets up RBAC
9. **Verifies deployment** - Checks all components are healthy

### Total Resources Created:

- **3 Nodes** - 1 master + 2 workers (all Ready)
- **~30 Pods** - System pods across all namespaces
- **5 Namespaces** - kube-system, calico-system, ingress-nginx, etc.
- **~20 Services** - ClusterIP services for cluster components
- **~15 DaemonSets/Deployments** - Workload controllers
- **Networking** - Full pod-to-pod, pod-to-service, external access

---

**Last Updated:** December 29, 2025  
**Kubespray Version:** Latest from git submodule  
**Kubernetes Version:** v1.34.3  
**Deployment Time:** ~15-30 minutes  
