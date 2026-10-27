setopt err_exit no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnyard=${here:h}/bin/barnyard
whence zshctl > /dev/null || { print -u 2 'fatal: zshctl is required'; exit 1 }
typeset tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/ssh-bin" "$tmp/capture"

integer failures=0
function assert_equal {
    typeset label=$1 expected=$2 actual=$3
    if [[ $actual = $expected ]]; then
        print "ok: $label"
    else
        print -u 2 "not ok: $label"
        print -u 2 "  expected: ${(qqq)expected}"
        print -u 2 "  actual:   ${(qqq)actual}"
        (( ++failures ))
    fi
}

export BARNYARD_REFRESH_CAPTURE=$tmp/capture
export BARNYARD_REFRESH_REAL_ZSHCTL=${commands[zshctl]:A}
export BARNYARD_REFRESH_REAL_MKTEMP=${commands[mktemp]:A}
export BARNYARD_REFRESH_REAL_CHMOD=${commands[chmod]:A}
export BARNYARD_REFRESH_REAL_MV=${commands[mv]:A}
export BARNYARD_REFRESH_REAL_RM=${commands[rm]:A}
export BARNYARD_REFRESH_VERSION=$($barnyard version)

cat > "$tmp/ssh-bin/ssh" <<'EOF'
#!/bin/zsh -f
print call >> "$BARNYARD_REFRESH_CAPTURE/calls"
print -rl -- "$@" > "$BARNYARD_REFRESH_CAPTURE/arguments"
cat > "$BARNYARD_REFRESH_CAPTURE/payload"
exit ${BARNYARD_REFRESH_SSH_STATUS:-0}
EOF
chmod +x "$tmp/ssh-bin/ssh"

PATH=$tmp/ssh-bin:$PATH $barnyard control refresh --destination operator@bench.invalid
assert_equal 'refresh uses one SSH connection' call "$(<$tmp/capture/calls)"
assert_equal 'refresh pins the host and uses noninteractive sudo' \
    $'-o\nConnectTimeout=30\n-o\nConnectionAttempts=1\n-o\nStrictHostKeyChecking=yes\n--\noperator@bench.invalid\n/usr/bin/sudo -n /bin/bash' \
    "$(<$tmp/capture/arguments)"

awk 'found && /^EndOfBarnyard$/ { exit } found { print } /^BARNYARD_SOURCE=/ { found=1 }' \
    "$tmp/capture/payload" > "$tmp/source"
integer result=0
cmp -s "$barnyard" "$tmp/source" || result=$?
assert_equal 'the SSH payload contains the executing source' 0 $result
typeset receiver=$(awk '/^BARNYARD_EXPECTED_VERSION=/ { found=1 } found { print }' "$tmp/capture/payload")

# Redirect only the receiving script's absolute paths. Keep the transported
# Barnyard bytes intact and execute its real version command with local zshctl.
export BARNYARD_REFRESH_ROOT=$tmp/root
receiver=${receiver//\/usr\/local\/bin/$BARNYARD_REFRESH_ROOT/usr/local/bin}
receiver=${receiver//\/usr\/bin\/zshctl/$BARNYARD_REFRESH_ROOT/usr/bin/zshctl}
print -r -- $'set -e\nset -o pipefail\n'"$receiver" > "$tmp/receive.bash"

cat > "$tmp/bin/mktemp" <<'EOF'
#!/bin/zsh -f
[[ $BARNYARD_REFRESH_FAILURE != staging ]] || exit 40
exec "$BARNYARD_REFRESH_REAL_MKTEMP" "$@"
EOF
cat > "$tmp/bin/chown" <<'EOF'
#!/bin/zsh -f
print -rl -- "$@" > "$BARNYARD_REFRESH_CAPTURE/chown"
[[ $1 = root:root && $2 = $BARNYARD_REFRESH_ROOT/usr/local/bin/.barnyard.*/barnyard ]] || exit 90
[[ $BARNYARD_REFRESH_FAILURE != ownership ]] || exit 41
EOF
cat > "$tmp/bin/chmod" <<'EOF'
#!/bin/zsh -f
[[ $1 = 0755 ]] || exit 90
[[ $BARNYARD_REFRESH_FAILURE != permissions ]] || exit 42
exec "$BARNYARD_REFRESH_REAL_CHMOD" "$@"
EOF
cat > "$tmp/zshctl" <<'EOF'
#!/bin/zsh -f
print -rl -- "$@" > "$BARNYARD_REFRESH_CAPTURE/validation"
[[ $# = 2 && $1 = $BARNYARD_REFRESH_ROOT/usr/local/bin/.barnyard.*/barnyard && $2 = version ]] || exit 90
[[ -s $BARNYARD_REFRESH_CAPTURE/chown ]] || exit 91
zmodload zsh/stat
typeset -a modes
zstat -A modes +mode "$1"
(( (modes[1] & 8#777) == 8#755 )) || exit 92
zstat -A modes +mode "${1:h}"
(( (modes[1] & 8#777) == 8#700 )) || exit 93
case $BARNYARD_REFRESH_FAILURE in
    validation|validation-cleanup) exit 43 ;;
    version) print different; exit 0 ;;
    noisy-version) print -r -- "$BARNYARD_REFRESH_VERSION"; print unexpected; exit 0 ;;
esac
exec "$BARNYARD_REFRESH_REAL_ZSHCTL" "$@"
EOF
cat > "$tmp/bin/mv" <<'EOF'
#!/bin/zsh -f
print -rl -- "$@" > "$BARNYARD_REFRESH_CAPTURE/publication"
[[ $# = 4 && $1 = -T && $2 = -- ]] || exit 90
shift 2
[[ $1 = $BARNYARD_REFRESH_ROOT/usr/local/bin/.barnyard.*/barnyard && $2 = $BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard ]] || exit 91
cmp -s "$2" "$BARNYARD_REFRESH_ROOT/old" || exit 92
[[ $BARNYARD_REFRESH_FAILURE != rename ]] || exit 44
# BSD mv lacks -T; the assertion above checks its Linux invocation. The
# actual rename below lets an open hard link witness the original inode.
exec "$BARNYARD_REFRESH_REAL_MV" -- "$@"
EOF
cat > "$tmp/bin/rm" <<'EOF'
#!/bin/zsh -f
"$BARNYARD_REFRESH_REAL_RM" "$@" || exit $?
[[ $BARNYARD_REFRESH_FAILURE != *cleanup ]] || exit 45
EOF
chmod +x "$tmp/bin/"* "$tmp/zshctl"

function reset_receiver {
    rm -rf "$BARNYARD_REFRESH_ROOT"
    rm -f "$tmp/capture/"{chown,validation,publication}
    mkdir -p "$BARNYARD_REFRESH_ROOT/usr/"{bin,local/bin}
    cp "$tmp/zshctl" "$BARNYARD_REFRESH_ROOT/usr/bin/zshctl"
    # The old executable need not work for refresh to replace it.
    print -r -- $'#!/bin/sh\nexit 99' > "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard"
    chmod +x "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard"
    cp "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" "$BARNYARD_REFRESH_ROOT/old"
    ln "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" "$BARNYARD_REFRESH_ROOT/old-inode"
}

function run_receiver {
    integer result=0
    # Supply the captured source separately: macOS Bash 3 misparses a case
    # arm inside a quoted heredoc nested in command substitution. The VM
    # proof runs the complete SSH payload through Ubuntu's Bash.
    BARNYARD_SOURCE="$(<$tmp/source)" PATH=$tmp/bin:$PATH \
        /bin/bash "$tmp/receive.bash" > "$tmp/output" 2>&1 || result=$?
    print $result
}

function assert_cleanup {
    typeset -a stages=( "$BARNYARD_REFRESH_ROOT"/usr/local/bin/.barnyard.*(N) )
    assert_equal "$1 cleans staging" 0 $#stages
}

export BARNYARD_REFRESH_FAILURE=none
reset_receiver
assert_equal 'a real candidate passes installed zshctl' 0 "$(run_receiver)"
result=0
cmp -s "$barnyard" "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" || result=$?
assert_equal 'the executing source is transferred intact' 0 $result
result=0
cmp -s "$BARNYARD_REFRESH_ROOT/old" "$BARNYARD_REFRESH_ROOT/old-inode" || result=$?
assert_equal 'publication replaces rather than truncates the old inode' 0 $result
assert_cleanup success

reset_receiver
cp "$barnyard" "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard"
print '# previous build with the same version' >> "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard"
cp "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" "$BARNYARD_REFRESH_ROOT/old"
assert_equal 'the old build reports the same version' "$BARNYARD_REFRESH_VERSION" \
    "$(zshctl "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" version)"
assert_equal 'equal versions still refresh' 0 "$(run_receiver)"
result=0
cmp -s "$barnyard" "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" || result=$?
assert_equal 'equal versions replace different bytes' 0 $result
assert_cleanup same-version

typeset failure expected
for failure expected in staging 40 ownership 41 permissions 42 validation 43 version 1 noisy-version 1 rename 44 validation-cleanup 43; do
    reset_receiver
    BARNYARD_REFRESH_FAILURE=$failure
    result=$(run_receiver)
    assert_equal "$failure fails before publication" "$expected" "$result"
    result=0
    cmp -s "$BARNYARD_REFRESH_ROOT/old" "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard" || result=$?
    assert_equal "$failure preserves the old executable" 0 $result
    assert_cleanup "$failure"
done
assert_equal 'cleanup failure preserves the validation status' 43 "$(run_receiver)"

reset_receiver
BARNYARD_REFRESH_FAILURE=cleanup
assert_equal 'cleanup failure does not reverse successful publication' 0 "$(run_receiver)"
assert_cleanup cleanup-failure

BARNYARD_REFRESH_FAILURE=none
for failure in barnyard zshctl; do
    reset_receiver
    if [[ $failure = barnyard ]]; then
        rm "$BARNYARD_REFRESH_ROOT/usr/local/bin/barnyard"
    else
        rm "$BARNYARD_REFRESH_ROOT/usr/bin/zshctl"
    fi
    assert_equal "refresh requires installed $failure" 1 "$(run_receiver)"
    assert_cleanup "missing $failure"
done

result=0
BARNYARD_REFRESH_SSH_STATUS=23 PATH=$tmp/ssh-bin:$PATH \
    $barnyard control refresh --destination operator@bench.invalid > /dev/null 2>&1 || result=$?
assert_equal 'an SSH failure fails refresh' 1 $result

rm "$tmp/capture/calls"
result=0
PATH=$tmp/ssh-bin:$PATH $barnyard control refresh > /dev/null 2>&1 || result=$?
assert_equal 'refresh requires a destination' 1 $result
result=0
PATH=$tmp/ssh-bin:$PATH $barnyard control refresh --destination operator@bench.invalid unexpected \
    > /dev/null 2>&1 || result=$?
assert_equal 'refresh rejects positional arguments' 1 $result
assert_equal 'invalid arguments do not connect' false "$([[ -e $tmp/capture/calls ]] && print true || print false)"

(( failures == 0 )) || exit 1
