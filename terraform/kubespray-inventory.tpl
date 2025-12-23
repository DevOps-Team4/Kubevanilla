all:
  hosts:
%{ for master in masters ~}
    ${master.name}:
      ansible_host: ${master.ansible_host}
      ip: ${master.ip}
      access_ip: ${master.ip}
%{ endfor ~}
%{ for worker in workers ~}
    ${worker.name}:
      ansible_host: ${worker.ansible_host}
      ip: ${worker.ip}
      access_ip: ${worker.ip}
%{ endfor ~}
  children:
    kube_control_plane:
      hosts:
%{ for master in masters ~}
        ${master.name}:
%{ endfor ~}
    kube_node:
      hosts:
%{ for master in masters ~}
        ${master.name}:
%{ endfor ~}
%{ for worker in workers ~}
        ${worker.name}:
%{ endfor ~}
    etcd:
      hosts:
%{ for master in masters ~}
        ${master.name}:
%{ endfor ~}
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
  vars:
    # SSH configuration will be handled by your Ansible configuration
    # Configure ansible_user, ansible_ssh_private_key_file, and proxy settings
    # in your ansible.cfg or inventory as needed
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'