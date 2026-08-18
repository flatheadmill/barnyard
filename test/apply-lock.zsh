#!/usr/bin/env zsh

setopt err_exit no_bg_nice no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnyard=$here/../bin/barnyard
typeset tmp=$(mktemp -d)
typeset first_pid=

function cleanup {
    [[ -n $first_pid ]] && kill $first_pid 2>/dev/null || true
    rm -rf $tmp
}
trap cleanup EXIT

cat > $tmp/apply <<EOF
#!/usr/bin/env zsh
typeset -gA zshctl
source ${(q)barnyard}
function abend { print -u 2 -r -- "\$*"; exit 73 }
function :barnyard:apply:body {
    print -r -- \$sysparams[pid] > ${(q)tmp}/body.\$o_barnyard[operation]
    [[ \$o_barnyard[operation] != first ]] ||
        while [[ ! -e ${(q)tmp}/release ]]; do sleep 0.05; done
}
typeset -gA o_barnyard=(
    lock ${(q)tmp}/apply.lock
    operation \$1
)
:barnyard:apply
EOF
chmod 755 $tmp/apply

$tmp/apply first >$tmp/first.out 2>$tmp/first.err &
first_pid=$!
integer attempt
for attempt in {1..100}; do
    [[ -e $tmp/body.first ]] && break
    sleep 0.05
done
[[ -e $tmp/body.first ]] || { print -u 2 'first apply did not acquire the lock'; exit 1 }
kill -0 $first_pid 2>/dev/null || { print -u 2 'first apply exited before contention'; exit 1 }

setopt local_options no_err_exit
typeset output
output=$($tmp/apply second 2>&1)
integer code=$?
setopt err_exit
[[ $code = 73 ]] || { print -u 2 "second apply exited $code, expected 73"; exit 1 }
[[ $output = *'another Barnyard apply is running'* ]] || {
    print -u 2 'second apply did not report lock contention'
    exit 1
}
typeset holder_pid=$(<$tmp/body.first)
[[ $output = *"pid=$holder_pid operation=first"* ]] || {
    print -u 2 "second apply did not name the holder: $output"
    exit 1
}
[[ ! -e $tmp/body.second ]] || { print -u 2 'second apply entered the apply body'; exit 1 }

touch $tmp/release
wait $first_pid
first_pid=
$tmp/apply third
[[ -e $tmp/body.third ]] || { print -u 2 'apply lock was not released'; exit 1 }

print 'apply lock passed'
