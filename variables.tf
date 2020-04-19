variable "name" {
  description = "Name for all resources (preferably generated by terraform-null-label `module.id`)"
  type        = string
}

variable "tags" {
  description = "Tags as map (preferably generated by terraform-null-label `module.tags`)"
  type        = map(string)
  default = {
    Project = "Jitsi",
    Module  = "terraform-aws-jitsi"
  }
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS Region (e.g. `eu-central-1`)"
  type        = string
}

variable "vpc_id" {
  description = "ID of VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "AutoScalingGroup Subnet IDs to create Jitsi Host into (=> public)"
  type        = list(string)
}

variable "enable_cross_account" {
  description = "Enable cross-account with IAM Role to assume by UserData for updating of Route53 records (Valid values: `1` => Enable, `0` => Disable)"
  type        = string
  default     = "0"
}

variable "arn_role" {
  description = "ARN of IAM role to assume in cross-account scenarios"
  type        = string
  default     = ""
}


# --------------------------------------------------------------------------
# Aurora Serverless
# --------------------------------------------------------------------------
variable "db_subnet_group_name" {
  description = "Name for DB subnet group to associate with this Aurora Cluster"
  type        = string
  default     = null
}

variable "kms_key" {
  description = "The ARN, ID or AliasARN for the KMS encryption key (RDS encryption-at-rest)"
  type        = string
  default     = null
}

variable "serverless_max" {
  description = "SERVERLESS: Maximum capacity units"
  type        = number
  default     = 2
}

variable "serverless_min" {
  description = "SERVERLESS: Minimum capacity units"
  type        = number
  default     = 1
}

variable "serverless_auto_pause" {
  description = "SERVERLESS: Enable auto-pause after `seconds_until_auto_pause` - NOTE: If cluster is paused for >7d, cluster might be backed up with a snapshot and then restored when there is a request to connect to it)"
  type        = bool
  default     = true
}

variable "serverless_seconds_pause" {
  description = "SERVERLESS: Seconds after which the the Serverless Aurora DB Cluster will be paused (valid values: `300` through `86400`)"
  type        = number
  default     = 300
}


variable "serverless_timeout_action" {
  description = "SERVERLESS: Action to take when a Aurora Serverless action timeouts (e.g. `ForceApplyCapacityChange` or `RollbackCapacityChange`)"
  type        = string
  default     = "RollbackCapacityChange"
}

variable "serverless_http_endpoint" {
  description = "Enable / Disbale the Aurora Serverless Data API HTTP endpoint"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of Database"
  type        = string
  default     = "jitsi"
}

variable "apply_immediately" {
  description = "Whether to apply changes to the cluster immediately or at the next maintenance window"
  type        = bool
  default     = true
}

variable "preferred_maintenance_window" {
  description = "Weekly time range during which system changes can occur (in UTC - e.g. `wed:04:00-wed:04:30` => Wednesday between 04:00-04:30)"
  type        = string
  default     = "sun:02:30-sun:03:30"
}

variable "backup_retention_days" {
  description = "Days for how long Backups will be retained"
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Daily time range during automated backups (if enabled - Default = true) will are created (UTC)"
  type        = string
  default     = "01:00-02:00"
}

variable "deletion_protection" {
  description = "Enable / Disable deletion protection for this Aurora Cluster"
  type        = bool
  default     = false
}


# --------------------------------------------------------------------------
# EC2
# --------------------------------------------------------------------------
variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ebs_type" {
  description = "EBS root block device type (e.g. `standard`, `gp2`)"
  type        = string
  default     = "gp2"
}

variable "ebs_size" {
  description = "EBS root block device size in gigabytes (e.g. `20`)"
  type        = number
  default     = 10
}

# --------------------------------------------------------------------------
# AutoScalingGroup
# --------------------------------------------------------------------------
variable "asg_metrics" {
  description = "List of metrics to collect of AutoScalingGroup"
  type        = list(string)
  default = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
  // default above => all available metrics
}


# --------------------------------------------------------------------------
# Jitsi
# --------------------------------------------------------------------------
variable "host" {
  description = "The host part of the Route53 A record referencing the Jitsi DNS (e.g. `jitsi` for `jitsi.example.com`)"
  type        = string
  default     = "meet"
}

variable "domain" {
  description = "The domain part of the Route53 A record referencing the Jitsi DNS (e.g. `example` for `jitsi.example.com`)"
  type        = string
}

variable "letsencrypt_email" {
  description = "E-Mail address for LetsEncrypt"
  type        = string
}

variable "timezone" {
  description = "Timezone set in the EC2 instance UserData"
  type        = string
  default     = "Europe/Berlin"
}

variable "public_zone_id" {
  description = "Route53 Public Hosted Zone ID to create Bastion Host DNS records"
  type        = string
}

variable "private_zone_id" {
  description = "Route53 Private Hosted Zone ID to create Bastion Host DNS records"
  type        = string
}


# --------------------------------------------------------------------------
# SecurityGroup & Key Pair
# --------------------------------------------------------------------------
variable "allow_workstation_ipv4" {
  description = "Enable / Disable to allow workstation IPv4 address to be allowed in SecurityGroup for SSH access"
  type        = bool
  default     = true
}

variable "key_pair_name" {
  description = "Name of pre-existing AWS Key Pair name to associate with Jitsi"
  type        = string
  default     = null
}

variable "ssh_cidrs" {
  description = "IPV4 CIDRs to allow for SSH access"
  type        = map(string)
  default     = {}
}

variable "jitsi_cidrs" {
  description = "IPV4 CIDRs to allow for Jitsi access"
  type        = map(string)
  default = {
    "ALL-IPv4" = "0.0.0.0/0"
  }
}


# --------------------------------------------------------------------------
# CloudWatch Logs
# --------------------------------------------------------------------------
variable "cw_kms_arn" {
  description = "KMS Key ARN for CloudWatch encryption"
  type        = string
  default     = null
}

variable "cw_retention" {
  description = "Specifies the number of days you want to retain log events in the specified log groups (e.g. `30` => 30 days)"
  type        = number
  default     = 30
}


# --------------------------------------------------------------------------
# Data Lifecycle Manager
# --------------------------------------------------------------------------
variable "enable_dlm" {
  description = "Enable / Disable Data Lifecycle Manager for automatic EBS Snapshots"
  type        = bool
  default     = true
}

variable "state" {
  description = "Enable / Disable DLM Lifecycle Policy (e.g. `ENABLED` or `DISABLED`)"
  type        = string
  default     = "ENABLED"
}

variable "schedule_name" {
  description = "Name of the DLM policy schedule"
  type        = string
  default     = "1 week of daily snapshots"
}

variable "schedule_interval" {
  description = "How often this lifecycle policy should be evaluated (valid values: `1`, `2`, `3`, `4`, `6`, `8`, `12` or `24`)"
  type        = number
  default     = 24
}

variable "schedule_time" {
  description = "Time in 24 hour format when the policy should be evaluated (e.g. `02:30`)"
  type        = string
  default     = "02:30"
}

variable "retain_count" {
  description = "How many snapshots to keep (valid value: integeger between `1` and `1000`)"
  type        = string
  default     = 7
}

variable "tags_to_add_map" {
  description = "Map of extra tags to add to the snapshots"
  type        = map(string)
  default = {
    SnapshotCreator = "DLM"
  }
}

variable "copy_tags" {
  description = "Copy all user-defined tags on a source volume to snapshots of the volume created by this policy"
  type        = bool
  default     = true
}
