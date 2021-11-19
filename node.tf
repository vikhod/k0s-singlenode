# Define required providers
terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.35.0"
    }
  }
}

# Configure the OpenStack Provider
# openrc.sh is used for configuration
provider "openstack" {
}

### Network configuration ###

## Add heare direct conection networks

data "openstack_networking_network_v2" "public" {
  name = "public"
}

resource "openstack_networking_floatingip_v2" "argo_extip" {
  pool = "public"
}

resource "openstack_compute_keypair_v2" "argo-keypair" {
  name       = "argo-keypair"
  public_key = file("argo_rsa.pub")
}

resource "openstack_blockstorage_volume_v2" "argo_volume" {
  name = "argo_volume"
  size = 10
}

resource "openstack_compute_instance_v2" "argo-single-node" {
  name            = "argo-single-node"
  image_name      = "focal-server-cloudimg-amd64-20211006"
  flavor_name     = "compact.prx"
  key_pair = "argo-keypair"
}

resource "openstack_compute_floatingip_associate_v2" "connected" {
  floating_ip = "${openstack_networking_floatingip_v2.argo_extip.address}"
  instance_id = "${openstack_compute_instance_v2.argo-single-node.id}"
}

resource "openstack_compute_volume_attach_v2" "attached" {
  instance_id = "${openstack_compute_instance_v2.argo-single-node.id}"
  volume_id   = "${openstack_blockstorage_volume_v2.argo_volume.id}"
}

resource "null_resource" "ansibled" {
  depends_on = [
    openstack_compute_instance_v2.argo-single-node,
    openstack_compute_floatingip_associate_v2.connected,
    openstack_compute_volume_attach_v2.attached
  ]

  provisioner "local-exec" {
    command = <<EOD
cat <<EOF > argo_hosts 
[argo-single-node] 
${openstack_networking_floatingip_v2.argo_extip.address}

[argo-single-node:vars]
ansible_ssh_user=ubuntu
ansible_ssh_private_key_file=argo_rsa
argo-single-node_ip=${openstack_networking_floatingip_v2.argo_extip.address}
EOF
EOD
  }

  provisioner "local-exec" {
    command = "ansible-playbook ArgoSingleNode.yml -i argo_hosts"
  }
}