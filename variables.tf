variable "tenancy_ocid" {
  description = "OCID do seu tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID do seu usuário OCI"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint da sua chave API"
  type        = string
}

variable "private_key_path" {
  description = "Caminho para a chave privada da API OCI (ex: ~/.oci/oci_api_key.pem)"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "Região OCI (ex: sa-saopaulo-1)"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "compartment_id" {
  description = "OCID do compartimento onde criar a instância"
  type        = string
}

variable "availability_domain" {
  description = "AD onde tentar criar (ex: iMvT:SA-SAOPAULO-1-AD-1)"
  type        = string
}

variable "instance_name" {
  description = "Nome da instância"
  type        = string
  default     = "botchat-geek-arm"
}

variable "image_ocid" {
  description = "OCID da imagem (Ubuntu 22.04 ARM, por exemplo)"
  type        = string
}

variable "subnet_ocid" {
  description = "OCID da subnet"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Caminho para a chave SSH pública (ex: ~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ocpus" {
  description = "Número de OCPUs (máx 4 no free tier)"
  type        = number
  default     = 4
}

variable "memory_in_gbs" {
  description = "Memória em GB (máx 24 no free tier)"
  type        = number
  default     = 24
}

variable "boot_volume_size_gb" {
  description = "Tamanho do boot volume em GB"
  type        = number
  default     = 50
}
