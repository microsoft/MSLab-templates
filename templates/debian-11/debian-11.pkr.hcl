packer {
  required_plugins {
    # Fixed version for Windows 11 (to be able to use Default Switch)
    hyperv = {
      version = ">= 1.0.2"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

variable "username" {
  type    = string
  default = "packer"
}

variable "password" {
  type    = string
  default = "LS1setup!"
  sensitive = true
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
  default = "debian11-tpl"
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

variable "osdisk_size" { 
  type    = number
  default = 20480 
}

locals {
  vm_dir = "${var.vm_dir}/debian-11"
}

variable "switch_name" {
  type    = string
  default = "Default Switch"
}

source "hyperv-iso" "debian-11" {
  boot_command      = ["<wait>c<wait>", "linux /install.amd/vmlinuz ", "auto=true ", "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}//debian-11-preseed.cfg ", "passwd/user-password=${var.password} ", "passwd/user-password-again=${var.password} ", "passwd/username=${var.username} ", "hostname=${var.vm_name} ", "domain=${var.domain} ", "interface=auto ", "vga=788 noprompt quiet --<enter>", "initrd /install.amd/initrd.gz<enter>", "boot<enter>"]
  boot_wait         = "3s"
  generation        = 2
  headless          = true
  http_directory    = "${path.root}/http"
  iso_checksum      = "none"
  iso_url           = "${var.iso_path}"
  output_directory  = "${var.vm_dir}"
  shutdown_command  = "echo '${var.password}' | sudo -S shutdown -P now"
  ssh_password      = "${var.password}"
  ssh_timeout       = "30m"
  ssh_username      = "${var.username}"
  switch_name       = "${var.switch_name}"
  vm_name           = "packer-${var.vm_name}"
  differencing_disk = true
  disk_size         = "${var.osdisk_size}"
  disk_block_size   = 1 # 1MB as per https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v#tuning-linux-file-systems-on-dynamic-vhdx-files
}

build {
  sources = ["source.hyperv-iso.debian-11"]

# temporarily make sudo passwordless
  provisioner "shell" {
    execute_command  = "echo ${var.password} | {{.Vars}} sudo -S bash -c {{.Path}}"
    inline = [
      "echo '${var.username} ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/${var.username}",
      "chmod 440 /etc/sudoers.d/${var.username}",
      "ls -l /etc/sudoers.d"
    ]
  }

  provisioner "shell" {
    inline = ["mkdir -p /home/${var.username}/.ssh/", "echo '${var.ssh_key}' | tee /home/${var.username}/.ssh/authorized_keys"]
  }

# include latest kernel for the latest Hyper-V integration components
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

# Do not store EFI boot loader in EFI itself (so we can use only a VHDX to create new VMs)
  provisioner "shell" {
    inline = [
      "sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --no-nvram --removable",
      "sudo update-grub"
    ]
  }

# Enable vsock for SSH to enable SSH Direct connection via hvc ssh command.
  provisioner "shell" {
    inline = ["sudo cp /usr/lib/systemd/system/ssh.socket /usr/lib/systemd/system/ssh_vsock.socket", "sudo cp /usr/lib/systemd/system/ssh@.service /usr/lib/systemd/system/ssh_vsock@.service", "sudo sed -i 's/ListenStream=22/ListenStream=vsock::22/' /usr/lib/systemd/system/ssh_vsock.socket", "sudo systemctl disable ssh.service", "sudo systemctl enable ssh.socket", "sudo systemctl enable ssh_vsock.socket"]
  }

# When using SSH Direct all connections would come from UNKNOWN hostname, add it to localhost to avoid resolution timeouts when connecting
  provisioner "shell" {
    inline = ["sudo sed -i -E 's/^#UseDNS.*$/UseDNS no/' /etc/ssh/sshd_config", "sudo sed -i -E 's/^(127\\.0\\.0\\.1[[:blank:]].*)$/\\1\\tUNKNOWN/' /etc/hosts", "echo 'hv_sock' | sudo tee /etc/modules-load.d/hv_sock.conf"]
  }

# Add needed packages for AD join
  provisioner "shell" {
    execute_command  = "{{.Vars}} sudo -S bash -c {{.Path}}"
    inline = [
      "apt install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit",
      "echo 'session optional        pam_mkhomedir.so skel=/etc/skel umask=077' >> /etc/pam.d/common-session", # create homedirs
      "systemctl restart sssd"
    ]
  }

# and cleanup sudoers NOPASSWD
  provisioner "shell" {
    inline = ["sudo rm /etc/sudoers.d/${var.username}"]
  }
}
