#!/bin/bash

set -e

function abend() {
    local message=$1
    echo "$message" 1>&2
    exit 1
}

cat <<'EOF' | sudo bash
set -e
set -o pipefail

rm -f /usr/local/bin/barnyard
rm -rf /etc/barnyard
rm -rf /var/barnyard/repository
rm -rf /root/.ssh

mkdir -p /etc/barnyard
mkdir -p /var/barnyard

while read -r key; do
    if [[ "$key" =~ ^pub: ]]; then
        IFS=':' read -r -a fields <<< "$key"
        gpg --yes --batch --delete-keys "${fields[4]}"
    fi
done < <(gpg --list-public-keys --with-colons)
EOF

echo "$GITHUB_KEY" | sudo bash -c 'umask 077; cat /dev/stdin > /etc/barnyard/id_barnyard'

cat <<'EOF' | sudo bash -s "$BARNYARD_SOURCE" "$@"
set -e
set -o pipefail

source="$1"
repository="$2"
branch="$3"
gpg="$4"
fingerprint="$5"

function abend() {
    local message=$1
    echo "$message" 1>&2
    exit 1
}

cat <<"EOC" > /etc/barnyard/config
repository=$repository
branch=$branch
fingerprint=$fingerprint
EOC

mkdir -p /etc/barnyard
mkdir -p /var/barnyard

umask 077
mkdir -p /root/.ssh
umask 022

gpg --quiet --import <(echo "$gpg")

known_github="github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
echo "$known_github" > /root/.ssh/known_hosts

GIT_SSH_COMMAND='ssh -i /etc/barnyard/id_barnyard -o IdentitiesOnly=yes' \
    git clone -qb "$branch" "$repository" /var/barnyard/repository 2> /dev/null

declare -a checkout=()
while read -r line; do
    IFS=' ' read -a fields <<< "$line"
    if [[ "${fields[2]}" == "$fingerprint" ]]; then
        checkout=("${fields[@]}")
        break
    fi
done < <(git -C /var/barnyard/repository log --format='%H %at %GF')

[[ "${#checkout[@]}" -eq 0 ]] && abend 'unable to find signed commit'

echo "$source" > /usr/local/bin/barnyard
chmod +x /usr/local/bin/barnyard

age-keygen -o /etc/barnyard/age 2>/dev/null
awk '/^# public key:/ { print $4 }' /etc/barnyard/age
EOF
