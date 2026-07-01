# ─────────────────────────────────────────────
# Vizoure NMS — Packer Variables
# ─────────────────────────────────────────────

# VM Settings
variable "vm_name" {
  default = "vizoure-nms-7.4.9"
}

variable "vm_version" {
  default = "7.4.9"
}

# ISO Settings
variable "iso_url" {
  default = "/root/vizoure-nms-builde/packer/ubuntu-24.04.2-live-server-amd64.iso"
}

variable "iso_checksum" {
  default = "sha256:b59a72f4abb97bcdc9c4f24d6f78c5bc40fbed991f53b3440c04f1cb0e6965dc"
}

# Hardware
variable "disk_size" {
  default = "40960"
}

variable "memory" {
  default = "4096"
}

variable "cpus" {
  default = "2"
}

# SSH (for Packer to connect after OS install)
variable "ssh_username" {
  default = "admin"
}

variable "ssh_password" {
  default = "AES@admin"
}

# ESXi Host Settings — fill these in
variable "esxi_host" {
  default = "10.122.10.45"
}

variable "esxi_username" {
  default = "root"
}

variable "esxi_password" {
  default = "AES@aes123"
  sensitive = true
}

variable "esxi_datastore" {
  default = "datastore1"
}

# Output
variable "output_dir" {
  default = "../dist"
}
