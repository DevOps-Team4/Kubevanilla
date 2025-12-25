resource "google_compute_instance" "postgres" {
  allow_stopping_for_update = true
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags

  labels = {
    application = "database"
    role        = "postgres"
  }

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {}
    }
  }

  service_account {
    email  = var.service_account
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = "${var.provisioning_user}:${var.provisioning_public_key}"
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    DB_PORT           = var.db_port
    POSTGRES_USER     = var.postgres_user
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = var.postgres_db
    DOCKER_IMAGE      = var.docker_image
    PROVISIONING_USER = var.provisioning_user
    PROVISIONING_KEY  = var.provisioning_public_key
  })
}
