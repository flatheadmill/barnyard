machine www.flatheadmill.com
    @ datadog
    @ apt diff get+=zsh get+=wireguard
    @ users - <<'    EOF'
        user+=alan:alan,sudoers 1001:1001 /usr/bin/zsh
        user+=cory,sudoers 1002:1002 /bin/bash
    EOF

user alan shell=/usr/bin/zsh group=alan groups=sudoers

machine ftp.flatheadmill.com
    @ datadog
    @ apt diff get+=zsh get+=wireguard
    @ users diff "${sudoers[@]}" "$sally"

machine ingress.flatheadmill.com
    @bootstrap
    @ twingate connector=exuberant-eagle

machine ingress.flatheadmill.com
    @ pre_apt module/apt get+=build-essential get+=git
    @ apt get+=postgresql
    @ twingate connector=exuberant-eagle
