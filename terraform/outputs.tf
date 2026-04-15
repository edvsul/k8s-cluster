output "longhorn_bucket_name" {
  description = "S3 bucket name for Longhorn backups"
  value       = module.longhorn_backup.bucket_name
}

output "longhorn_bucket_region" {
  description = "S3 bucket region"
  value       = module.longhorn_backup.bucket_region
}

output "longhorn_backup_target" {
  description = "Value to set as backupTarget in Longhorn settings"
  value       = module.longhorn_backup.longhorn_backup_target
}

output "longhorn_iam_user" {
  description = "IAM user name for Longhorn"
  value       = module.longhorn_backup.iam_user_name
}

output "longhorn_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for Longhorn backup secret"
  value       = module.longhorn_backup.access_key_id
  sensitive   = true
}

output "longhorn_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for Longhorn backup secret"
  value       = module.longhorn_backup.secret_access_key
  sensitive   = true
}
