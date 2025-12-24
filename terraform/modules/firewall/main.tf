# Bastion Host - SSH from internet
resource "google_compute_firewall" "bastion_ssh" {
  name    = "fw-bastion-ssh-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]
  description   = "Allow SSH to bastion host from anywhere"
}

# Kubernetes Master API Server - External access
resource "google_compute_firewall" "k8s_api_external" {
  name    = "fw-k8s-api-external-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k8s-master"]
  description   = "Allow external access to Kubernetes API server"
}

# SSH Access - From bastion to Kubernetes nodes only
resource "google_compute_firewall" "k8s_ssh_from_bastion" {
  name    = "fw-k8s-ssh-from-bastion-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_tags = ["bastion"]
  target_tags = ["k8s-master", "k8s-worker", "kubernetes", "postgres"]
  description = "Allow SSH to Kubernetes nodes and database from bastion host only"
}

# Database Security - Access from Kubernetes nodes only
resource "google_compute_firewall" "database_access" {
  name    = "fw-database-access-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
  
  source_tags = ["kubernetes", "k8s-master", "k8s-worker"]
  target_tags = ["postgres"]
  description = "Allow database access from Kubernetes nodes"
}

# Kubernetes Master-to-Master Communication
resource "google_compute_firewall" "k8s_master_internal" {
  name    = "fw-k8s-master-internal-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["2379", "2380", "10250", "10251", "10252"]
  }
  
  source_tags = ["k8s-master"]
  target_tags = ["k8s-master"]
  description = "Allow communication between Kubernetes masters"
}

# Kubernetes Master-to-Worker Communication
resource "google_compute_firewall" "k8s_master_to_worker" {
  name    = "fw-k8s-master-to-worker-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }
  
  source_tags = ["k8s-master"]
  target_tags = ["k8s-worker"]
  description = "Allow Kubernetes master to communicate with workers"
}

# Kubernetes Worker-to-Master Communication
resource "google_compute_firewall" "k8s_worker_to_master" {
  name    = "fw-k8s-worker-to-master-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  
  source_tags = ["k8s-worker"]
  target_tags = ["k8s-master"]
  description = "Allow Kubernetes workers to communicate with API server"
}

# NodePort Services - External access
resource "google_compute_firewall" "k8s_nodeport" {
  name    = "fw-k8s-nodeport-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kubernetes"]
  description   = "Allow NodePort services external access"
}

# Internal Communication - All traffic within VPC for Kubernetes
resource "google_compute_firewall" "k8s_internal_all" {
  name    = "fw-k8s-internal-all-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.vpc_cidr]
  description   = "Allow all internal communication within VPC for Kubernetes"
}

# HTTPS for Load Balancers and Ingress
resource "google_compute_firewall" "k8s_https" {
  name    = "fw-k8s-https-${var.environment}"
  network = var.network_name
  
  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kubernetes"]
  description   = "Allow HTTP/HTTPS for Kubernetes ingress and load balancers"
}