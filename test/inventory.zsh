setopt err_exit no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnyard=$here/../bin/barnyard
[[ -x $barnyard ]] || { print -u 2 'fatal: barnyard is not executable'; exit 1 }
for dependency in jq zshctl; do
    whence $dependency > /dev/null || { print -u 2 "fatal: $dependency is required"; exit 1 }
done

typeset tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p $tmp/conf/{age,machines,resources}

integer failures=0
function fail {
    print -u 2 "not ok: $1"
    (( ++failures ))
}
function pass {
    print "ok: $1"
}
function assert_equal {
    typeset label=${1:-} expected=${2:-} actual=${3:-}
    if [[ $actual = $expected ]]; then
        pass "$label"
    else
        print -u 2 "not ok: $label"
        print -u 2 "  expected: ${(qqq)expected}"
        print -u 2 "  actual:   ${(qqq)actual}"
        (( ++failures ))
    fi
}

cat > $tmp/conf/common.zsh <<'EOF'
function @standard {
    @ locale diff language=en_US.UTF-8
}
EOF

cat > $tmp/conf/first.zsh <<'EOF'
typeset dir=${${0:a}:h}
source $dir/common.zsh

machine alpha.example code=main
    @ @standard

machine bravo.example code=main
    @ locale diff language=en_GB.UTF-8

machine disabled.example enabled=0
    @ locale

machine excluded.example code=main
    @ locale
EOF

cat > $tmp/conf/second.zsh <<'EOF'
machine charlie.example code=main
    @ locale
EOF

typeset output
output=$(
    cd $tmp/conf
    $barnyard control inventory --include '*.example' \
        --exclude 'excluded.*' first.zsh second.zsh
)
assert_equal 'inventory lists the generated selection' \
    $'alpha.example\nbravo.example\ncharlie.example' "$output"

typeset -a artifacts=( $tmp/conf/{age,machines,resources}/*(N) )
if (( $#artifacts == 0 )); then
    pass 'inventory does not change the configuration tree'
else
    fail 'inventory does not change the configuration tree'
fi

(
    cd $tmp/conf
    $barnyard control generate --include '*.example' \
        --exclude 'excluded.*' first.zsh second.zsh
)
typeset machine
typeset -a generated=()
for machine in $tmp/conf/machines/*(N/); do
    generated+=( "${machine:t}" )
done
assert_equal 'inventory and generation select the same machines' \
    "$output" "${(F)generated}"

output=$(
    cd $tmp/conf
    $barnyard control inventory --include 'nobody.*' first.zsh
)
assert_equal 'an empty inventory succeeds with empty output' '' "$output"

cat > $tmp/conf/invalid.zsh <<'EOF'
machine broken.example
    @ locale unknown-value
EOF
if (cd $tmp/conf && $barnyard control inventory invalid.zsh > /dev/null 2>&1); then
    fail 'an invalid manifest fails inventory'
else
    pass 'an invalid manifest fails inventory'
fi

if (cd $tmp/conf && $barnyard control inventory > /dev/null 2>&1); then
    fail 'inventory requires a manifest'
else
    pass 'inventory requires a manifest'
fi

(( failures == 0 )) || exit 1
