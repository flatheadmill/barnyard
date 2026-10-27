setopt err_exit no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnyard=${here:A:h}/bin/barnyard
[[ -x $barnyard ]] || { print -u 2 'fatal: barnyard is not executable'; exit 1 }
whence zshctl > /dev/null || { print -u 2 'fatal: zshctl is required'; exit 1 }

typeset tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p $tmp/bin

cat > $tmp/bin/systemd-run <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$BARNYARD_TEST_ARGUMENTS"
printf '%s\n' fixture-output
exit "${BARNYARD_TEST_STATUS:-0}"
EOF
chmod +x $tmp/bin/systemd-run

integer failures=0
function assert_equal {
    typeset label=${1:-} expected=${2:-} actual=${3:-}
    if [[ $actual = $expected ]]; then
        print "ok: $label"
    else
        print -u 2 "not ok: $label"
        print -u 2 "  expected: ${(qqq)expected}"
        print -u 2 "  actual:   ${(qqq)actual}"
        (( ++failures ))
    fi
}

export BARNYARD_TEST_ARGUMENTS=$tmp/arguments
typeset version=$($barnyard version)
typeset output
output=$(PATH=$tmp/bin:$PATH $barnyard agent systemd apply --dry-run --version "$version")
assert_equal 'systemd apply streams output' fixture-output "$output"
assert_equal 'systemd apply constructs the transient command' \
    $'--quiet\n--wait\n--pipe\n--collect\n--property=Type=exec\n--unit=barnyard\n'$barnyard$'\nagent\napply\n--dry-run' \
    "$(<$BARNYARD_TEST_ARGUMENTS)"

output=$(PATH=$tmp/bin:$PATH $barnyard agent systemd always --version "$version" sshpop x509_rotate)
assert_equal 'systemd always streams output' fixture-output "$output"
assert_equal 'systemd always preserves operator arguments' \
    $'--quiet\n--wait\n--pipe\n--collect\n--property=Type=exec\n--unit=barnyard\n'$barnyard$'\nagent\nalways\nsshpop\nx509_rotate' \
    "$(<$BARNYARD_TEST_ARGUMENTS)"

integer result=0
BARNYARD_TEST_STATUS=23 PATH=$tmp/bin:$PATH \
    $barnyard agent systemd apply > /dev/null || result=$?
assert_equal 'systemd apply returns the process status' 23 $result

result=0
PATH=$tmp/bin:$PATH $barnyard agent systemd apply unexpected > /dev/null 2>&1 || result=$?
assert_equal 'systemd apply rejects positional arguments' 1 $result

(( failures == 0 )) || exit 1
