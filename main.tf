# Data resources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
}
data "aws_region" "current" {}


# --------------------------------------------------------------------------
# Ubuntu 18.04 AMI
# --------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# --------------------------------------------------------------------------
# Get Subnet CIDRs
# --------------------------------------------------------------------------
data "aws_subnet" "subnet" {
  count = length(var.public_subnet_ids)

  id     = var.public_subnet_ids[count.index]
  vpc_id = var.vpc_id
}

# --------------------------------------------------------------------------
# Locals
# --------------------------------------------------------------------------
locals {
  tags = merge(
    var.tags,
    map(
      "Name", var.name
    )
  )
  tags_as_list_of_maps = flatten([
    for key in keys(local.tags) : merge(
      {
        key   = key
        value = local.tags[key]
    }, { propagate_at_launch = "true" })
  ])
  account_id                = var.aws_account_id == "" ? data.aws_caller_identity.current.account_id : var.aws_account_id
}


# --------------------------------------------------------------------------
# OPTIONAL: Generate secure RSA Key Pair
# --------------------------------------------------------------------------
resource "tls_private_key" "jitsi" {
  count = var.key_pair_name == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jitsi" {
  count = var.key_pair_name == null ? 1 : 0

  key_name   = var.name
  public_key = tls_private_key.jitsi[0].public_key_openssh
}

# --------------------------------------------------------------------------
# OPTIONAL: SSM Parameter Store
# --------------------------------------------------------------------------
resource "aws_ssm_parameter" "jitsi_ssm_key_pair_private" {
  count = var.key_pair_name == null ? 1 : 0

  name        = "/jitsi/id_rsa"
  description = "SSH Private Key for Jitsi - ${var.name}"
  type        = "SecureString"
  value       = tls_private_key.jitsi[0].private_key_pem
  overwrite   = true

  tags = local.tags
}

resource "aws_ssm_parameter" "jitsi_ssm_key_pair_public" {
  count = var.key_pair_name == null ? 1 : 0

  name        = "/jitsi/id_rsa.pub"
  description = "SSH Public Key for Jitsi - ${var.name}"
  type        = "String"
  value       = tls_private_key.jitsi[0].public_key_openssh
  overwrite   = true

  tags = local.tags
}


# --------------------------------------------------------------------------
# Security Group
# --------------------------------------------------------------------------
resource "aws_security_group" "jitsi" {
  name_prefix = "${var.name}-"
  description = "Jitsi Meet"
  vpc_id      = var.vpc_id

  tags = local.tags
}

resource "aws_security_group_rule" "letsencrypt" {
  description       = "LetsEncrypt http-01 Challenge"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.jitsi.id
}

resource "aws_security_group_rule" "ssh" {
  for_each = var.ssh_cidrs

  description       = "SSH: ${each.key}"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.jitsi.id
}

resource "aws_security_group_rule" "tcp" {
  for_each = var.jitsi_cidrs

  description       = "TCP: ${each.key}"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.jitsi.id
}

resource "aws_security_group_rule" "udp" {
  for_each = var.jitsi_cidrs

  description       = "UDP: ${each.key}"
  type              = "ingress"
  from_port         = 10000
  to_port           = 10000
  protocol          = "udp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.jitsi.id
}

resource "aws_security_group_rule" "egress" {
  description       = "Egress: ALL"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.jitsi.id
}

# --------------------------------------------------------------------------
# CloudWatch Log Group
# --------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "jitsi" {
  name              = var.name
  retention_in_days = var.cw_retention
  kms_key_id        = var.cw_kms_arn

  tags = local.tags
}

# --------------------------------------------------------------------------
# Launch Template
# --------------------------------------------------------------------------
resource "aws_launch_template" "jitsi" {
  name = var.name

  iam_instance_profile {
    name = aws_iam_instance_profile.jitsi.name
  }

  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.ec2_instance_type
  key_name      = var.key_pair_name == null ? aws_key_pair.jitsi[0].id : var.key_pair_name
  ebs_optimized = true

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = var.ebs_type
      volume_size           = var.ebs_size
      delete_on_termination = true
      encrypted             = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/userdata.tpl", {
    arn_role                 = var.arn_role
    aws_region               = var.aws_region
    cross_account            = var.enable_cross_account
    db_host                  = aws_rds_cluster.aurora.endpoint
    db_name                  = aws_rds_cluster.aurora.database_name
    db_user                  = aws_rds_cluster.aurora.master_username
    db_password              = aws_rds_cluster.aurora.master_password
    domain                   = var.domain
    host                     = var.host
    letsencrypt_email        = var.letsencrypt_email
    log_group_name           = aws_cloudwatch_log_group.jitsi.id
    name                     = var.name
    public_zone_id           = var.public_zone_id
    private_zone_id          = var.private_zone_id
    timezone                 = var.timezone
    prosody_user             = var.jitsi_admin_username
    prosody_password         = var.jitsi_admin_password
    enable_welcome_page      = var.enable_welcome_page
    default_background_color = var.default_background_color
    watermark_url            = var.watermark_url
    language_detection       = var.language_detection
    default_language         = var.default_language
  }))

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.jitsi.id]
  }


  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}


# --------------------------------------------------------------------------
# AutoScalingGroup
# --------------------------------------------------------------------------
resource "aws_autoscaling_group" "jitsi" {
  name              = var.name
  max_size          = 1
  min_size          = 1
  desired_capacity  = 1
  force_delete      = true
  health_check_type = "EC2"

  launch_template {
    id      = aws_launch_template.jitsi.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.public_subnet_ids
  enabled_metrics     = var.asg_metrics

  tags = local.tags_as_list_of_maps
}


# --------------------------------------------------------------------------
# SNS Topic
# --------------------------------------------------------------------------
resource "aws_sns_topic" "jitsi" {
  name = var.name

  tags = local.tags
}

# --------------------------------------------------------------------------
# AutoScaling notification --> SNS topic
# --------------------------------------------------------------------------
resource "aws_autoscaling_notification" "jitsi" {
  group_names = [aws_autoscaling_group.jitsi.name]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = aws_sns_topic.jitsi.arn
}


# --------------------------------------------------------------------------
# Elastic IP Address (=EIP)
# --------------------------------------------------------------------------
resource "aws_eip" "eip" {
  vpc = true

  tags = local.tags
}
