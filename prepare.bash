#!/bin/bash

cat <<'EOF' | sudo bash
echo '######### apt update ##########'
apt-get update && apt-get upgrade -y && apt-get -y autoremove
echo '######### install gpg, git ##########'
apt-get install -y gpg git
echo '######### check gpg ##########'
gpg --version
echo '######### check git ##########'
git --version
echo '######### install age ##########'
age_tar=$(curl -sL https://github.com/FiloSottile/age/releases/download/v1.0.0/age-v1.0.0-linux-amd64.tar.gz | base64)
echo "$age_tar" | base64 --decode | tar xz -O age/age > /usr/local/bin/age
chmod +x /usr/local/bin/age
echo "$age_tar" | base64 --decode | tar xz -O age/age-keygen > /usr/local/bin/age-keygen
chmod +x /usr/local/bin/age-keygen
echo '######### check age ##########'
age --version
echo '######### check age-keygen ##########'
age-keygen --version
EOF
