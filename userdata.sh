#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# Update all packages
function update_system() {
  apt-get update
  apt-get upgrade -y -q
  apt-get install -y -q apt-transport-https jq mysql-client python-pip
  pip install awscli
}

function associate_eip() {
  echo "Associate EIP ..."
  export AWS_DEFAULT_REGION=${aws_region}
  export INSTANCE_ID=$(curl -sLf http://169.254.169.254/latest/meta-data/instance-id)

  # Get free EIPs with matching Name tag and which are not associated with an InstanceId
  for eip in $(aws ec2 describe-addresses --filters Name=tag:Name,Values=${name} --query 'Addresses[*]' --output json | jq -r '.[] | select(.InstanceId == null)  | .AllocationId')
  do
    if [ "$eip" == null ]
    then
      continue
    else
      aws ec2 associate-address --allocation-id $eip --instance-id $INSTANCE_ID
      EXITCODE=$?
      if [ $EXITCODE -ne 0 ]
      then
        continue
      else
        break
      fi
    fi
  done
}

# Set Hostname, Timezone
function set_hostname_timezone() {
  echo "Set Hostname"
  hostnamectl set-hostname --static "${host}.${domain}"
  export HOSTNAME="${host}.${domain}"

  echo "Set Timezone"
  timedatectl set-timezone ${timezone}
}

function update_private_route53() {
  # Update route53 record
  dnshostname=$(curl -fs http://169.254.169.254/latest/meta-data/public-hostname)
  file=/tmp/privaterecord.json
  cat << EOF > $file
{
  "Comment": "Update the A record set",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${host}.${domain}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "$dnshostname"
          }
        ]
      }
    }
  ]
}
EOF
  if [ "${cross_account}" == "1" ]; then
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    creds=$(aws sts assume-role --role-arn "${arn_role}" --role-session-name jitsi | jq -r '.Credentials')
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.SessionToken')
  fi
  echo "Updating Route53 Private Hosted Zone record"
  aws route53 change-resource-record-sets --hosted-zone-id ${private_zone_id} --change-batch file://$file
}

function update_public_route53() {
  # Update route53 record
  dnshostname=$(curl -fs http://169.254.169.254/latest/meta-data/public-hostname)
  file=/tmp/publicrecord.json
  cat << EOF > $file
{
  "Comment": "Update the A record set",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${host}.${domain}",
        "Type": "CNAME",
        "TTL": 30,
        "ResourceRecords": [
          {
            "Value": "$dnshostname"
          }
        ]
      }
    }
  ]
}
EOF
  if [ "${cross_account}" == "1" ]; then
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    creds=$(aws sts assume-role --role-arn ${arn_role} --role-session-name jitsi | jq -r '.Credentials')
    export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.SessionToken')
  fi
  echo "Updating Route53 Public Hosted Zone record"
  aws route53 change-resource-record-sets --hosted-zone-id ${public_zone_id} --change-batch file://$file
}

function add_jitsi_sources(){
  # Add Jitsi sources
  echo 'deb https://download.jitsi.org stable/' >> /etc/apt/sources.list.d/jitsi-stable.list
  wget -qO - https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -
  apt-get update
}

function install_etherpad(){
  # Install Etherpad
  curl -sL https://deb.nodesource.com/setup_13.x | sudo -E bash -
  apt install -y nodejs
  cd /opt/ || exit
  adduser --system --home /opt/etherpad --group etherpad-lite
  cd /opt/etherpad || exit
  git clone --branch master https://github.com/ether/etherpad-lite.git
  chown -R etherpad-lite:etherpad-lite /opt/etherpad/etherpad-lite
}

function start_etherpad(){
  # Etherpad Systemd
  cat << 'EOF' > /etc/systemd/system/etherpad-lite.service
[Unit]
Description=Etherpad-lite, the collaborative editor.
After=syslog.target network.target

[Service]
Type=simple
User=etherpad-lite
Group=etherpad-lite
WorkingDirectory=/opt/etherpad/etherpad-lite
Environment=NODE_ENV=production
ExecStart=/bin/sh /opt/etherpad/etherpad-lite/bin/run.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable etherpad-lite
  systemctl start etherpad-lite
}

function raise_system_limits() {
  # Raise Limits
  echo "DefaultLimitNOFILE=65000" >> /etc/systemd/system.conf
  echo "DefaultLimitNPROC=65000" >> /etc/systemd/system.conf
  echo "DefaultTasksMax=65000" >> /etc/systemd/system.conf
  systemctl daemon-reload
}

function configure_jitsi_install() {
  # Configure Jitsi Install
  echo "jitsi-videobridge jitsi-videobridge/jvb-hostname string $HOSTNAME" | debconf-set-selections
  echo "jitsi-meet-web-config jitsi-meet/cert-choice select 'Generate a new self-signed certificate'" | debconf-set-selections
}

function install_jitsi() {
  # Install Jitsi, Jitsi PostgreSQL support
  apt-get --option=Dpkg::Options::=--force-confold --option=Dpkg::options::=--force-unsafe-io --assume-yes --quiet install jitsi-meet lua-dbi-mysql
}

function configure_prosody() {
  # Configure Prosody (PostgreSQL, Admin User)
  sed -i "s/--storage = \"sql\".*/storage = \"sql\"/g" /etc/prosody/prosody.cfg.lua
  sed -i "s/--sql = { driver = \"MySQL\".*/sql = { driver = \"MySQL\", database = \"${db_name}\", username = \"${db_user}\", password = \"${db_password}\", host = \"${db_host}\" }/g" /etc/prosody/prosody.cfg.lua
}

function create_mysql_client_config() {
  echo "Configure MySQL client preference file"
  export MYSQL_PREF=/etc/.my.cnf
  cat <<EOF > $MYSQL_PREF
[client]
user=${db_user}
password="${db_password}"
port=3306
host="${db_host}"
EOF
  ln -s $MYSQL_PREF /root/.my.cnf
}

function convert_datastores() {
  cat <<EOT >> /tmp/migrator.cfg.lua
filestore {
         type = "prosody_files";
         path = "/var/lib/prosody";
}
database {
         type = "prosody_sql";
         driver = "MySQL";
         database = "${db_name}";
         username = "${db_user}";
         password = "${db_password}";
         host = "${db_host}";
}
EOT
  TABLECOUNT=$(mysql --defaults-file=$MYSQL_PREF ${db_name} -s --skip-column-names -e "SELECT COUNT(*) FROM prosody;")
  echo "TABLECOUNT: $TABLECOUNT"
  if [ $TABLECOUNT -lt 2 ]; then
    echo "Migrate from filestore to Database"
    # Has to be set in UserData (not set by default) or otherwise prosody-migrator will fail...
    export HOME=/root
    prosody-migrator filestore database --config=/tmp/migrator.cfg.lua
  else
    PROSODYDIR=$(echo "auth.$HOSTNAME" | sed 's/[.]/%2e/g')
    FOCUSPW=$(grep -oP '"\K[^"\047]+(?=["\047];)' /var/lib/prosody/$PROSODYDIR/accounts/focus.dat)
    JVBPW=$(grep -oP '"\K[^"\047]+(?=["\047];)' /var/lib/prosody/$PROSODYDIR/accounts/jvb.dat)
    mysql --defaults-file=$MYSQL_PREF ${db_name} -s --skip-column-names -e "UPDATE prosody SET value = '$FOCUSPW' WHERE host = 'auth.$HOSTNAME' AND user = 'focus';"
    mysql --defaults-file=$MYSQL_PREF ${db_name} -s --skip-column-names -e "UPDATE prosody SET value = '$JVBPW' WHERE host = 'auth.$HOSTNAME' AND user = 'jvb';"
  fi
}
function configure_authentication() {
  # Configure Authentication
  sed -i "s|// anonymousdomain:.*|anonymousdomain: 'guest.$HOSTNAME',|g" /etc/jitsi/meet/$HOSTNAME-config.js
  sed -i "s/authentication = \"anonymous\"/authentication = \"internal_plain\"/g" /etc/prosody/conf.avail/$HOSTNAME.cfg.lua
  cat <<EOT >> /etc/prosody/conf.avail/$HOSTNAME.cfg.lua

VirtualHost "guest.$HOSTNAME"
    authentication = "anonymous"
    c2s_require_encryption = false
EOT

  echo "org.jitsi.jicofo.auth.URL=XMPP:$HOSTNAME" >> /etc/jitsi/jicofo/sip-communicator.properties
}

function configure_nginx() {
  cp /usr/share/jitsi-meet/interface_config.js /etc/jitsi/meet/$HOSTNAME-interface_config.js
  sed -i "s|^}|\    location ^~ /etherpad/ {\n        proxy_pass http://localhost:9001/;\n        proxy_set_header X-Forwarded-For \$remote_addr;\n        proxy_buffering off;\n        proxy_set_header       Host \$host;\n    }\n}|g" /etc/nginx/sites-enabled/$HOSTNAME.conf
  sed -i "s|^}|\    location = /interface_config.js {\n        alias /etc/jitsi/meet/$HOSTNAME-interface_config.js;\n    }\n}|g" /etc/nginx/sites-enabled/$HOSTNAME.conf
}

function configure_meet() {
  sed -i "/makeJsonParserHappy.*/i\    etherpad_base: 'https://$HOSTNAME/etherpad/p/'", /etc/jitsi/meet/$HOSTNAME-config.js
}

function create_awscli_conf() {
  echo "Creating awscli.conf for CloudWatch Agent"
  mkdir -p /etc/awslogs
  cat << 'EOF' > /etc/awslogs/awscli.conf
[plugins]
cwlogs = cwlogs
[default]
region = ${aws_region}
EOF
}

function create_awslogs_conf() {
  mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
  cat << 'EOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 30,
    "logfile": "/var/log/amazon-cloudwatch-agent.log",
    "debug": true
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/cloud-init-output.log"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/cloud-init.log"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/auth.log"
          },
          {
            "file_path": "/var/log/boot.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/boot.log"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/dpkg.log"
          },
          {
            "file_path": "/var/log/kern.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/kern.log"
          },
          {
            "file_path": "/var/log/jitsi/jicofo.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/jicofo.log"
          },
          {
            "file_path": "/var/log/jitsi/jvb.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/jvb.log"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/nginx/error.log"
          },
          {
            "file_path": "/var/log/prosody/prosody.err",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/prosody.err"
          },
          {
            "file_path": "/var/log/prosody/prosody.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/prosody.log"
          }
        ]
      }
    }
  }
}
EOF
}

function install_coudwatchagent() {
  echo "Install CloudWatch Agent"
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i amazon-cloudwatch-agent.deb
  echo "Enable CloudWatch Agent at boot via systemd"
  systemctl enable amazon-cloudwatch-agent
}

function letsencrypt() {
  sed -i "s/^read EMAIL/export EMAIL=\"${letsencrypt_email}\"/g" /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
  FILE=/etc/letsencrypt/live/$HOSTNAME/cert.pem
  if [ ! -f "$FILE" ]; then
    echo "Getting LetsEncrypt cert ..."
    /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
  else
    echo "LetsEncrypt cert found, do NOT install again"
  fi
}

function restart_services() {
  # Restart services
  systemctl restart amazon-cloudwatch-agent
  systemctl restart nginx
  systemctl restart prosody
  systemctl restart jicofo
  systemctl restart jitsi-videobridge2
}


# START
update_system
associate_eip
set_hostname_timezone
sleep 5
update_public_route53

if [ "${private_record}" == "1" ]; then
  update_private_route53
fi
create_awscli_conf
create_awslogs_conf
install_coudwatchagent
add_jitsi_sources
install_etherpad
start_etherpad
raise_system_limits
configure_jitsi_install
install_jitsi
configure_prosody
restart_services
letsencrypt
configure_authentication
configure_nginx
configure_meet
restart_services
sleep 5
create_mysql_client_config
convert_datastores
restart_services
# END
