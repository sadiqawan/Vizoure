# ─────────────────────────────────────────────
# Vizoure NMS — Packer Variables
# ─────────────────────────────────────────────

variable "vm_name" {
  default = "vizoure-nms-7.4.9"
}

variable "vm_version" {
  default = "7.4.9"
}

variable "iso_url" {
  default = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
}

variable "iso_checksum" {
  # Update this to match the actual ISO checksum
  default = "sha256:b59a72f4abb97bcdc9c4f24d6f78c5bc40fbed991f53b3440c04f1cb0e6965dc"
}

variable "disk_size" {
  default = "40960"   # 40GB in MB
}

variable "memory" {
  default = "4096"    # 4GB RAM
}

variable "cpus" {
  default = "2"
}

variable "ssh_username" {
  default = "admin"
}

variable "ssh_password" {
  default = "AES@admin"
}

variable "output_dir" {
  default = "../dist"
}
