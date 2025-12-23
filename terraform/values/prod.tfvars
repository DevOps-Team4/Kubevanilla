project_id = "your-production-project-id"
region     = "europe-west3"
environment = "prod"

# VPC Network configuration
vpc_name            = "k8s-vpc"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
enable_nat_gateway  = true

# Kubernetes cluster configuration
zone = "europe-west3-a"

# Database configuration
postgres_user = "postgres"
postgres_password = "SecureProdPass2024!"

db = {
  name         = "postgres-db"
  machine_type = "e2-small"
  public_ip    = false
  tags         = ["database", "postgres"]
  docker_image = "postgres:13"  
  port         = 5432
  os_image     = "debian-cloud/debian-11"
  disk_size_gb = 30
  postgres_db  = "appdb_prod"
}

# External database configuration (for applications)
# These variables can be used to configure applications deployed to Kubernetes
external_database = {
  host     = "your-external-prod-db-host.com"
  port     = 5432
  name     = "appdb_prod"
  user     = "appuser_prod"
  # Password should be stored in Kubernetes secrets, not here
}

# VM Instances configuration for Kubernetes cluster
# Production cluster: 1 bastion + 3 masters + 2 workers
vm_instances = [
  {
    name         = "bastion-host"
    machine_type = "e2-small"
    zone         = "europe-west3-a"
    subnet       = "public"
    public_ip    = true
    tags         = ["bastion"]
    ports        = [22]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 10
  },
  {
    name         = "k8s-master-1"
    machine_type = "e2-standard-4"
    zone         = "europe-west3-a"
    subnet       = "public"
    public_ip    = true
    tags         = ["k8s-master", "kubernetes"]
    ports        = [22, 6443, 2379, 2380, 10250, 10251, 10252]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 30
  },
  {
    name         = "k8s-master-2"
    machine_type = "e2-standard-4"
    zone         = "europe-west3-b"
    subnet       = "public"
    public_ip    = true
    tags         = ["k8s-master", "kubernetes"]
    ports        = [22, 6443, 2379, 2380, 10250, 10251, 10252]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 30
  },
  {
    name         = "k8s-master-3"
    machine_type = "e2-standard-4"
    zone         = "europe-west3-c"
    subnet       = "public"
    public_ip    = true
    tags         = ["k8s-master", "kubernetes"]
    ports        = [22, 6443, 2379, 2380, 10250, 10251, 10252]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 30
  },
  {
    name         = "k8s-worker-1"
    machine_type = "e2-standard-4"
    zone         = "europe-west3-a"
    subnet       = "private"
    public_ip    = false
    tags         = ["k8s-worker", "kubernetes"]
    ports        = [22, 10250, 30000, 80, 443]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 30
  },
  {
    name         = "k8s-worker-2"
    machine_type = "e2-standard-4"
    zone         = "europe-west3-b"
    subnet       = "private"
    public_ip    = false
    tags         = ["k8s-worker", "kubernetes"]
    ports        = [22, 10250, 30000, 80, 443]
    os_image     = "ubuntu-os-cloud/ubuntu-2004-lts"
    disk_size_gb = 30
  }
]