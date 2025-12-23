#!/bin/bash
set -e

# System updates and Docker installation
apt-get update
apt-get install -y docker.io python3 python3-pip

# Create provisioning user for Ansible
useradd -m -s /bin/bash "${PROVISIONING_USER}" || true
mkdir -p "/home/${PROVISIONING_USER}/.ssh"
echo "${PROVISIONING_KEY}" > "/home/${PROVISIONING_USER}/.ssh/authorized_keys"
chmod 600 "/home/${PROVISIONING_USER}/.ssh/authorized_keys"
chown -R "${PROVISIONING_USER}:${PROVISIONING_USER}" "/home/${PROVISIONING_USER}/.ssh"

echo "${PROVISIONING_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${PROVISIONING_USER}"
chmod 440 "/etc/sudoers.d/${PROVISIONING_USER}"

# Start Docker
systemctl start docker
systemctl enable docker

# Run PostgreSQL container
docker run \
  --name postgres \
  --restart always \
  -e POSTGRES_USER="${POSTGRES_USER}" \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -e POSTGRES_DB="${POSTGRES_DB}" \
  -p "${DB_PORT}:5432" \
  -v postgres_data:/var/lib/postgresql/data \
  -d \
  "${DOCKER_IMAGE}"

# Mark as ready
touch /tmp/terraform-setup-complete
echo "$(date): PostgreSQL database ready and Ansible user configured" > /var/log/terraform-setup.log