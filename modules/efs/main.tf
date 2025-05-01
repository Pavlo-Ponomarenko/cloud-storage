resource "aws_kms_key" "efs_key" {
  description             = "KMS key for EFS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "efs_key_alias" {
  name          = "alias/efs-key"
  target_key_id = aws_kms_key.efs_key.id
}

resource "aws_efs_file_system" "primary" {
  creation_token = "primary-efs"
  kms_key_id     = aws_kms_key.efs_key.arn
  encrypted = true
  tags = {
    Name = "PrimaryEFS"
  }
}

resource "aws_efs_mount_target" "primary" {
  file_system_id  = aws_efs_file_system.primary.id
  subnet_id = var.public_subnet_id
}

# IAM User with minimum permissions
resource "aws_iam_user" "efs_user" {
  name = "efs-mount-user"
}

resource "aws_iam_policy" "efs_policy" {
  name = "EFSMinimumAccess"
  description = "Minimum access to create and mount EFS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "elasticfilesystem:CreateFileSystem",
          "elasticfilesystem:CreateMountTarget",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:ClientMount"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "efs_attach" {
  user = aws_iam_user.efs_user.name
  policy_arn = aws_iam_policy.efs_policy.arn
}

# Create Replication Configuration
resource "aws_efs_replication_configuration" "replica" {
  source_file_system_id = aws_efs_file_system.primary.id
  destination {
    region = "eu-west-1"
  }
}