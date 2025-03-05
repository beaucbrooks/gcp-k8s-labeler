variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  default = "us-central1"
  type    = string
}

variable "credentials_file" {
  description = "Path to the GCP service account key file"
  type        = string
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "allowed_ip" {
  description = "The IP address to allow access access from"
  type        = string
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC"
  default     = "default"
  type        = string
}

variable "node_tags" {
  description = "The tags to apply to the GKE nodes"
  default     = ["k8s-node"]
  type        = list(string)
}