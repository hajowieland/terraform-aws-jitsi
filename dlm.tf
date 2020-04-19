# --------------------------------------------------------------------------
# OPTIONAL: DLM Lifecycle Manager Policy for automatic EBS Snapshots
# --------------------------------------------------------------------------
resource "aws_dlm_lifecycle_policy" "ebs_snapshot" {
  count = var.enable_dlm == true ? 1 : 0

  description        = "${var.name} DLM lifecycle policy"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role[0].arn
  state              = var.state

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = var.schedule_name

      create_rule {
        interval      = var.schedule_interval
        interval_unit = "HOURS"
        times         = [var.schedule_time]
      }

      retain_rule {
        count = var.retain_count
      }

      tags_to_add = var.tags_to_add_map

      copy_tags = var.copy_tags
    }

    target_tags = local.tags
  }

  tags = local.tags
}
