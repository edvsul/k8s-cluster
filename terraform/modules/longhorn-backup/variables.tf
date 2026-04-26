variable "cluster_name" {
  description = "Name of the k3s cluster (used for resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. staging, production)"
  type        = string
  default     = "staging"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Longhorn backups. Defaults to <cluster_name>-longhorn-backups."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region where the S3 bucket will be created"
  type        = string
  default     = "eu-west-1"
}

variable "retention_days" {
  description = "Number of days to retain Longhorn backup objects before expiry (0 = no expiry)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
