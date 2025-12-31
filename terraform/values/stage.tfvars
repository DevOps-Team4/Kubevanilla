project_id = "kuber-super"   #This needs to be unique, change this before applying
region     = "europe-west3"
environment = "stage"

# VPC Network configuration
vpc_name            = "k8s-vpc"
vpc_cidr            = "10.1.0.0/16"
public_subnet_cidr  = "10.1.1.0/24"
private_subnet_cidr = "10.1.2.0/24"
enable_nat_gateway  = true

# Kubernetes cluster configuration
zone = "europe-west3-a"

# Database configuration
postgres_user = "postgres"
postgres_password = "SecureStagePass2024!"

db = {
  name         = "postgres-db"
  machine_type = "e2-micro"
  public_ip    = false
  tags         = ["database", "postgres"]
  docker_image = "postgres:13"  
  port         = 5432
  os_image     = "debian-cloud/debian-11"
  disk_size_gb = 20
  postgres_db  = "appdb"
}

# External database configuration (for applications)
# These variables can be used to configure applications deployed to Kubernetes
external_database = {
  host     = "your-external-db-host.com"
  port     = 5432
  name     = "appdb"
  user     = "appuser"
  # Password should be stored in Kubernetes secrets, not here
}

# VM Instances configuration for Kubernetes cluster
# Stage cluster: 1 bastion + 1 master + 2 workers
vm_instances = [
  {
    name         = "bastion-host"
    machine_type = "e2-micro"
    zone         = "europe-west3-a"
    subnet       = "public"
    public_ip    = true
    tags         = ["bastion"]
    ports        = [22]
    os_image     = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 10
  },
  {
    name         = "k8s-master-1"
    machine_type = "e2-standard-2"
    zone         = "europe-west3-a"
    subnet       = "public"
    public_ip    = true
    tags         = ["k8s-master", "kubernetes"]
    ports        = [22, 6443, 2379, 2380, 10250, 10251, 10252]
    os_image     = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 20
  },
  {
    name         = "k8s-worker-1"
    machine_type = "e2-standard-2"
    zone         = "europe-west3-b"
    subnet       = "private"
    public_ip    = false
    tags         = ["k8s-worker", "kubernetes"]
    ports        = [22, 10250, 30000, 80, 443]
    os_image     = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 20
  },
  {
    name         = "k8s-worker-2"
    machine_type = "e2-standard-2"
    zone         = "europe-west3-c"
    subnet       = "private"
    public_ip    = false
    tags         = ["k8s-worker", "kubernetes"]
    ports        = [22, 10250, 30000, 80, 443]
    os_image     = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 20
  }
]