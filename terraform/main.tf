module "longhorn_backup" {
  source = "./modules/longhorn-backup"

  cluster_name   = var.cluster_name
  environment    = var.environment
  region         = var.region
  retention_days = var.longhorn_backup_retention_days
}

resource "kubernetes_secret" "longhorn_backup_credentials" {
  metadata {
    name      = "longhorn-backup-s3"
    namespace = "longhorn-system"
  }

  data = {
    AWS_ACCESS_KEY_ID     = module.longhorn_backup.access_key_id
    AWS_SECRET_ACCESS_KEY = module.longhorn_backup.secret_access_key
  }

  type = "Opaque"
}
