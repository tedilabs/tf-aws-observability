locals {
  metadata = {
    package = "terraform-aws-misc"
    version = trimspace(file("${path.module}/../../VERSION"))
    module  = basename(path.module)
    name    = var.name
  }
  module_tags = var.module_tags_enabled ? {
    "module.terraform.io/package"   = local.metadata.package
    "module.terraform.io/version"   = local.metadata.version
    "module.terraform.io/name"      = local.metadata.module
    "module.terraform.io/full-name" = "${local.metadata.package}/${local.metadata.module}"
    "module.terraform.io/instance"  = local.metadata.name
  } : {}
}


###################################################
# S3 Bucket for archive
###################################################

# TODO: object_lock_configuration
resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules

    content {
      id      = try(lifecycle_rule.value.id, null)
      enabled = try(lifecycle_rule.value.enabled, true)
      prefix  = try(lifecycle_rule.value.prefix, null)
      tags    = try(lifecycle_rule.value.tags, null)

      abort_incomplete_multipart_upload_days = try(lifecycle_rule.value.abort_incomplete_multipart_upload_days, null)

      expiration {
        date = try(lifecycle_rule.value.expiration.date, null)
        days = try(lifecycle_rule.value.expiration.days, 0)

        expired_object_delete_marker = try(lifecycle_rule.value.expiration.expired_object_delete_marker, false)
      }

      dynamic "transition" {
        for_each = try(lifecycle_rule.value.transitions, [])

        content {
          date = try(transition.value.date, null)
          days = try(transition.value.days, null)

          storage_class = transition.value.storage_class
        }
      }

      noncurrent_version_expiration {
        days = try(lifecycle_rule.value.noncurrent_version_expiration.days, null)
      }

      dynamic "noncurrent_version_transition" {
        for_each = try(lifecycle_rule.value.noncurrent_version_transitions, [])

        content {
          days = try(noncurrent_version_transition.value.days, null)

          storage_class = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  tags = merge(
    {
      "Name" = local.metadata.name
    },
    local.module_tags,
    var.tags,
  )
}


###################################################
# Server Side Encryption for S3 Bucket
###################################################

locals {
  sse_algorithm = {
    "AES256"  = "AES256"
    "AWS_KMS" = "aws:kms"
  }
}

# TODO: `expected_bucket_owner`
# TODO: `bucket_key_enabled`
# TODO: `rule.apply_server_side_encryption_by_default.kms_master_key_id`
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = local.sse_algorithm["AES256"]
    }
  }
}


###################################################
# IAM Policy for S3 Bucket
###################################################

data "aws_iam_policy_document" "this" {
  source_policy_documents = concat(
    var.tls_required ? [data.aws_iam_policy_document.tls_required.json] : [],
    var.delivery_cloudtrail_enabled ? [data.aws_iam_policy_document.cloudtrail.json] : [],
    var.delivery_config_enabled ? [data.aws_iam_policy_document.config.json] : [],
    var.delivery_elb_enabled ? [data.aws_iam_policy_document.elb.json] : [],
  )
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json
}
