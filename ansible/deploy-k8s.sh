#!/bin/bash
#
# Kubernetes Cluster Deployment Script
# This script deploys a self-managed Kubernetes cluster using Kubespray
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ANSIBLE_DIR="$SCRIPT_DIR"
KUBESPRAY_DIR="$ANSIBLE_DIR/kubespray"
VENV_DIR="$ANSIBLE_DIR/kubespray-venv"
K8S_INVENTORY="$ANSIBLE_DIR/k8s-inventory.ini"

echo -e "${BLUE}=========================================="
echo "Kubernetes Cluster Deployment"
echo "==========================================${NC}"
echo ""

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Error: Virtual environment not found at $VENV_DIR${NC}"
    echo "Please run: python3 -m venv $VENV_DIR && source $VENV_DIR/bin/activate && pip install -r $KUBESPRAY_DIR/requirements.txt"
    exit 1
fi

# Check if Kubespray exists
if [ ! -d "$KUBESPRAY_DIR" ]; then
    echo -e "${RED}Error: Kubespray not found at $KUBESPRAY_DIR${NC}"
    echo "Please run: git clone https://github.com/kubernetes-sigs/kubespray.git $KUBESPRAY_DIR"
    exit 1
fi

# Check if inventory exists
if [ ! -f "$K8S_INVENTORY" ]; then
    echo -e "${RED}Error: Kubernetes inventory not found at $K8S_INVENTORY${NC}"
    exit 1
fi

# Activate virtual environment
echo -e "${GREEN}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

# Verify SSH connectivity
echo -e "${GREEN}Verifying SSH connectivity to nodes...${NC}"
echo -e "${YELLOW}Testing bastion host...${NC}"
if ssh -i ~/.ssh/provisioning_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 provisioning@34.107.25.116 "echo 'Bastion accessible'" 2>/dev/null; then
    echo -e "${GREEN}✓ Bastion host is accessible${NC}"
else
    echo -e "${RED}✗ Cannot connect to bastion host${NC}"
    echo "Please ensure:"
    echo "  1. SSH key exists at ~/.ssh/provisioning_key"
    echo "  2. Bastion host is running and accessible"
    exit 1
fi

# Display deployment plan
echo ""
echo -e "${BLUE}Deployment Plan:${NC}"
echo "  Cluster Name: sytoss-k8s-cluster"
echo "  Kubernetes Version: v1.28.5"
echo "  Network Plugin: Calico"
echo "  Control Plane: k8s-master (10.1.1.3)"
echo "  Workers: k8s-worker-1 (10.1.2.3), k8s-worker-2 (10.1.2.2)"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the deployment? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
fi

# Run the playbook
echo -e "${GREEN}Starting Kubernetes deployment...${NC}"
echo "This may take 20-40 minutes depending on your network speed."
echo ""

cd "$ANSIBLE_DIR"

# Run the custom kubernetes playbook
ansible-playbook -i "$K8S_INVENTORY" playbooks/kubernetes.yml

echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Configure kubectl on your local machine:"
echo "   export KUBECONFIG=$ANSIBLE_DIR/kubeconfig"
echo ""
echo "2. Verify cluster:"
echo "   kubectl get nodes"
echo "   kubectl get pods --all-namespaces"
echo ""
echo "3. Access via bastion:"
echo "   ssh -i ~/.ssh/provisioning_key provisioning@34.159.39.161"
echo ""
echo -e "${GREEN}Happy Kubernetes clustering! 🚀${NC}"
