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
  default = "rhel8-tpl"
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

variable "osdisk_size" { 
  type    = number
  default = 20480 
}

locals {
  vm_dir = "${var.vm_dir}/rhel-8"
}

variable "switch_name" {
  type    = string
  default = "Default Switch"
}

source "hyperv-iso" "rhel-8" {
  #boot_command      = ["<wait>c<wait>", "text ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks-8.cfg<enter><wait>", "boot<enter>"]
  boot_command      = [ "<up><wait>e<wait><down><wait><down><wait><end> text inst.sshd inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kickstart.cfg <wait><leftCtrlOn>x<leftCtrlOff>" ]
  boot_wait         = "3s"
  generation        = 2
  headless          = true
  http_directory    = "${path.root}/http"
  iso_checksum      = "none"
  iso_url           = "${var.iso_path}"
  output_directory  = "${var.vm_dir}"
  #shutdown_command  = "echo 'LS1setup!' | sudo -S shutdown -P now"
  #disable_shutdown  = true
  #shutdown_timeout  = "15m"
  shutdown_command  = "sudo su root -c \"userdel -rf mslabinstaller; shutdown -P now\""
  ssh_timeout       = "30m"
  ssh_username      = "mslabinstaller"
  ssh_password      = "LS1setup!"
  switch_name       = "${var.switch_name}"
  vm_name           = "packer-${var.vm_name}"
  differencing_disk = true
  disk_size         = "${var.osdisk_size}"
  disk_block_size   = 1 # 1MB as per https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v#tuning-linux-file-systems-on-dynamic-vhdx-files
  keep_registered   = false
}

build {
  sources = ["source.hyperv-iso.rhel-8"]

  # Enable vsock for SSH to enable SSH Direct connection via hvc ssh command.
  provisioner "shell" {
    execute_command = "echo 'LS1setup!' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    inline = [
      "cp /usr/lib/systemd/system/sshd.socket /usr/lib/systemd/system/sshd_vsock.socket", 
      "cp /usr/lib/systemd/system/sshd@.service /usr/lib/systemd/system/sshd_vsock@.service", 
      "sed -i 's/ListenStream=22/ListenStream=vsock::22/' /usr/lib/systemd/system/sshd_vsock.socket", 
      "systemctl disable sshd.service", 
      "systemctl enable sshd.socket", 
      "systemctl enable sshd_vsock.socket"
    ]
  }

  # create a standard user
  provisioner "shell" {
    execute_command = "echo 'LS1setup!' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    #expect_disconnect = true
    inline = [
        "useradd ${var.username}",
        "echo '${var.password}' | passwd ${var.username} --stdin",
        "mkdir -p /home/${var.username}/.ssh/", "echo '${var.ssh_key}' | tee /home/${var.username}/.ssh/authorized_keys",
        "usermod -aG wheel ${var.username}"
        #"shutdown -P now"
    ]
  }

  # Move EFI to VHD file
#  provisioner "shell" {
#    execute_command = "echo 'LS1setup!' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
#    #expect_disconnect = true
#    inline = [
#        "bootnum=$(efibootmgr -v | grep -i redhat | awk '{print $1}' | cut -c5-8)",
#        "efibootmgr -b $bootnum -B",
#        "efibootmgr --create --label RedHat --disk /dev/sda1 --loader '\\EFI\\redhat\\shimx64.efi'",
#        "grub2-mkconfig -o /boot/efi/EFI/BOOT/grub.cfg",
#        "efibootmgr -v"
#    ]
#  }

#  # create a standard user
#  provisioner "shell" {
#    execute_command = "echo 'LS1setup!' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
#    expect_disconnect = true
#    skip_clean = true
#    inline = [
#        "sleep 1",
#        "userdel -f -r mslabinstaller",
#        "shutdown -P now"
#    ]
#  }
}
