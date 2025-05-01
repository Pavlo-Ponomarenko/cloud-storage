provider "aws" {
  region = "eu-west-1"
  alias  = "replica"
}

resource "aws_s3_bucket" "secure_bucket" {
  bucket = "my-secure-bucket-unique-123456"
  force_destroy = true
  object_lock_enabled = true

  tags = {
    Name = "SecureBucket"
    Environment = "Dev"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.secure_bucket.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# Enable default encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.secure_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.secure_bucket.id

  versioning_configuration {
    status = "Enabled"
    mfa_delete = "Enabled"
  }
}

# Enable object lock
resource "aws_s3_bucket_object_lock_configuration" "object_lock" {
  bucket = aws_s3_bucket.secure_bucket.id
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode  = "GOVERNANCE"
      days  = 30
    }
  }
}

resource "aws_iam_user" "readonly_user" {
  name = "s3-readonly-user"
}

resource "aws_iam_user" "readwrite_user" {
  name = "s3-readwrite-user"
}

resource "aws_iam_policy" "readonly_policy" {
  name = "S3ReadOnlyPolicy"
  description = "Read-only access to the S3 secure bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.secure_bucket.arn,
          "${aws_s3_bucket.secure_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "readwrite_policy" {
  name = "S3ReadWritePolicy"
  description = "Read-write access to the S3 secure bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Resource = [
          aws_s3_bucket.secure_bucket.arn,
          "${aws_s3_bucket.secure_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "readonly_attach" {
  user = aws_iam_user.readonly_user.name
  policy_arn = aws_iam_policy.readonly_policy.arn
}

resource "aws_iam_user_policy_attachment" "readwrite_attach" {
  user = aws_iam_user.readwrite_user.name
  policy_arn = aws_iam_policy.readwrite_policy.arn
}

# Destination bucket
resource "aws_s3_bucket" "replica_bucket" {
  bucket = "my-secure-bucket-replica-123456"
  provider = aws.replica
  force_destroy = true
  object_lock_enabled = true

  tags = {
    Name = "ReplicaBucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "replica_versioning" {
  bucket = aws_s3_bucket.replica_bucket.id
  provider = aws.replica
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM role for replication
resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication_policy" {
  name = "s3-replication-policy"
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication",
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ListBucket"
        ],
        Resource = [
          "${aws_s3_bucket.secure_bucket.arn}/*",
          aws_s3_bucket.secure_bucket.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Resource = [
          "${aws_s3_bucket.replica_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Add replication configuration to source bucket
resource "aws_s3_bucket_replication_configuration" "replication" {
  depends_on = [
    aws_s3_bucket_versioning.versioning,
    aws_s3_bucket_versioning.replica_versioning
  ]

  role   = aws_iam_role.replication_role.arn
  bucket = aws_s3_bucket.secure_bucket.id

  rule {
    id     = "replication-rule"
    status = "Enabled"

    destination {
      bucket = aws_s3_bucket.replica_bucket.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id = var.vpc_id
  service_name = "com.amazonaws.eu-central-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [var.route_table_id]

  tags = {
    Name = "S3GatewayEndpoint"
  }

  depends_on = [ 
    aws_s3_bucket_replication_configuration.replication,
    aws_s3_bucket_versioning.replica_versioning
  ]
}
