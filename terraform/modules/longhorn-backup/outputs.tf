output "bucket_name" {
  description = "Name of the S3 bucket created for Longhorn backups"
  value       = aws_s3_bucket.longhorn.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.longhorn.arn
}

output "bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.longhorn.region
}

output "iam_user_name" {
  description = "IAM user name used by Longhorn"
  value       = aws_iam_user.longhorn.name
}

output "iam_user_arn" {
  description = "IAM user ARN"
  value       = aws_iam_user.longhorn.arn
}

output "access_key_id" {
  description = "AWS access key ID for the Longhorn IAM user"
  value       = aws_iam_access_key.longhorn.id
  sensitive   = true
}

output "secret_access_key" {
  description = "AWS secret access key for the Longhorn IAM user"
  value       = aws_iam_access_key.longhorn.secret
  sensitive   = true
}

# Convenience output: ready-to-use backupTarget URL for Longhorn
output "longhorn_backup_target" {
  description = "Longhorn backupTarget value (set this in Longhorn settings)"
  value       = "s3://${aws_s3_bucket.longhorn.id}@${aws_s3_bucket.longhorn.region}/"
}
