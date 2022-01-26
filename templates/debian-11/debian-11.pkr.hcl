packer {
  required_plugins {
    # Fixed version for Windows 11 (to be able to use Default Switch)
    hyperv = {
      version = ">= 1.0.0"
      source  = "github.com/machv/hyperv"
    }
  }
}

variable "username" {
  type    = string
  default = "labadmin"
}

variable "domain" {
  type    = string
  default = "corp.contoso.com"
}

variable "ssh_key" {
  type    = string
  default = ""
}

variable "vm_name" {
  type    = string
  default = "deb-bullseye-tpl"
}

variable "vm_dir" {
  type    = string
  default = "packer_output"
}

variable "iso_name" {
  type    = string
  default = ""
}

variable "iso_path" {
  type    = string
  default = ""
}


variable "iso_checksum" {
  type    = string
  default = ""
}

locals {
  vm_dir = "${var.vm_dir}/debian"
}

variable "switch_name" {
  type    = string
  default = "Default Switch"
}


source "hyperv-iso" "deb-bullseye" {
  boot_command      = ["<wait>c<wait>", "linux /install.amd/vmlinuz ", "auto=true ", "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}//debian-11-preseed.cfg ", "passwd/username=packer", "hostname=${var.vm_name} ", "domain=${var.domain} ", "interface=auto ", "vga=788 noprompt quiet --<enter>", "initrd /install.amd/initrd.gz<enter>", "boot<enter>"]
  boot_wait         = "3s"
  generation        = 2
  headless          = true
  http_directory    = "${path.root}/http"
  iso_checksum      = "sha256:${var.iso_checksum}"
  iso_url           = "${var.iso_path}"
  output_directory  = "${var.vm_dir}"
  shutdown_command  = "echo 'packer' | sudo -S shutdown -P now"
  ssh_password      = "packer"
  ssh_timeout       = "30m"
  ssh_username      = "packer"
  switch_name       = "${var.switch_name}"
  vm_name           = "packer-${var.vm_name}"
  differencing_disk = true
  disk_size         = 20480 #20GB
  disk_block_size   = 1 # 1MB as per https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v#tuning-linux-file-systems-on-dynamic-vhdx-files
}

build {
  sources = ["source.hyperv-iso.deb-bullseye"]

  provisioner "shell" {
    inline = ["mkdir -p /home/packer/.ssh/", "echo '${var.ssh_key}' | tee /home/packer/.ssh/authorized_keys"]
  }

  provisioner "shell" {
    inline = [
        "echo 'Package: linux-* initramfs-tools  hyperv-daemons' | sudo tee /etc/apt/preferences.d/hyperv.pref",
        "echo 'Pin: release n=bullseye-backports' | sudo tee -a /etc/apt/preferences.d/hyperv.pref",
        "echo 'Pin-Priority: 500' | sudo tee -a /etc/apt/preferences.d/hyperv.pref"
    ]
  }

  provisioner "shell" {
    inline = [
        "echo 'deb http://deb.debian.org/debian bullseye-backports main' | sudo tee /etc/apt/sources.list.d/backports.list",
	"sudo apt-get update",
	"sudo apt-get upgrade -y"
    ]
  }
  provisioner "shell" {
    inline = [
      "sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --no-nvram --removable",
      "sudo update-grub"
    ]
  }

  provisioner "shell" {
    inline = ["sudo cp /usr/lib/systemd/system/ssh.socket /usr/lib/systemd/system/ssh_vsock.socket", "sudo cp /usr/lib/systemd/system/ssh@.service /usr/lib/systemd/system/ssh_vsock@.service", "sudo sed -i 's/ListenStream=22/ListenStream=vsock::22/' /usr/lib/systemd/system/ssh_vsock.socket", "sudo systemctl disable ssh.service", "sudo systemctl enable ssh.socket", "sudo systemctl enable ssh_vsock.socket"]
  }

  provisioner "shell" {
    inline = ["sudo sed -i -E 's/^#UseDNS.*$/UseDNS no/' /etc/ssh/sshd_config", "sudo sed -i -E 's/^(127\\.0\\.0\\.1[[:blank:]].*)$/\\1\\tUNKNOWN/' /etc/hosts", "echo 'hv_sock' | sudo tee /etc/modules-load.d/hv_sock.conf"]
  }
}
