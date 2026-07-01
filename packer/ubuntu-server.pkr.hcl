packer {
  required_version = ">= 1.9.0"
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 1"
    }
  }
}

# ─────────────────────────────────────────────
# SOURCE: Build directly on ESXi host
# ─────────────────────────────────────────────
source "vmware-iso" "vizoure_nms" {
  vm_name       = var.vm_name
  guest_os_type = "ubuntu-64"
  version       = "19"

  # ESXi remote build settings
  remote_type     = "esx5"
  remote_host     = var.esxi_host
  remote_username = var.esxi_username
  remote_password = var.esxi_password
  remote_datastore = var.esxi_datastore

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  disk_size         = var.disk_size
  memory            = var.memory
  cpus              = var.cpus
  network           = "VM Network"
  disk_adapter_type = "pvscsi"

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "60m"

  shutdown_command = "sudo shutdown -P now"

  http_directory = "http"

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ <enter><wait>",
    "initrd /casper/initrd <enter><wait>",
    "boot <enter>"
  ]

  # Keep artifact on ESXi after build
  skip_export = false
  output_directory = "vizoure-nms-output"
}

# ─────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────
build {
  name    = "vizoure-nms"
  sources = ["source.vmware-iso.vizoure_nms"]

  # Step 1: Run Vizoure install script
  provisioner "shell" {
    inline = [
      "echo '=== Vizoure NMS Packer Provisioner ==='",
      "curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh | sudo bash"
    ]
  }

  # Step 2: Cleanup + seal image
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /tmp/* /var/tmp/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "echo '=== Image sealed ==='"
    ]
  }

  # Step 3: Export OVF from ESXi
  post-processor "shell-local" {
    inline = [
      "mkdir -p ../dist/ovf",
      "ovftool --acceptAllEulas vi://${var.esxi_username}:${var.esxi_password}@${var.esxi_host}/vizoure-nms-output/${var.vm_name}.vmx ../dist/ovf/${var.vm_name}.ovf",
      "echo 'OVF export complete'"
    ]
  }

  # Step 4: Build manifest
  post-processor "manifest" {
    output     = "../dist/manifest.json"
    strip_path = true
  }
}
