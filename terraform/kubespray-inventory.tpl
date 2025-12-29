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
    ansible_user: provisioning
    ansible_ssh_private_key_file: ~/.ssh/provisioning_key
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/provisioning_key provisioning@${bastion_ip}"'
    ansible_python_interpreter: /usr/bin/python3