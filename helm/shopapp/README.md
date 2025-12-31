# ShopApp Helm Chart

Helm chart for deploying the BookStore fullstack application (React Frontend + Spring Boot Backend + PostgreSQL) to Kubernetes.

## 📋 Overview

This Helm chart deploys:
- **Frontend**: React/TypeScript application (Vite)
- **Backend**: Spring Boot REST API
- **Database**: PostgreSQL

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.x
- kubectl configured

### Installation

#### Development Environment

```bash
# Install with dev values
helm install shopapp ./helm/shopapp \
  --namespace shopapp \
  --create-namespace \
  -f ./helm/shopapp/values-dev.yaml
```

#### Production Environment

```bash
# Install with production values
helm install shopapp ./helm/shopapp \
  --namespace shopapp \
  --create-namespace \
  -f ./helm/shopapp/values-prod.yaml \
  --set postgresql.env.POSTGRES_PASSWORD=<secure-password>
```

### Upgrade

```bash
helm upgrade shopapp ./helm/shopapp \
  --namespace shopapp \
  -f ./helm/shopapp/values-prod.yaml
```

### Uninstall

```bash
helm uninstall shopapp --namespace shopapp
```

## 📁 Chart Structure

```
helm/shopapp/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
├── values-dev.yaml         # Development overrides
├── values-prod.yaml        # Production overrides
└── templates/
    ├── deployment.yaml     # Deployments for frontend, backend, postgresql
    ├── service.yaml        # Services for all components
    ├── configmap.yaml      # Application configuration
    ├── secret.yaml         # Secrets (database passwords)
    ├── serviceaccount.yaml # Service account
    ├── role.yaml           # RBAC role
    ├── rolebinding.yaml    # RBAC role binding
    ├── ingress.yaml        # Ingress configuration
    ├── persistentvolumeclaim.yaml # PVC for PostgreSQL
    ├── hpa.yaml            # Horizontal Pod Autoscaler
    ├── pdb.yaml            # Pod Disruption Budget
    └── _helpers.tpl        # Template helpers
```

## ⚙️ Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `backend.replicaCount` | Number of backend replicas | `2` |
| `frontend.replicaCount` | Number of frontend replicas | `2` |
| `postgresql.persistence.size` | PostgreSQL PVC size | `10Gi` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.hosts[0].host` | Ingress hostname | `shopapp.example.com` |

### Environment-Specific Values

- **Development** (`values-dev.yaml`): Single replica, smaller resources
- **Production** (`values-prod.yaml`): Multiple replicas, autoscaling, larger resources

## 🔒 Security

### Secrets Management

**⚠️ IMPORTANT**: Change the default PostgreSQL password in production!

```bash
# Generate secure password
openssl rand -base64 32

# Install with custom password
helm install shopapp ./helm/shopapp \
  --set postgresql.env.POSTGRES_PASSWORD=<your-secure-password>
```

Or use existing secret:

```yaml
postgresql:
  existingSecret: "my-postgres-secret"
  secretKey: "password"
```

## 📊 Monitoring & Scaling

### Autoscaling

Autoscaling is enabled in production by default:

```yaml
backend:
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Health Checks

- **Backend**: `/actuator/health` endpoint
- **Frontend**: Root path `/`

## 🌐 Ingress

The chart includes Ingress configuration for external access:

- Frontend: `https://shopapp.example.com/`
- Backend API: `https://shopapp.example.com/api`

### TLS/SSL

Configure TLS certificates via cert-manager or provide your own:

```yaml
ingress:
  tls:
    - secretName: shopapp-tls
      hosts:
        - shopapp.example.com
```

## 💾 Persistence

PostgreSQL data is persisted using PersistentVolumeClaim:

```yaml
postgresql:
  persistence:
    enabled: true
    size: 10Gi
    storageClass: "standard"
```

## 🔧 Customization

### Custom Images

```yaml
backend:
  image:
    repository: my-registry/bookstore-backend
    tag: v1.2.3
    pullPolicy: Always

frontend:
  image:
    repository: my-registry/bookstore-frontend
    tag: v1.2.3
```

### Resource Limits

```yaml
backend:
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "2Gi"
      cpu: "2000m"
```

## 📝 Notes

- Default PostgreSQL password is `bookstoreadmin` - **CHANGE IN PRODUCTION!**
- Backend connects to PostgreSQL via service name: `shopapp-postgresql`
- Frontend connects to backend via service name: `shopapp-backend`
- All components use the same namespace

## 🐛 Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n shopapp
```

### View Logs

```bash
# Backend logs
kubectl logs -n shopapp -l component=backend

# Frontend logs
kubectl logs -n shopapp -l component=frontend

# PostgreSQL logs
kubectl logs -n shopapp -l component=postgresql
```

### Database Connection Issues

```bash
# Check PostgreSQL service
kubectl get svc -n shopapp shopapp-postgresql

# Test connection from backend pod
kubectl exec -n shopapp -it deployment/shopapp-backend -- \
  env | grep POSTGRES
```

## 📚 Additional Resources

- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

