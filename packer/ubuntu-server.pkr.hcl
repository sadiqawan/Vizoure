# ─────────────────────────────────────────────
# Vizoure NMS — Packer Build Template
# Outputs: VMX (Workstation) + OVF (ESXi)
# ─────────────────────────────────────────────

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
# SOURCE: VMware ISO builder
# Boots Ubuntu ISO + runs autoinstall
# ─────────────────────────────────────────────
source "vmware-iso" "vizoure_nms" {
  vm_name          = var.vm_name
  guest_os_type    = "ubuntu-64"
  version          = "19"

  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum

  disk_size        = var.disk_size
  memory           = var.memory
  cpus             = var.cpus

  network          = "nat"
  disk_adapter_type = "pvscsi"

  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "60m"

  shutdown_command = "sudo shutdown -P now"

  # HTTP server serves user-data + meta-data for autoinstall
  http_directory   = "http"

  # Boot command — tells Ubuntu where to find autoinstall config
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ <enter><wait>",
    "initrd /casper/initrd <enter><wait>",
    "boot <enter>"
  ]

  # VMX output directory
  output_directory = "${var.output_dir}/vmx/${var.vm_name}"
}

# ─────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────
build {
  name    = "vizoure-nms"
  sources = ["source.vmware-iso.vizoure_nms"]

  # Step 1: Run install script (pulls from GitHub)
  provisioner "shell" {
    inline = [
      "echo '=== Vizoure NMS Packer Provisioner ==='",
      "curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh | sudo bash"
    ]
  }

  # Step 2: Cleanup before sealing image
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "echo '=== Image sealed and ready ==='"
    ]
  }

  # Step 3: Export OVF from the VMX
  post-processor "shell-local" {
    inline = [
      "mkdir -p ${var.output_dir}/ovf",
      "ovftool --acceptAllEulas ${var.output_dir}/vmx/${var.vm_name}/${var.vm_name}.vmx ${var.output_dir}/ovf/${var.vm_name}.ovf",
      "echo 'OVF export complete'"
    ]
  }

  # Step 4: Create manifest file for GitHub Release
  post-processor "manifest" {
    output     = "${var.output_dir}/manifest.json"
    strip_path = true
  }
}
