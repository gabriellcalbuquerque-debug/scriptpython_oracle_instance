terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Tenta criar a instância no AD especificado (mude para AD-2 ou AD-3 se falhar)
resource "oci_core_instance" "arm_instance" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type = "image"
    source_id   = var.image_ocid
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = true
    display_name     = "${var.instance_name}-vnic"
  }

  metadata = {
    ssh_authorized_keys = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDUKhfygOrmtgxMm04O1IjvNNSZb/x+9oFZ49MYjZS/t7PAcJ3X7/X/p/WV++ZlC5h2vf8Oai2nnmSdyLI3AvrEK4PY82Y5IVOGgUOgn3r2Nd+rYHElamYSVn8x7J/GqjtNFEyszU0enq5h12d39jq2cUZF/YZw9ghf9Sdc/V//VZSsKalnH8Fxri0vmnOkzUWkNoB6jjD6Gm1NPTKJkUcJH1ljJmeExYIz6kGuQRwAlxdX8dcXcGJVIphRovVISMMCdgZgICFz/7IXvPJa0YEQ+MwlnrYb5IHKPqG/Qw0490KZjvMG0VNKsNjhFd9Ox/dzJ262gcHQbI+rb/y0TBZk5x4Z5a1VdMexNe+q3/sjDlMAlqpZigo7BcmtUqnnSZZddId5sjib7DhGBkVZAtnVuzPktsmJLYkeu0mrJQamiZvBUW8gqV6WyMhP4fej4of/GIp4SeeZGzKoDLbwpGxgSmxTCv9iPTrL2vhj+12l6nA5VDfbttKAF2Lhegg+7QvpMeaWXp8CD+m1ujHfcNCLawXsOtf1smgxGxutEXgu/SmcciS97gir6CVY/GXzdknoNVoCsevQKnvd4hrNBljZL8HEny4vUXgf7K12wQqnU4Jdz0KG0pfyaDWQeiVySkK7x3W3v7d61MDHzUTy3gViJKjNDMwWYgbu12WEP3lh9Q== biel_@Gabriel-PC"
  }

  # Não especifica fault domain — aumenta chance de encontrar capacidade
  # fault_domain = "FAULT-DOMAIN-1"

  timeouts {
    create = "10m"
  }
}

output "instance_id" {
  value = oci_core_instance.arm_instance.id
}

output "public_ip" {
  value = oci_core_instance.arm_instance.public_ip
}

output "state" {
  value = oci_core_instance.arm_instance.state
}
