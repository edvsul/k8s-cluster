variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "tgtg-playground-edvinas"
}

variable "cluster_name" {
  description = "Name of the k3s cluster"
  type        = string
  default     = "k8s-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "longhorn_backup_retention_days" {
  description = "Days to retain Longhorn backup objects (0 = no expiry)"
  type        = number
  default     = 90
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used to connect to the cluster"
  type        = string
  default     = "../../config"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use (empty string = current context)"
  type        = string
  default     = ""
}
