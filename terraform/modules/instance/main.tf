locals {
  # Find public and private subnet names
  public_subnet  = [for s in var.subnets : s.name if strcontains(s.name, "public")][0]
  private_subnet = [for s in var.subnets : s.name if strcontains(s.name, "private")][0]
}

resource "google_compute_instance" "vm" {
  for_each     = { for vm in var.vm_instances : vm.name => vm }
  name         = each.value.name
  machine_type = each.value.machine_type
  zone         = each.value.zone
  tags         = each.value.tags
  allow_stopping_for_update = true

  labels = {
    application = "app"
    environment = "stage"
  }

  boot_disk {
    initialize_params {
      image = each.value.os_image
      size  = each.value.disk_size_gb
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = each.value.subnet == "public" ? local.public_subnet : local.private_subnet

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    # SSH keys will be handled by GCP metadata or Ansible
    enable-oslogin = "FALSE"
    ssh-keys = "provisioning:${var.ssh_public_key}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Fast setup - only SSH keys, let Ansible handle packages
    
    %{if contains(each.value.tags, "bastion")}
    # Setup SSH private key for bastion host to access other nodes
    mkdir -p /home/provisioning/.ssh
    chown provisioning:provisioning /home/provisioning/.ssh
    chmod 700 /home/provisioning/.ssh
    
    # Create the private key file
    cat > /home/provisioning/.ssh/provisioning_key << 'PRIVATE_KEY_EOF'
${var.ssh_private_key}
PRIVATE_KEY_EOF
    
    # Set correct permissions
    chown provisioning:provisioning /home/provisioning/.ssh/provisioning_key
    chmod 600 /home/provisioning/.ssh/provisioning_key
    
    # Create SSH config for easier access
    cat > /home/provisioning/.ssh/config << 'SSH_CONFIG_EOF'
Host *
    IdentityFile ~/.ssh/provisioning_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
SSH_CONFIG_EOF
    
    chown provisioning:provisioning /home/provisioning/.ssh/config
    chmod 600 /home/provisioning/.ssh/config
    %{endif}
    
    # Mark as ready for Ansible configuration
    touch /tmp/terraform-provisioning-complete
    echo "$(date): Instance ${each.value.name} ready for Ansible configuration" > /var/log/terraform-setup.log
  EOF

  service_account {
    email  = "default"
    scopes = ["cloud-platform"]
  }
}

# Firewall rules are handled by the dedicated firewall module
# This prevents duplication and security issues
