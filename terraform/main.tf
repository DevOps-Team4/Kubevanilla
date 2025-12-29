terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  backend "gcs" {
    # Configuration will be provided via -backend-config flag
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "tls_private_key" "provisioning_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "provisioning_private_key" {
  content         = tls_private_key.provisioning_key.private_key_pem
  filename        = "${path.root}/.ssh/provisioning_key"
  file_permission = "0600"
}

# 1. Network Module - Creates VPC + Subnets + Routes
module "network" {
  source = "./modules/network"

  project_id          = var.project_id
  region              = var.region
  vpc_name            = var.vpc_name
  environment         = var.environment
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

# 2. NAT Gateway Module - Creates Cloud Router + Cloud NAT
module "nat_gateway" {
  source = "./modules/nat-gateway"

  project_id        = var.project_id
  region            = var.region
  vpc_name          = var.vpc_name
  environment       = var.environment
  network_id        = module.network.network_id
  private_subnet_id = module.network.private_subnet_id
  enable_nat        = var.enable_nat_gateway

  depends_on = [module.network]
}

# 3. Firewall Module - Creates Security Groups (Firewall Rules)
module "firewall" {
  source = "./modules/firewall"

  network_name = module.network.network_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  depends_on = [module.network]
}

# 4. Database Module - Creates managed database
module "db" {
  source            = "./modules/db"
  name              = var.db.name
  machine_type      = var.db.machine_type
  zone              = var.zone
  public_ip         = var.db.public_ip
  tags              = var.db.tags
  docker_image      = var.db.docker_image
  db_port           = var.db.port
  os_image          = var.db.os_image
  disk_size_gb      = var.db.disk_size_gb
  network           = module.network.network_name
  subnetwork        = module.network.private_subnet_name
  service_account   = "default"
  postgres_user     = var.postgres_user
  postgres_password = var.postgres_password
  postgres_db       = var.db.postgres_db

  provisioning_user       = "provisioning"
  provisioning_public_key = tls_private_key.provisioning_key.public_key_openssh

  depends_on = [module.network]
}

# 5. VM Instances Module - Creates all Kubernetes nodes
module "instances" {
  source = "./modules/instance"

  subnets = [
    {
      name = module.network.public_subnet_name   # Zone A - for bastion & master
      zone = "${var.region}-a"
    },
    {
      name = module.network.private_subnet_name  # Zone B - for workers
      zone = "${var.region}-b"
    },
    {
      name = module.network.private_subnet_name  # Zone C - for workers  
      zone = "${var.region}-c"
    }
  ]
  vm_instances = var.vm_instances
  network_name = module.network.network_name
  ssh_public_key = tls_private_key.provisioning_key.public_key_openssh
  ssh_private_key = tls_private_key.provisioning_key.private_key_pem

  depends_on = [module.network, module.firewall]
}

# Generate Kubespray inventory file for Ansible
resource "local_file" "kubespray_inventory" {
  filename = "${path.module}/../kubespray/inventory/k8s-cluster/hosts.yaml"

  content = templatefile("${path.module}/kubespray-inventory.tpl", {
    bastion_ip = try([
      for name, ip in module.instances.public_ips : ip
      if contains([for vm in var.vm_instances : vm.name if contains(vm.tags, "bastion")], name)
    ][0], null)
    
    masters = [for vm in var.vm_instances : {
      name         = vm.name
      # Use private IP for Ansible access (via bastion), but keep public IP for access_ip
      ip           = module.instances.private_ips[vm.name]
      ansible_host = module.instances.private_ips[vm.name]
      public_ip    = vm.public_ip ? module.instances.public_ips[vm.name] : null
    } if contains(vm.tags, "k8s-master")]

    workers = [for vm in var.vm_instances : {
      name         = vm.name
      ip           = module.instances.private_ips[vm.name]
      ansible_host = module.instances.private_ips[vm.name]
      public_ip    = vm.public_ip && vm.subnet == "public" ? module.instances.public_ips[vm.name] : null
    } if contains(vm.tags, "k8s-worker")]
  })
}