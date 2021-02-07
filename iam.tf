# --------------------------------------------------------------------------
# EC2 Instance Profile
# --------------------------------------------------------------------------
resource "aws_iam_role" "jitsi" {
  name = var.name

  assume_role_policy = data.aws_iam_policy_document.tr.json

  force_detach_policies = true

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "jitsi" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.jitsi.name
}

resource "aws_iam_role_policy_attachment" "attach_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.jitsi.name
}

resource "aws_iam_role_policy_attachment" "attach_CloudWatchAgentServerPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.jitsi.name
}


# IAM Intance Profile Trust Relationship: EC2, SSM
data "aws_iam_policy_document" "tr" {
  statement {
    sid     = "Ec2Ssm"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com",
        "ssm.amazonaws.com"
      ]
    }
  }
}

# Jitsi Policy document
data "aws_iam_policy_document" "jitsi" {
  statement {
    sid = "Route53"
    actions = [
      "route53:ListHostedZones",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EIPsAndTags"
    actions = [
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:CreateTags",
      "ec2:DescribeAddresses",
      "ec2:DisassociateAddress",
      "ec2:ReleaseAddress"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "UpdateRoute53"
    actions = ["route53:ChangeResourceRecordSets"]
    resources = [
      "arn:aws:route53:::hostedzone/${var.private_zone_id}",
      "arn:aws:route53:::hostedzone/${var.public_zone_id}"
    ]
  }
}

resource "aws_iam_policy" "jitsi" {
  policy = data.aws_iam_policy_document.jitsi.json
  name   = "${var.name}-jitsi"
}

resource "aws_iam_role_policy_attachment" "attach-jitsi" {
  policy_arn = aws_iam_policy.jitsi.arn
  role       = aws_iam_role.jitsi.name
}

# Cross-Account
data "aws_iam_policy_document" "assume" {
  statement {
    sid       = "CrossAccountAssume"
    actions   = ["sts:AssumeRole"]
    resources = [var.arn_role]
  }
}

resource "aws_iam_policy" "assume" {
  count = var.enable_cross_account == "1" ? 1 : 0

  name = "${var.name}-cross-account-assume"

  policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "attach_assume" {
  count = var.enable_cross_account == "1" ? 1 : 0

  policy_arn = aws_iam_policy.assume[0].arn
  role       = aws_iam_role.jitsi.name
}



# --------------------------------------------------------------------------
# OPTIONAL: DLM Lifecycle Manager Policy for automatic EBS Snapshots
# --------------------------------------------------------------------------
# Trust Relationship
data "aws_iam_policy_document" "dlm_tr" {
  count = var.enable_dlm == true ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["dlm.amazonaws.com"]
      type        = "Service"
    }
  }
}

# IAM Role
resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enable_dlm == true ? 1 : 0

  name = "${var.name}-dlm"

  assume_role_policy = data.aws_iam_policy_document.dlm_tr[0].json

  tags = local.tags
}

# IAM Policy
data "aws_iam_policy_document" "dlm" {
  count = var.enable_dlm == true ? 1 : 0

  statement {
    actions = [
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots"
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*::snapshot/*"]
  }
}

resource "aws_iam_role_policy" "dlm_lifecycle" {
  name = "${var.name}-dlm"
  role = aws_iam_role.dlm_lifecycle_role[0].id

  policy = data.aws_iam_policy_document.dlm[0].json
}