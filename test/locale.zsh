setopt err_exit no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnctl=$here/../bin/barnctl
typeset barnyard=$here/../bin/barnyard
typeset extension=$here/fixtures/extension
[[ -x $barnctl ]] || { print -u 2 'fatal: barnctl is not executable'; exit 1 }
[[ -x $barnyard ]] || { print -u 2 'fatal: barnyard is not executable'; exit 1 }
[[ -r $extension/barnyard.extension.zsh ]] || { print -u 2 'fatal: fixture extension is missing'; exit 1 }
for dependency in git jq zshctl; do
    whence $dependency > /dev/null || { print -u 2 "fatal: $dependency is required"; exit 1 }
done

typeset tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
umask 077
mkdir -p $tmp/work/conf/{age,machines,resources} $tmp/work/code $tmp/bin
cp -R $extension $tmp/work/code/barnyard
mkdir -p $tmp/work/code/barnyard/commands/system
cp -R $extension/commands/locale $tmp/work/code/barnyard/commands/system/locale
typeset system=$(<$extension/commands/locale/command.zsh)
print -r -- "${system//:locale/:system}" > $tmp/work/code/barnyard/commands/system/command.zsh
for command in $tmp/work/code/barnyard/commands/system/locale/**/command.zsh(N); do
    typeset body=$(<$command)
    print -r -- "${body//:locale/:system:locale}" > "$command"
done
print 'AGE-SECRET-KEY-TEST' > $tmp/work/conf/age/fixture.example

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
function assert_file_equal {
    typeset label=${1:-} expected=${2:-} actual=${3:-}
    if diff -u "$expected" "$actual"; then
        pass "$label"
    else
        fail "$label"
    fi
}
function write_manifest {
    typeset language=${1:-}
    typeset mode=${2:-diff}
    typeset implementation=${3:-barnyard.system.locale}
    cat > $tmp/work/conf/fixture.zsh <<EOF
        typeset -a labels=( alpha 'two words' )
        typeset -A settings=( region west )
        machine fixture.example code=topic/locale bootstrap=1
        @ locale/apply $mode $implementation language=$language labels@=labels \
            tags+=first 'tags+=two words' %settings
EOF
}
function generate {
    (cd $tmp/work/conf && $barnyard control generate fixture.zsh)
}
function commit_configuration {
    git -C $tmp/work/conf add .
    git -C $tmp/work/conf commit -q -m "$1"
    REPLY=$(git -C $tmp/work/conf rev-parse HEAD)
}

cat > $tmp/bin/update-locale <<'EOF'
#!/bin/sh
set -eu
jq -e --arg language "$BARNYARD_TEST_EXPECT" \
    --arg apply "$BARNYARD_TEST_APPLY" \
    --arg operator "$BARNYARD_TEST_OPERATOR" '
    ._apply == $apply and
    (if $operator == "" then
        (has("_operator") | not)
    else
        ._operator == $operator
    end) and
    .language == $language and
    .labels == ["alpha", "two words"]
' "$BARNYARD_CONFIGURATION" > /dev/null
[ "$BARNYARD_ARCHIVE" = "$BARNYARD_TEST_ARCHIVE" ]
[ "$BARNYARD_CONFIGURATION" = "$BARNYARD_TEST_CONFIGURATION" ]
[ "$BARNYARD_EXTENSION" = "$BARNYARD_TEST_EXTENSION" ]
[ "$BARNYARD_HOSTNAME" = "fixture.example" ]
[ "$BARNYARD_OPERATOR" = "locale" ]
[ "$BARNYARD_OPERATION" = "apply" ]
[ "${BARNYARD_ENVELOPE+x}" != x ]
case "$(/usr/bin/env)" in
    *AGE-SECRET-KEY-TEST*|*'two words'*) exit 1 ;;
esac
printf '%s\n' "$*" >> "$BARNYARD_TEST_LOG"
[ ! -e "$BARNYARD_TEST_FAIL" ] || exit 23
printf 'LANG=%s\n' "$BARNYARD_TEST_EXPECT" > "$BARNYARD_TEST_LOCALE"
EOF
chmod +x $tmp/bin/update-locale
cat > $tmp/bin/cat <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = /etc/default/locale ]; then
    exec /bin/cat "$BARNYARD_TEST_LOCALE"
fi
exec /bin/cat "$@"
EOF
chmod +x $tmp/bin/cat
export PATH=$tmp/bin:$PATH
export BARNYARD_TEST_LOG=$tmp/update-locale.log
export BARNYARD_TEST_FAIL=$tmp/fail-update-locale
export BARNYARD_TEST_LOCALE=$tmp/default-locale
export BARNYARD_TEST_EXTENSION=$tmp/work/code/barnyard
export BARNYARD_TEST_ARCHIVE=$tmp/work
export BARNYARD_TEST_CONFIGURATION=$tmp/work/conf/machines/fixture.example/locale.json
export BARNYARD_TEST_APPLY=diff
export BARNYARD_TEST_OPERATOR=barnyard.system.locale

write_manifest en_GB.UTF-8
generate

cat > $tmp/machine.expected.json <<'EOF'
{
  "bootstrap": "1",
  "code": "topic/locale"
}
EOF
cat > $tmp/locale.expected.json <<'EOF'
{
  "_apply": "diff",
  "_operator": "barnyard.system.locale",
  "labels": [
    "alpha",
    "two words"
  ],
  "language": "en_GB.UTF-8",
  "region": "west",
  "tags": [
    "first",
    "two words"
  ]
}
EOF
cat > $tmp/order.expected.json <<'EOF'
[
  "locale/apply"
]
EOF
assert_file_equal 'machine metadata is normalized JSON' $tmp/machine.expected.json $tmp/work/conf/machines/fixture.example/machine.json
assert_file_equal 'operator configuration is normalized JSON' $tmp/locale.expected.json $tmp/work/conf/machines/fixture.example/locale.json
assert_file_equal 'order contains only declared operator names' $tmp/order.expected.json $tmp/work/conf/machines/fixture.example/order.json

integer invalid=0
for declaration in 'bad/too/many' 'Locale' 'locale barnyard.Locale' 'locale unexpected'; do
    (( ++invalid ))
    cat > $tmp/work/conf/invalid.zsh <<EOF
        machine invalid-${invalid}.example
        @ ${(z)declaration}
EOF
    if (cd $tmp/work/conf && $barnyard control generate invalid.zsh > /dev/null 2>&1); then
        fail "invalid declaration $declaration is rejected"
    else
        pass "invalid declaration $declaration is rejected"
    fi
done
for values in 'value=scalar value+=array' 'value+=array value=scalar'; do
    (( ++invalid ))
    cat > $tmp/work/conf/invalid.zsh <<EOF
        machine invalid-${invalid}.example
        @ locale ${(z)values}
EOF
    if (cd $tmp/work/conf && $barnyard control generate invalid.zsh > /dev/null 2>&1); then
        fail "mixed operators ${(qqq)values} are rejected"
    else
        pass "mixed operators ${(qqq)values} are rejected"
    fi
done
rm -f $tmp/work/conf/invalid.zsh
rm -rf $tmp/work/conf/machines/invalid-*.example

# Compile one manifest through the old and new recorders, then normalize the
# two stores to the same meaning. The old recorder's synthetic `machine` module
# becomes machine.json metadata and is not a named operator in the new store.
mkdir -p $tmp/reference/{old,new}/{age,machines,resources}
for directory in $tmp/reference/{old,new}; do
    cat > $directory/fixture.zsh <<'EOF'
        typeset -a labels=( alpha 'two words' )
        typeset -A settings=( region west )
        function @base {
            @ locale diff language=en_GB.UTF-8 labels@=labels %settings
        }
        machine fixture.example code=topic/locale bootstrap=1
        @ @base
EOF
done
(cd $tmp/reference/old && $barnctl generate fixture.zsh)
(cd $tmp/reference/new && $barnyard control generate fixture.zsh)

typeset old=$tmp/reference/old/machines/fixture.example
typeset new=$tmp/reference/new/machines/fixture.example
typeset old_declaration=$(
    sed -n 's/^module+=//p' $old/order | grep -v '^machine$'
)
typeset old_name=${old_declaration%%/*}
typeset old_operation=${old_declaration#*/}
[[ $old_operation = $old_declaration ]] && old_operation=apply
typeset old_implementation=$(sed -n 's/^_module=//p' $old/$old_name)
[[ -n $old_implementation ]] || old_implementation=barnyard.$old_name
typeset labels=$(
    sed -n 's/^labels+=//p' $old/$old_name | jq -R . | jq -s .
)
jq -nS \
    --arg code "$(sed -n 's/^code=//p' $old/machine)" \
    --arg bootstrap "$(sed -n 's/^bootstrap=//p' $old/machine)" \
    --arg name "$old_name" \
    --arg implementation "$old_implementation" \
    --arg operation "$old_operation" \
    --arg apply "$(sed -n 's/^_apply=//p' $old/$old_name)" \
    --arg language "$(sed -n 's/^language=//p' $old/$old_name)" \
    --arg region "$(sed -n 's/^region=//p' $old/$old_name)" \
    --argjson labels "$labels" '
        {
            machine: { bootstrap: $bootstrap, code: $code },
            order: [
                {
                    implementation: $implementation,
                    name: $name,
                    operation: $operation
                }
            ],
            operators: {
                locale: {
                    _apply: $apply,
                    labels: $labels,
                    language: $language,
                    region: $region
                }
            }
        }
    ' > $tmp/reference/old.semantic.json
jq -nS \
    --slurpfile machine $new/machine.json \
    --slurpfile operator $new/locale.json \
    --slurpfile order $new/order.json '
        {
            machine: $machine[0],
            order: ($order[0] | map(
                . as $declaration |
                ($declaration | split("/")) as $parts |
                {
                    implementation: ($operator[0]._operator // ("barnyard." + $parts[0])),
                    name: $parts[0],
                    operation: ($parts[1] // "apply")
                }
            )),
            operators: { locale: ($operator[0] | del(._operator)) }
        }
    ' > $tmp/reference/new.semantic.json
assert_file_equal 'old and new recorders compile the same manifest meaning' \
    $tmp/reference/old.semantic.json $tmp/reference/new.semantic.json

git -C $tmp/work/conf init -q
git -C $tmp/work/conf config user.name 'Barnyard Test'
git -C $tmp/work/conf config user.email barnyard-test@example.invalid
git -C $tmp/work/conf config commit.gpgsign false
commit_configuration initial
typeset first_sha=$REPLY

function abend {
    print -u 2 -r -- "$*"
    return 1
}
typeset -gA zshctl
source $barnyard
BARNYARD_PATH=${barnyard:A:h}
function log { : }
export BARNYARD_TEST_EXPECT=en_GB.UTF-8
typeset -gA o_barnyard=(
    archive $tmp/work
    hostname fixture.example
    repository $tmp/work/conf
    sha1 $first_sha
    always no
    dry_run 0
    limit 100
    state $tmp/state
)
typeset -a invocations marker

:barnyard:order:operators
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
marker=( "${(z)$(< $tmp/state/applied/locale)}" )
assert_equal 'locale command dispatches once' 1 ${#invocations}
assert_equal 'locale command reads its JSON configuration' '--reset LANG=en_GB.UTF-8' "$invocations[1]"
assert_equal 'successful apply records current commit' $first_sha "$marker[1]"

:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'unchanged commit skips locale' 1 ${#invocations}

write_manifest en_CA.UTF-8
generate
commit_configuration changed-locale
typeset second_sha=$REPLY
o_barnyard[sha1]=$second_sha
export BARNYARD_TEST_EXPECT=en_CA.UTF-8
:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
marker=( "${(z)$(< $tmp/state/applied/locale)}" )
assert_equal 'changed locale configuration reruns' 2 ${#invocations}
assert_equal 'changed locale invocation uses new language' '--reset LANG=en_CA.UTF-8' "$invocations[-1]"
assert_equal 'changed locale advances applied marker' $second_sha "$marker[1]"

write_manifest en_AU.UTF-8
generate
commit_configuration failing-locale
typeset third_sha=$REPLY
o_barnyard[sha1]=$third_sha
export BARNYARD_TEST_EXPECT=en_AU.UTF-8
touch $BARNYARD_TEST_FAIL
if :barnyard:run locale/apply; then
    fail 'failed locale command returns nonzero'
else
    assert_equal 'failed locale command returns its status' 23 $?
fi
marker=( "${(z)$(< $tmp/state/applied/locale)}" )
assert_equal 'failed locale command does not advance marker' $second_sha "$marker[1]"

rm -f $BARNYARD_TEST_FAIL
write_manifest en_NZ.UTF-8 once barnyard.locale
generate
commit_configuration once-default-implementation
typeset once_sha=$REPLY
o_barnyard[sha1]=$once_sha
export BARNYARD_TEST_EXPECT=en_NZ.UTF-8
export BARNYARD_TEST_APPLY=once
export BARNYARD_TEST_OPERATOR=
rm -f $tmp/state/applied/locale $BARNYARD_TEST_LOG
if jq -e 'has("_operator") | not' \
    $tmp/work/conf/machines/fixture.example/locale.json > /dev/null
then
    pass 'default implementation is omitted from operator configuration'
else
    fail 'default implementation is omitted from operator configuration'
fi
:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'default implementation dispatches successfully' 1 ${#invocations}
assert_equal 'once runs without an applied marker' 1 ${#invocations}
:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'once skips with an applied marker' 1 ${#invocations}

write_manifest en_NZ.UTF-8 always barnyard.locale
generate
commit_configuration always
typeset always_sha=$REPLY
o_barnyard[sha1]=$always_sha
export BARNYARD_TEST_APPLY=always
rm -f $BARNYARD_TEST_LOG
:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'always runs with a stale applied marker' 1 ${#invocations}
:barnyard:run locale/apply
invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'always runs with a current marker and unchanged commit' 2 ${#invocations}

write_manifest en_NZ.UTF-8 never barnyard.locale
generate
commit_configuration never
o_barnyard[sha1]=$REPLY
export BARNYARD_TEST_APPLY=never
rm -f $BARNYARD_TEST_LOG
:barnyard:run locale/apply
invocations=()
[[ ! -e $BARNYARD_TEST_LOG ]] ||
    invocations=( "${(@f)$(<$BARNYARD_TEST_LOG)}" )
assert_equal 'never does not dispatch' 0 ${#invocations}

if (( failures )); then
    print -u 2 "$failures locale vertical assertion(s) failed"
    exit 1
fi
print 'locale vertical passed'
