locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.cluster_name}-longhorn-backups"
  iam_name    = "${var.cluster_name}-longhorn-backup"

  common_tags = merge(
    {
      Cluster     = var.cluster_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "longhorn-backup"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "longhorn" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "longhorn" {
  bucket = aws_s3_bucket.longhorn.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "longhorn" {
  bucket = aws_s3_bucket.longhorn.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "longhorn" {
  bucket = aws_s3_bucket.longhorn.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# IAM policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "longhorn_s3" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.longhorn.arn]
  }

  statement {
    sid    = "ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.longhorn.arn}/*"]
  }
}

resource "aws_iam_policy" "longhorn_s3" {
  name        = "${local.iam_name}-s3-policy"
  description = "Allows Longhorn to read/write backups in S3 bucket ${local.bucket_name}"
  policy      = data.aws_iam_policy_document.longhorn_s3.json
  tags        = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM user (used by Longhorn running outside AWS / on bare-metal k3s)
# ---------------------------------------------------------------------------

resource "aws_iam_user" "longhorn" {
  name = local.iam_name
  path = "/longhorn/"
  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "longhorn_s3" {
  user       = aws_iam_user.longhorn.name
  policy_arn = aws_iam_policy.longhorn_s3.arn
}

resource "aws_iam_access_key" "longhorn" {
  user = aws_iam_user.longhorn.name
}
