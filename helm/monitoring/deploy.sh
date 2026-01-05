#!/bin/bash

# Stop at error
set -e

NAMESPACE="monitoring"
RELEASE_NAME="bookstore-monitoring"
ENV="${1:-stage}"

echo "--------------------------------------------------"
echo "Deploying monitoring stack for environment: $ENV"
echo "--------------------------------------------------"

# 1. Helm 
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2.  kube-prometheus-stack
echo "Updating Helm dependencies..."
helm dependency update .

# 3. Installation with Helm
# Using --create-namespace
echo "Installing/Upgrading the release..."

if [ "$ENV" == "prod" ]; then
    helm upgrade --install $RELEASE_NAME . \
        --namespace $NAMESPACE \
        --values values.yaml \
        --values values-prod.yaml \
        --create-namespace \
        --wait
else
    helm upgrade --install $RELEASE_NAME . \
        --namespace $NAMESPACE \
        --values values.yaml \
        --values values-stage.yaml \
        --create-namespace \
        --wait
fi

echo "--------------------------------------------------"
echo "Monitoring stack deployed successfully!"
echo "--------------------------------------------------"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:80"
echo "  Login: admin / (пароль дивіться у values.yaml або секретах)"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n $NAMESPACE svc/prometheus-operated 9090:9090"
echo "--------------------------------------------------"