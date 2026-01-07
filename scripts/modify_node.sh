#! /bin/bash
sudo hostnamectl set-hostname $1
cat <<EOF | sudo tee /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: 
        - $2/$3
      routes:
        - to: default
          via: $4
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF
sudo netplan apply