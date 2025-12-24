# Network Outputs
output "vpc_network_name" {
  description = "VPC network name"
  value       = module.network.network_name
}

output "vpc_network_id" {
  description = "VPC network ID"
  value       = module.network.network_id
}

output "public_subnet_name" {
  description = "Public subnet name"
  value       = module.network.public_subnet_name
}

output "public_subnet_cidr" {
  description = "Public subnet CIDR"
  value       = module.network.public_subnet_cidr
}

output "private_subnet_name" {
  description = "Private subnet name"
  value       = module.network.private_subnet_name
}

output "private_subnet_cidr" {
  description = "Private subnet CIDR"
  value       = module.network.private_subnet_cidr
}

# NAT Gateway Outputs
output "nat_gateway_name" {
  description = "NAT Gateway name (null if disabled)"
  value       = module.nat_gateway.nat_gateway_name
}

output "router_name" {
  description = "Cloud Router name (null if NAT disabled)"
  value       = module.nat_gateway.router_name
}

# Firewall Outputs
output "firewall_rule_names" {
  description = "List of firewall rule names"
  value       = module.firewall.firewall_rule_names
}

# Kubernetes Cluster Outputs
output "bastion_host_ip" {
  description = "Public IP address of the bastion host"
  value = try([
    for name, ip in module.instances.public_ips : ip
    if contains([for vm in var.vm_instances : vm.name if contains(vm.tags, "bastion")], name)
  ][0], null)
}

output "kubernetes_master_ips" {
  description = "IP addresses of Kubernetes master nodes"
  value = {
    for name, ip in module.instances.public_ips : name => ip
    if contains([for vm in var.vm_instances : vm.name if contains(vm.tags, "k8s-master")], name)
  }
}

output "kubernetes_worker_ips" {
  description = "IP addresses of Kubernetes worker nodes"
  value = {
    for name, ip in module.instances.private_ips : name => ip
    if contains([for vm in var.vm_instances : vm.name if contains(vm.tags, "k8s-worker")], name)
  }
}

output "all_instance_ips" {
  description = "All instance IP addresses"
  value       = merge(module.instances.public_ips, module.instances.private_ips)
}

output "database_private_ip" {
  description = "Private IP address of the database"
  value       = module.db.private_ip
}

output "kubespray_inventory_path" {
  description = "Path to the generated Kubespray inventory file"
  value       = local_file.kubespray_inventory.filename
}

# External database configuration (for reference)
output "external_database_config" {
  description = "External database configuration for applications"
  value       = var.external_database
  sensitive   = false
}