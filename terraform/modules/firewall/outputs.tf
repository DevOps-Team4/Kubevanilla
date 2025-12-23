output "firewall_rule_names" {
  description = "Names of created firewall rules"
  value = [
    google_compute_firewall.bastion_ssh.name,
    google_compute_firewall.k8s_api_external.name,
    google_compute_firewall.k8s_ssh_from_bastion.name,
    google_compute_firewall.database_access.name,
    google_compute_firewall.k8s_master_internal.name,
    google_compute_firewall.k8s_master_to_worker.name,
    google_compute_firewall.k8s_worker_to_master.name,
    google_compute_firewall.k8s_nodeport.name,
    google_compute_firewall.k8s_internal_all.name,
    google_compute_firewall.k8s_https.name,
  ]
}

output "firewall_rules" {
  description = "Created firewall rules details"
  value = {
    bastion_ssh           = google_compute_firewall.bastion_ssh.id
    k8s_api_external      = google_compute_firewall.k8s_api_external.id
    k8s_ssh_from_bastion  = google_compute_firewall.k8s_ssh_from_bastion.id
    database_access       = google_compute_firewall.database_access.id
    k8s_master_internal   = google_compute_firewall.k8s_master_internal.id
    k8s_master_to_worker  = google_compute_firewall.k8s_master_to_worker.id
    k8s_worker_to_master  = google_compute_firewall.k8s_worker_to_master.id
    k8s_nodeport          = google_compute_firewall.k8s_nodeport.id
    k8s_internal_all      = google_compute_firewall.k8s_internal_all.id
    k8s_https             = google_compute_firewall.k8s_https.id
  }
}