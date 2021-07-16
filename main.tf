# TODO remove hard coding for the number of VMs

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
     uri = "qemu:///system"
}

resource "libvirt_pool" "pool" {
  name = "pool"
  type = "dir"
  path = "/tmp/terraform-provider-libvirt-pool"
}

resource "libvirt_volume" "os_image" {
  name   = "os_image"
  pool   = libvirt_pool.pool.name
  source = "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_volume" "master" {
  name           = "master"
  base_volume_id = libvirt_volume.os_image.id
  size           = 53613931520 # 50 GB - no science...
}

resource "libvirt_volume" "workers" {
  name           = "volume-${count.index}"
  base_volume_id = libvirt_volume.os_image.id
  count          = 4
  size           = 53613931520 # 50 GB - no science...
}

data "template_file" "user_data" {
  template = file("${path.module}/terraform/cloud_init.cfg")
}

data "template_file" "network_config" {
  template = file("${path.module}/terraform/network_config.cfg")
}

# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.pool.name
}

resource "libvirt_domain" "master" {
  name = "master"

  memory   = "10000"
  vcpu     = 2

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.master.id
  }
}

resource "libvirt_domain" "workers" {
  name = "worker-${count.index}"
  count = 4

  memory   = "10000"
  vcpu     = 2

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = element(libvirt_volume.workers.*.id, count.index)
  }
}

output "master" {
  value = libvirt_domain.master.network_interface.0.addresses.0
}

output "workers" {
  value = libvirt_domain.workers.*.network_interface.0.addresses.0
}

resource "local_file" "AnsibleInventory" {
 content = templatefile("terraform/inventory.tmpl",
 {
   workers_ips = libvirt_domain.workers.*.network_interface.0.addresses.0
   master_ip = libvirt_domain.master.network_interface.0.addresses.0
 }
   )
  filename = "generated-inventory.yml"
}

# TODO make helper scripts for all the nodes? Or some overall nicer way in general?
resource "local_file" "ssh" {
  content = <<-DOC
    #!/bin/bash
    exec ssh -o "UserKnownHostsFile /dev/null" -o StrictHostKeyChecking=no ubuntu@${libvirt_domain.master.network_interface.0.addresses.0}
DOC
  filename = "./ssh.sh"
  file_permission = "0755"
}
