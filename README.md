# terraform-aws-jitsi

This repository contains Terraform code to create an Jitsi Meet instance on AWS backed by an RDS Aurora Serverless database for authentication. 

<div align="center">
<img src=https://i.imgur.com/tmgNxtN.png" width="200" height="200">
<p><strong>Terraform Module:</strong></p>
<p>https://registry.terraform.io/modules/hajowieland/aws/jitsi/</p>
<p><strong>Blog Post:</strong></p>
<p>https://napo.io/posts/jitsi-on-aws-with-terraform/</p>
</div>





---

## Table of Contents
- [Prerequisites](#prerequisites)
- [Features](#features)
- [Usage](#usage)
  - [Cross-Account](#mysql-with-cross-account)
  - [Single-Account](#mysql-with-one-account)
  - [Add authenticated Users](#add-authenticated-users)
- [Notes](#notes)
- [Links](#links)
- [Changelog](#changelog)
- [TODO](#todo)

---

## Prerequisites

You need the following before deploying this Terraform module:

1. AWS Account and IAM Role to deploy these AWS resources
2. Route53 Public Hosted Zone
3. Route53 Private Hosted Zone
4. _**OPTIONAL:**_ If your Route53 zones are in a different AWS Account, the IAM Role in this account to create records in the above zones.


## Features

* ✅ Jitsi Meet (Ubuntu 18.04)
  * ✅ Authentication (Users need to be authenticated to create new conferences) + Guest access (can only join existing conferences)
  * ✅ LetsEncrypt certificate for HTTPS
  * ✅ Collaborative working on a shared document during Jitsi conference ([etherpad-lite](https://github.com/ether/etherpad-lite)) 
  * ✅ SQL Database for Jitsi authorized accounts
* ✅ Aurora Serverless
  * ✅ MySQL
  * ✅ Can scale down to 0 to reduce costs
  * ❌ PostgreSQL _(can't yet scale down to zero)_
* ✅ AutoScalingGroup
  * ✅ ASG notifications (+ SNS Topic)
  * ❌ Mulitple EC2 instances (ASG > 1)
* ✅ CloudWatch Logs (+ CloudWatch Agent)
* ✅ Route53 Public & Private records
  * ✅ _OPTIONAL:_ Cross-Account for Public & Private records
* SecurityGroup
  * ✅ Allow SSH by workstation IPv4 (can be disabled)
  * ✅ Add other allowed IPv4 CIDRs for SSH
  * ✅ Restrict Jitsi access CIDRs (Default: not restricted)
* ✅ _OPTIONAL:_ AWS Key Pair (Default: true)
* ✅ _OPTIONAL:_ SSM Parameters for AWS Key Pair (Default: true)
* ✅ _OPTIONAL:_ Automatic EBS Snapshots via Data Lifecycle Manager (Default: true)


## Usage

### MySQL with cross-account

✔ Cross-account for Route53 records

✔ Allow additional CIDRs (+ your workstation's IPV4 CIDR) for SSH access

```
module "jitsi" {
  source  = "hajowieland/jitsi/aws"
  version = "1.0.0"

  aws_region = "eu-central-1"

  name   = "jitsi-meet"
  host   = "meet"
  domain = "example.com" # should match public and private hosted zone
  # will result in FQDN => meet.example.com

  ec2_instance_type = "t3a.large"
  vpc_id            = "vpc-123"
  public_subnet_ids = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
  
  # If the Route53 zones are in a different AWS Account:
  enable_cross_account = "1"
  arn_role             = "arn:aws:iam::other-account-id:role/route53-jitsi-other-account"

  public_zone_id  = "Z0123publiczone"
  private_zone_id = "Z456privatezone
  
  letsencrypt_email = "mail@example.com"

  # If you want to allow other SSH IPv4 CIDRs (in addition to your workstation's IPV4 address):
  ssh_cidrs = {
    "127.0.0.1/32"  = "first-ip-to-allow",
    "127.0.0.2/32"  = "second-ip-to-allow"
  }
}
```

### MySQL with one account

✔ Cross-account for Route53 records

✔ Only allow your workstation's IPV4 CIDR for SSH access

```
module "jitsi" {
  source     = "hajowieland/jitsi/aws"
  version    = "1.0.0"

  aws_region = "eu-west-1"

  name   = "jitsi-meet"
  host   = "meet"
  domain = "example.com" # should match public and private hosted zone
  # will result in FQDN => meet.example.com

  db_driver  = "postgresql" # Set this for Postgres

  ec2_instance_type = "t3a.medium"
  vpc_id            = "vpc-123"
  public_subnet_ids = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
  
  public_zone_id  = "Z0819publiczone"
  private_zone_id = "Z134rivatezone
  
  letsencrypt_email = "mail@example.com"
}
```

### Add authenticated Users

To create a new user in Prosody which can create new conferences, ssh into the Jitsi instance and execute:

```
prosodyctl adduser newuser@<HOST>.<DOMAIN>

# Example
prosodyctl adduser hans@meet.example.com
```


## Notes
* ↪️ The Jitsi instance can be terminated at any time (AutoScalingGroup will then start a fresh new instance, but the authorized users in the SQL database will retain)
* 💰To reduce costs, you can stop the instance (e.g. with [diodonfrost/lambda-scheduler-stop-start](https://registry.terraform.io/modules/diodonfrost/lambda-scheduler-stop-start/aws)) - Aurora Serverless will then scale down to zero.
* If you do not specify a RDS DB Subnet Group (´var.db_subnet_group_name`), then the Aurora DB will be created in the same subnets as Jitsi (⚠️Public Subnets!)
* When you enable `var.enable_cross_account` you need to specify (`var.arn_role`) an IAM role in the AWS Account where the Public & Private Route53 Zones reside in. This role has to have the policy to allow `route53:ChangeResourceRecordSets` on the desired Route53 Zones.
* Route53 records will be created in UserData => during a `terraform destroy` these records have be deleted manually (see [TODO](#TODO))
* Only MySQL is supported at the moment, because PostgreSQL in Aurora-Serverless can **not** scale down to zero


## Links
* https://github.com/jitsi/jitsi-meet/blob/master/doc/quick-install.md
* https://aws.amazon.com/blogs/opensource/getting-started-with-jitsi-an-open-source-web-conferencing-solution/ 


## Changelog

* 19/04/2020: Initial commit 🚀


## TODO

* Enable SG restriction of IPv6 subnets, too
* Enable Clustering with multiple jvb-videobridges for high availability and load balancing
* Aurora optional so user can provide pre-existing Aurora DB
* Add PostgreSQL even if it does not support scaling down to zero
* Create Terraform null_resource for destroy to delete Route53 records


<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 0.12 |
| aws | ~> 2.40 |
| http | ~> 1.2 |
| random | ~> 2.2 |
| tls | ~> 2.1 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 2.40 |
| http | ~> 1.2 |
| random | ~> 2.2 |
| tls | ~> 2.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allow\_workstation\_ipv4 | Enable / Disable to allow workstation IPv4 address to be allowed in SecurityGroup for SSH access | `bool` | `true` | no |
| apply\_immediately | Whether to apply changes to the cluster immediately or at the next maintenance window | `bool` | `true` | no |
| arn\_role | ARN of IAM role to assume in cross-account scenarios | `string` | `""` | no |
| asg\_metrics | List of metrics to collect of AutoScalingGroup | `list(string)` | <pre>[<br>  "GroupMinSize",<br>  "GroupMaxSize",<br>  "GroupDesiredCapacity",<br>  "GroupInServiceInstances",<br>  "GroupPendingInstances",<br>  "GroupStandbyInstances",<br>  "GroupTerminatingInstances",<br>  "GroupTotalInstances"<br>]</pre> | no |
| aws\_account\_id | AWS account ID | `string` | `""` | no |
| aws\_region | AWS Region (e.g. `eu-central-1`) | `string` | n/a | yes |
| backup\_retention\_days | Days for how long Backups will be retained | `number` | `30` | no |
| backup\_window | Daily time range during automated backups (if enabled - Default = true) will are created (UTC) | `string` | `"01:00-02:00"` | no |
| copy\_tags | Copy all user-defined tags on a source volume to snapshots of the volume created by this policy | `bool` | `true` | no |
| cw\_kms\_arn | KMS Key ARN for CloudWatch encryption | `string` | `null` | no |
| cw\_retention | Specifies the number of days you want to retain log events in the specified log groups (e.g. `30` => 30 days) | `number` | `30` | no |
| db\_name | Name of Database | `string` | `"jitsi"` | no |
| db\_subnet\_group\_name | Name for DB subnet group to associate with this Aurora Cluster | `string` | `null` | no |
| deletion\_protection | Enable / Disable deletion protection for this Aurora Cluster | `bool` | `false` | no |
| domain | The domain part of the Route53 A record referencing the Jitsi DNS (e.g. `example` for `jitsi.example.com`) | `string` | n/a | yes |
| ebs\_size | EBS root block device size in gigabytes (e.g. `20`) | `number` | `10` | no |
| ebs\_type | EBS root block device type (e.g. `standard`, `gp2`) | `string` | `"gp2"` | no |
| ec2\_instance\_type | EC2 instance type | `string` | n/a | yes |
| enable\_cross\_account | Enable cross-account with IAM Role to assume by UserData for updating of Route53 records (Valid values: `1` => Enable, `0` => Disable) | `string` | `"0"` | no |
| enable\_dlm | Enable / Disable Data Lifecycle Manager for automatic EBS Snapshots | `bool` | `true` | no |
| host | The host part of the Route53 A record referencing the Jitsi DNS (e.g. `jitsi` for `jitsi.example.com`) | `string` | `"meet"` | no |
| jitsi\_cidrs | IPV4 CIDRs to allow for Jitsi access | `map(string)` | <pre>{<br>  "ALL-IPv4": "0.0.0.0/0"<br>}</pre> | no |
| key\_pair\_name | Name of pre-existing AWS Key Pair name to associate with Jitsi | `string` | `null` | no |
| kms\_key | The ARN, ID or AliasARN for the KMS encryption key (RDS encryption-at-rest) | `string` | `null` | no |
| letsencrypt\_email | E-Mail address for LetsEncrypt | `string` | n/a | yes |
| name | Name for all resources (preferably generated by terraform-null-label `module.id`) | `string` | `"jitsi-meet"` | no |
| preferred\_maintenance\_window | Weekly time range during which system changes can occur (in UTC - e.g. `wed:04:00-wed:04:30` => Wednesday between 04:00-04:30) | `string` | `"sun:02:30-sun:03:30"` | no |
| private\_zone\_id | Route53 Private Hosted Zone ID to create Bastion Host DNS records | `string` | n/a | yes |
| public\_subnet\_ids | AutoScalingGroup Subnet IDs to create Jitsi Host into (=> public) | `list(string)` | n/a | yes |
| public\_zone\_id | Route53 Public Hosted Zone ID to create Bastion Host DNS records | `string` | n/a | yes |
| retain\_count | How many snapshots to keep (valid value: integeger between `1` and `1000`) | `string` | `7` | no |
| schedule\_interval | How often this lifecycle policy should be evaluated (valid values: `1`, `2`, `3`, `4`, `6`, `8`, `12` or `24`) | `number` | `24` | no |
| schedule\_name | Name of the DLM policy schedule | `string` | `"1 week of daily snapshots"` | no |
| schedule\_time | Time in 24 hour format when the policy should be evaluated (e.g. `02:30`) | `string` | `"02:30"` | no |
| serverless\_auto\_pause | SERVERLESS: Enable auto-pause after `seconds_until_auto_pause` - NOTE: If cluster is paused for >7d, cluster might be backed up with a snapshot and then restored when there is a request to connect to it) | `bool` | `true` | no |
| serverless\_http\_endpoint | Enable / Disbale the Aurora Serverless Data API HTTP endpoint | `bool` | `false` | no |
| serverless\_max | SERVERLESS: Maximum capacity units | `number` | `2` | no |
| serverless\_min | SERVERLESS: Minimum capacity units | `number` | `1` | no |
| serverless\_seconds\_pause | SERVERLESS: Seconds after which the the Serverless Aurora DB Cluster will be paused (valid values: `300` through `86400`) | `number` | `300` | no |
| serverless\_timeout\_action | SERVERLESS: Action to take when a Aurora Serverless action timeouts (e.g. `ForceApplyCapacityChange` or `RollbackCapacityChange`) | `string` | `"RollbackCapacityChange"` | no |
| ssh\_cidrs | IPV4 CIDRs to allow for SSH access | `map(string)` | `{}` | no |
| state | Enable / Disable DLM Lifecycle Policy (e.g. `ENABLED` or `DISABLED`) | `string` | `"ENABLED"` | no |
| tags | Tags as map (preferably generated by terraform-null-label `module.tags`) | `map(string)` | <pre>{<br>  "Module": "terraform-aws-jitsi",<br>  "Project": "Jitsi"<br>}</pre> | no |
| tags\_to\_add\_map | Map of extra tags to add to the snapshots | `map(string)` | <pre>{<br>  "SnapshotCreator": "DLM"<br>}</pre> | no |
| timezone | Timezone set in the EC2 instance UserData | `string` | `"Europe/Berlin"` | no |
| vpc\_id | ID of VPC | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| endpoint | Endpoint for RDS Aurora cluster |
| fqdn | FQDN of Jitsi-Meet |
| instance\_profile\_arn | ARN of EC2 Instance Profile |
| role\_arn | ARN of EC2 role |
| sg\_id | Jitsi SG ID (e.g. for adding it outside of the module to other SGs) |
| sns\_topic\_arn | Jitsi ASG scaling events SNS topic ARN |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->



