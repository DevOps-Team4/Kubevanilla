# Kubernetes Cluster Setup with Kubespray

This directory contains all the necessary configuration to deploy a self-managed Kubernetes cluster on your GCP infrastructure using Kubespray and Ansible.

## 📋 Overview

The setup creates a 3-node Kubernetes cluster:
- **Control Plane (Master)**: k8s-master (10.1.1.3) - Public subnet
- **Worker Node 1**: k8s-worker-1 (10.1.2.3) - Private subnet
- **Worker Node 2**: k8s-worker-2 (10.1.2.2) - Private subnet (database server)

## 🏗️ Architecture

```
                    Internet
                       |
                   [Bastion]
                       |
         ┌─────────────┴─────────────┐
         |                           |
    Public Subnet              Private Subnet
         |                           |
   [k8s-master]           [k8s-worker-1, k8s-worker-2]
   Control Plane                   Worker Nodes
```

## 📁 Directory Structure

```
ansible/
├── deploy-k8s.sh                    # Main deployment script
├── k8s-inventory.ini                # Kubernetes cluster inventory
├── inventory.ini                    # Original infrastructure inventory
├── ansible.cfg                      # Ansible configuration
├── kubespray/                       # Kubespray repository (cloned)
├── kubespray-venv/                  # Python virtual environment
├── group_vars/
│   └── k8s_cluster/
│       ├── k8s-cluster.yml         # Main cluster configuration
│       └── addons.yml              # Kubernetes addons configuration
└── playbooks/
    └── kubernetes.yml              # Kubernetes deployment playbook
```

## 🚀 Quick Start

### Prerequisites

1. **Infrastructure Requirements**:
   - GCP infrastructure deployed via Terraform
   - All nodes accessible via SSH through bastion
   - SSH key at `~/.ssh/provisioning_key`

2. **Local Requirements**:
   - Python 3.8+
   - Ansible installed (via virtual environment)
   - Git

### Step 1: Verify Infrastructure

Ensure your GCP infrastructure is running:

```bash
# Check bastion connectivity
ssh -i ~/.ssh/provisioning_key provisioning@34.159.39.161

# From bastion, verify private nodes
ssh provisioning@10.1.1.3  # Control plane
ssh provisioning@10.1.2.3  # Worker 1
ssh provisioning@10.1.2.2  # Worker 2
```

### Step 2: Deploy Kubernetes Cluster

Run the deployment script:

```bash
cd /Users/iviul/Desktop/SYTOSS/IaC/ansible
./deploy-k8s.sh
```

The script will:
1. Verify prerequisites
2. Check SSH connectivity
3. Display deployment plan
4. Deploy Kubernetes using Kubespray
5. Configure kubectl access

**Expected Duration**: 20-40 minutes depending on network speed

### Step 3: Verify Deployment

After deployment completes:

```bash
# Set kubeconfig
export KUBECONFIG=/Users/iviul/Desktop/SYTOSS/IaC/ansible/kubeconfig

# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods --all-namespaces

# Check cluster info
kubectl cluster-info
```

## ⚙️ Configuration Details

### Cluster Configuration

**File**: `group_vars/k8s_cluster/k8s-cluster.yml`

Key settings:
- **Kubernetes Version**: v1.28.5
- **Container Runtime**: containerd
- **Network Plugin**: Calico
- **Service CIDR**: 10.233.0.0/18
- **Pod CIDR**: 10.233.64.0/18
- **DNS**: CoreDNS with NodeLocalDNS
- **Cloud Provider**: GCE (Google Compute Engine)

### Enabled Addons

**File**: `group_vars/k8s_cluster/addons.yml`

- ✅ Metrics Server (for `kubectl top`)
- ✅ Kubernetes Dashboard
- ✅ Ingress NGINX Controller
- ✅ Helm v3.13.0
- ✅ Local Path Provisioner (for PersistentVolumes)

## 🔧 Manual Deployment Steps

If you prefer to run steps manually instead of using the script:

### 1. Activate Virtual Environment

```bash
cd /Users/iviul/Desktop/SYTOSS/IaC/ansible
source kubespray-venv/bin/activate
```

### 2. Test Ansible Connectivity

```bash
ansible -i k8s-inventory.ini all -m ping
```

### 3. Prepare Nodes

```bash
ansible-playbook -i k8s-inventory.ini playbooks/kubernetes.yml --tags prepare
```

### 4. Deploy Kubernetes

```bash
cd kubespray
ansible-playbook -i ../k8s-inventory.ini \
  --become --become-user=root \
  cluster.yml
```

### 5. Configure kubectl Access

```bash
# Fetch kubeconfig from control plane
scp -i ~/.ssh/provisioning_key \
  provisioning@10.1.1.3:/home/provisioning/.kube/config \
  ../kubeconfig

# Use it
export KUBECONFIG=/Users/iviul/Desktop/SYTOSS/IaC/ansible/kubeconfig
kubectl get nodes
```

## 📊 Post-Deployment Tasks

### Access Kubernetes Dashboard

```bash
# Create admin service account token
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin

# Get token
kubectl -n kubernetes-dashboard create token dashboard-admin

# Start proxy
kubectl proxy

# Access at:
# http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Deploy Sample Application

```bash
# Create deployment
kubectl create deployment nginx --image=nginx

# Expose service
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check status
kubectl get svc nginx
```

### Setup Persistent Storage

```bash
# List storage classes
kubectl get storageclass

# Create a PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
EOF

# Verify
kubectl get pvc
```

## 🛠️ Troubleshooting

### SSH Connection Issues

```bash
# Test bastion connectivity
ssh -vvv -i ~/.ssh/provisioning_key provisioning@34.159.39.161

# Test private node via bastion
ssh -J provisioning@34.159.39.161 provisioning@10.1.1.3
```

### Ansible Connection Issues

```bash
# Test with verbose output
ansible -i k8s-inventory.ini all -m ping -vvv

# Test specific host
ansible -i k8s-inventory.ini k8s-master -m ping -vvv
```

### Check Kubespray Logs

```bash
# During deployment, logs are in:
cd /Users/iviul/Desktop/SYTOSS/IaC/ansible/kubespray
tail -f /tmp/ansible.log  # If configured
```

### Node Not Ready

```bash
# Check node status
kubectl describe node <node-name>

# Check kubelet logs on node
ssh provisioning@<node-ip>
sudo journalctl -u kubelet -f

# Check pod network
kubectl get pods -n kube-system
```

### Reset and Redeploy

If you need to start over:

```bash
# Reset cluster (from kubespray directory)
cd kubespray
ansible-playbook -i ../k8s-inventory.ini \
  --become --become-user=root \
  reset.yml

# Then redeploy
./deploy-k8s.sh
```

## 📝 Customization

### Modify Kubernetes Version

Edit `group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
kube_version: v1.29.0  # Change version
```

### Enable Additional Addons

Edit `group_vars/k8s_cluster/addons.yml`:

```yaml
cert_manager_enabled: true    # Enable cert-manager
metallb_enabled: true         # Enable MetalLB
```

### Change Network Plugin

Edit `group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
kube_network_plugin: flannel  # Options: calico, flannel, weave, cilium
```

## 🔒 Security Considerations

1. **SSH Keys**: Ensure `~/.ssh/provisioning_key` has proper permissions (0600)
2. **Bastion Access**: Only access cluster through bastion host
3. **RBAC**: Kubernetes RBAC is enabled by default
4. **Network Policies**: Consider implementing network policies for pod isolation
5. **Secrets Management**: Use Kubernetes secrets or external secret managers

## 📚 Additional Resources

- [Kubespray Documentation](https://kubespray.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Calico Network Plugin](https://docs.projectcalico.org/)
- [GCE Cloud Provider](https://cloud.google.com/kubernetes-engine/docs)

## 🆘 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Kubespray logs
3. Consult Kubernetes and Kubespray documentation
4. Check node and pod logs

## 📄 License

This configuration follows the same license as Kubespray (Apache 2.0).

---

**Happy Kubernetes Clustering! 🚀**
