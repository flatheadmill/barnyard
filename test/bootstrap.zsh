setopt err_exit no_unset pipe_fail

typeset here=${${(%):-%x}:A:h}
typeset barnyard=$here/../bin/barnyard
typeset fixture=$here/fixtures/github-public.asc
[[ -x $barnyard ]] || { print -u 2 'fatal: barnyard is not executable'; exit 1 }
[[ -r $fixture ]] || { print -u 2 'fatal: public-key fixture is missing'; exit 1 }
whence jo > /dev/null || { print -u 2 'fatal: jo is required'; exit 1 }
whence jq > /dev/null || { print -u 2 'fatal: jq is required'; exit 1 }
whence gpg > /dev/null || { print -u 2 'fatal: gpg is required'; exit 1 }
whence zshctl > /dev/null || { print -u 2 'fatal: zshctl is required'; exit 1 }

typeset barnyard_version=$($barnyard version)
typeset real_gpg=${commands[gpg]:A} real_jo=${commands[jo]:A}
typeset zshctl_functions=${${commands[zshctl]:A}:h:h}/share/zshctl/functions
[[ -d $zshctl_functions ]] || {
    print -u 2 'fatal: unable to find the zshctl function library'
    exit 1
}

integer failures=0
function assert {
    typeset label=${1:-} value=${2:-} pattern=${3:-}
    if [[ $value = ${~pattern} ]]; then
        print "ok: $label"
    else
        print -u 2 "FAIL: $label"
        (( failures++, 1 ))
    fi
    true
}

function assert_not {
    typeset label=${1:-} value=${2:-} pattern=${3:-}
    if [[ $value != ${~pattern} ]]; then
        print "ok: $label"
    else
        print -u 2 "FAIL: $label"
        (( failures++, 1 ))
    fi
    true
}

function line_count {
    typeset value=$1 line=$2
    integer count=0
    typeset item
    for item in "${(@f)value}"; do
        [[ $item = $line ]] && (( count++, 1 ))
    done
    print $count
}

function probe_receiver {
    setopt local_options no_err_exit
    typeset payload=$1 mode=${2:-success}
    print -rn -- "$payload" |
        BARNYARD_TEST_MODE=$mode \
        BARNYARD_TEST_GPG_HOME=$tmp/gpg-home \
        BARNYARD_TEST_GPG_SCRATCH=$tmp/gpg-scratch \
        BARNYARD_REAL_GPG=$real_gpg \
        INVOCATION_ID=test \
        PATH=$tmp/bin:$PATH \
        zsh -fc '
            typeset -A zshctl
            source bin/barnyard
            function abend { print -u 2 -- "$*"; exit 1 }
            function :barnyard:hostname { print bench.invalid }
            function :barnyard:distribution { print ubuntu }
            function exemplar { "$@" }
            function :barnyard:ssh:known-hosts {
                cat > /dev/null
                print APPLY_known-hosts
            }
            function :barnyard:ssh:private-key {
                cat > /dev/null
                print APPLY_private-key
                [[ $BARNYARD_TEST_MODE != fail-private ]]
            }
            function :barnyard:gpg:import {
                cat > /dev/null
                print APPLY_gpg-import
            }
            function :barnyard:gpg:trust { print "APPLY_gpg-trust:$o_fingerprint" }
            function :barnyard:clone { print "APPLY_clone:$o_repository" }
            :barnyard:agent:bootstrap
        ' 2>&1
    typeset receiver_status=$pipestatus[2]
    print "RECEIVER_STATUS=$receiver_status"
}

function run_real_receiver {
    setopt local_options no_err_exit
    typeset payload=$1
    print -rn -- "$payload" |
        BARNYARD_TEST_ETC=$tmp/root/etc/barnyard \
        BARNYARD_TEST_VAR=$tmp/root/var/lib/barnyard \
        BARNYARD_TEST_GPG_HOME=$tmp/gpg-home \
        BARNYARD_TEST_GPG_SCRATCH=$tmp/gpg-scratch \
        BARNYARD_TEST_GPG_IMPORTS=$tmp/gpg-imports \
        BARNYARD_TEST_GPG_TRUSTS=$tmp/gpg-trusts \
        BARNYARD_REAL_GPG=$real_gpg \
        BARNYARD_TEST_ZSHCTL_FUNCTIONS=$zshctl_functions \
        INVOCATION_ID=test \
        PATH=$tmp/bin:$PATH \
        zsh -fc '
            fpath=( "$BARNYARD_TEST_ZSHCTL_FUNCTIONS" $fpath )
            autoload -Uz abend exemplar
            typeset -A zshctl
            source bin/barnyard
            function :barnyard:hostname { print bench.invalid }
            function :barnyard:distribution { print ubuntu }

            typeset name body
            typeset root_check='"'"'(( $EUID == 0 ))'"'"'
            typeset etc_path=/etc/barnyard var_path=/var/lib/barnyard
            for name in :barnyard:ssh:known-hosts :barnyard:ssh:private-key \
                :barnyard:gpg:import :barnyard:gpg:trust :barnyard:clone
            do
                body=$functions[$name]
                body=${body//$root_check/true}
                body=${body//$etc_path/$BARNYARD_TEST_ETC}
                body=${body//$var_path/$BARNYARD_TEST_VAR}
                functions[$name]=$body
            done

            :barnyard:agent:bootstrap
        ' 2>&1
    typeset receiver_status=$pipestatus[2]
    print "RECEIVER_STATUS=$receiver_status"
}

typeset tmp=$(mktemp -d)
{
    mkdir -p $tmp/bin $tmp/capture $tmp/gpg-home $tmp/gpg-scratch
    chmod 700 $tmp/gpg-home $tmp/gpg-scratch

    cat > $tmp/bin/ssh <<'EOF'
#!/bin/zsh
print call >> $BARNYARD_CAPTURE/calls
print -rl -- "$@" > $BARNYARD_CAPTURE/ssh-argv
cat > $BARNYARD_CAPTURE/stdin
EOF
    chmod 755 $tmp/bin/ssh

    cat > $tmp/bin/jo <<'EOF'
#!/bin/zsh
print -rl -- "$@" > $BARNYARD_CAPTURE/jo-argv
exec "$BARNYARD_REAL_JO" "$@"
EOF
    chmod 755 $tmp/bin/jo

    cat > $tmp/bin/gpg <<'EOF'
#!/bin/zsh
if [[ " $* " = *' --import '* ]]; then
    typeset key=${argv[-1]}
    "$BARNYARD_REAL_GPG" --homedir "$BARNYARD_TEST_GPG_HOME" \
        --batch --with-colons --show-keys "$key" > /dev/null || exit
    print imported >> "$BARNYARD_TEST_GPG_IMPORTS"
elif [[ " $* " = *' --sign-key '* ]]; then
    print -- ${argv[-1]} >> "$BARNYARD_TEST_GPG_TRUSTS"
elif [[ " $* " = *' --show-keys '* ]]; then
    typeset key=$(mktemp "$BARNYARD_TEST_GPG_SCRATCH/key.XXXXXX") || exit
    cat > "$key"
    "$BARNYARD_REAL_GPG" --homedir "$BARNYARD_TEST_GPG_HOME" \
        --batch --with-colons --show-keys "$key"
    typeset result=$?
    rm -f "$key"
    exit $result
elif [[ " $* " = *' --fingerprint '* && " $* " = *' --list-keys '* ]]; then
    print 'fpr:::::::::968479A1AFF927E37D1A566BB5690EEEBB952194:'
    exit 0
elif [[ " $* " = *' --list-keys '* ]]; then
    exit 0
else
    exit 64
fi
EOF
    chmod 755 $tmp/bin/gpg

    typeset known=$tmp/github-known-hosts private_key=$tmp/id_barnyard
    print -r -- 'github.com ssh-ed25519 TEST' > $known
    print -r -- 'PRIVATE KEY CONTENT MUST NOT REACH ARGV' > $private_key

    BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
        $barnyard control bootstrap \
            --destination operator@bench.invalid \
            --known $known \
            --ssh $private_key \
            --gpg $fixture --gpg $fixture \
            --fingerprint 5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23 \
            --fingerprint 968479A1AFF927E37D1A566BB5690EEEBB952194 \
            --repository git@github.com:example/barnyard-configuration.git \
            --branch production

    typeset payload=$(<$tmp/capture/stdin)
    jq -e --arg known "$(<$known)" --arg key "$(<$private_key)" \
        --arg gpg "$(<$fixture)" '
        . == {
            "version": "0.26.0",
            "ssh": { "known_hosts": $known, "private_key": $key },
            "gpg": {
                "import": [ $gpg, $gpg ],
                "trust": [
                    "5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23",
                    "968479A1AFF927E37D1A566BB5690EEEBB952194"
                ]
            },
            "repository": {
                "url": "git@github.com:example/barnyard-configuration.git",
                "branch": "production"
            },
            "expect": { "hostname": "bench.invalid", "distribution": "ubuntu" }
        }
    ' <<< $payload > /dev/null
    assert 'control sends one bootstrap payload' "${$(wc -l < $tmp/capture/calls)// /}" 1
    assert 'control requires strict host checking' "$(<$tmp/capture/ssh-argv)" \
        '*StrictHostKeyChecking=yes*operator@bench.invalid*/usr/bin/sudo -n /usr/local/bin/barnyard agent bootstrap*'
    assert_not 'private key is absent from SSH argv' "$(<$tmp/capture/ssh-argv)" '*PRIVATE KEY CONTENT*'
    assert_not 'private key is absent from jo argv' "$(<$tmp/capture/jo-argv)" '*PRIVATE KEY CONTENT*'
    assert 'jo receives the private-key path' "$(<$tmp/capture/jo-argv)" "*ssh.private_key=@$private_key*"

    rm -f $tmp/capture/calls $tmp/capture/stdin
    BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
        $barnyard control bootstrap \
            --destination operator@bench.invalid \
            --gpg $fixture
    typeset partial=$(<$tmp/capture/stdin)
    jq -e --arg gpg "$(<$fixture)" '
        . == {
            "version": "0.26.0",
            "gpg": { "import": [ $gpg ] },
            "expect": { "hostname": "bench.invalid", "distribution": "ubuntu" }
        }
    ' <<< $partial > /dev/null
    assert 'control sends a one-property payload' "${$(wc -l < $tmp/capture/calls)// /}" 1
    typeset partial_out=$(probe_receiver "$partial")
    assert 'one GPG key imports by itself' "$partial_out" '*APPLY_gpg-import*RECEIVER_STATUS=0*'
    assert_not 'GPG-only payload skips SSH' "$partial_out" '*APPLY_known-hosts*'
    assert_not 'GPG-only payload skips trust' "$partial_out" '*APPLY_gpg-trust*'
    assert_not 'GPG-only payload skips clone' "$partial_out" '*APPLY_clone*'

    BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
        $barnyard control bootstrap \
            --destination operator@bench.invalid \
            --known $known \
            --fingerprint 968479A1AFF927E37D1A566BB5690EEEBB952194
    partial=$(<$tmp/capture/stdin)
    partial_out=$(probe_receiver "$partial")
    assert 'known_hosts and existing trust form a valid subset' "$partial_out" \
        '*APPLY_known-hosts*APPLY_gpg-trust:968479A1AFF927E37D1A566BB5690EEEBB952194*RECEIVER_STATUS=0*'
    assert_not 'known-and-trust subset skips private key' "$partial_out" '*APPLY_private-key*'
    assert_not 'known-and-trust subset skips import' "$partial_out" '*APPLY_gpg-import*'
    assert_not 'known-and-trust subset skips clone' "$partial_out" '*APPLY_clone*'

    BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
        $barnyard control bootstrap \
            --destination operator@bench.invalid \
            --repository git@github.com:example/barnyard-configuration.git \
            --branch production
    partial=$(<$tmp/capture/stdin)
    partial_out=$(probe_receiver "$partial")
    assert 'repository converges by itself' "$partial_out" \
        '*APPLY_clone:git@github.com:example/barnyard-configuration.git#production*RECEIVER_STATUS=0*'
    assert_not 'repository-only payload skips SSH' "$partial_out" '*APPLY_known-hosts*'
    assert_not 'repository-only payload skips GPG' "$partial_out" '*APPLY_gpg-import*'

    typeset no_op_out no_op_status
    no_op_out=$(
        BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
            $barnyard control bootstrap --destination operator@bench.invalid 2>&1
    ) && no_op_status=0 || no_op_status=$?
    assert_not 'control rejects a no-op payload' $no_op_status 0
    assert 'control names the no-op' "$no_op_out" '*nothing to bootstrap*'

    no_op_out=$(
        BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
            $barnyard control bootstrap --destination operator@bench.invalid \
                --repository git@example.invalid:repo 2>&1
    ) && no_op_status=0 || no_op_status=$?
    assert_not 'control rejects a repository half-pair' $no_op_status 0
    assert 'control requires branch with repository' "$no_op_out" '*branch is required*'

    typeset out=$(probe_receiver "$payload")
    assert 'receiver accepts the complete payload' "$out" '*RECEIVER_STATUS=0*'
    assert 'receiver applies in order' "$out" \
        '*APPLY_known-hosts*APPLY_private-key*APPLY_gpg-import*APPLY_gpg-import*APPLY_gpg-trust:5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23*APPLY_gpg-trust:968479A1AFF927E37D1A566BB5690EEEBB952194*APPLY_clone:git@github.com:example/barnyard-configuration.git#production*'
    assert 'receiver applies both GPG imports' "$(line_count "$out" APPLY_gpg-import)" 2
    assert 'receiver logs bootstrap completion' "$out" '*status=success*operation=bootstrap*'

    out=$(probe_receiver "$payload" fail-private)
    assert_not 'failed applier returns nonzero' "$out" '*RECEIVER_STATUS=0*'
    assert 'receiver reaches the failed private-key applier' "$out" '*APPLY_private-key*'
    assert_not 'receiver stops after the failed applier' "$out" '*APPLY_gpg-import*'

    typeset invalid=$(printf '%s' "$payload" | jq '.extra = true')
    out=$(probe_receiver "$invalid")
    assert_not 'unknown field is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'unknown field rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.ssh.extra = true')
    out=$(probe_receiver "$invalid")
    assert_not 'unknown nested field is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'unknown nested field rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.expect.hostname = "wrong.invalid"')
    out=$(probe_receiver "$invalid")
    assert_not 'wrong host is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'wrong host rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.expect.distribution = "wrong"')
    out=$(probe_receiver "$invalid")
    assert_not 'wrong distribution is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'wrong distribution rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.version = "9.9.9"')
    out=$(probe_receiver "$invalid")
    assert_not 'version mismatch is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'version mismatch rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.ssh.private_key = ""')
    out=$(probe_receiver "$invalid")
    assert_not 'empty private key is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'empty private key rejects before dispatch' "$out" '*APPLY_*'

    out=$(probe_receiver '{"version":')
    assert_not 'malformed JSON is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'malformed JSON rejects before dispatch' "$out" '*APPLY_*'

    out=$(probe_receiver '')
    assert_not 'empty payload is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'empty payload rejects before dispatch' "$out" '*APPLY_*'

    partial=$(jo -d. -- -s version=$barnyard_version \
        -s expect.hostname=bench.invalid -s expect.distribution=ubuntu \
        -s 'gpg.trust[]=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
    out=$(probe_receiver "$partial")
    assert_not 'trust without an available key is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'unavailable trust rejects before dispatch' "$out" '*APPLY_*'

    partial=$(jo -d. -- -s version=$barnyard_version \
        -s expect.hostname=bench.invalid -s expect.distribution=ubuntu)
    out=$(probe_receiver "$partial")
    assert_not 'receiver rejects a no-op payload' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'receiver no-op runs no applier' "$out" '*APPLY_*'

    partial=$(jo -d. -- -s version=$barnyard_version \
        -s expect.hostname=bench.invalid -s expect.distribution=ubuntu \
        -s repository.url=git@example.invalid:repo)
    out=$(probe_receiver "$partial")
    assert_not 'receiver rejects a repository half-pair' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'repository half-pair runs no applier' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.gpg.trust[0] = "DEADBEEF"')
    out=$(probe_receiver "$invalid")
    assert_not 'absent trust fingerprint is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'absent fingerprint rejects before dispatch' "$out" '*APPLY_*'

    invalid=$(printf '%s' "$payload" | jq '.gpg.import[0] = "not an OpenPGP key"')
    out=$(probe_receiver "$invalid")
    assert_not 'invalid OpenPGP data is rejected' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'invalid key rejects before dispatch' "$out" '*APPLY_*'

    mkdir -p $tmp/root/etc/barnyard $tmp/root/var/lib/barnyard $tmp/source
    chmod 700 $tmp/root/etc/barnyard
    rm -f $private_key
    ssh-keygen -q -t ed25519 -N '' -f $private_key
    git init -q -b main $tmp/source
    git -C $tmp/source -c user.name=Barnyard -c user.email=test@example.invalid \
        -c commit.gpgsign=false commit --allow-empty -qm initial

    BARNYARD_CAPTURE=$tmp/capture BARNYARD_REAL_JO=$real_jo PATH=$tmp/bin:$PATH \
        $barnyard control bootstrap \
            --destination operator@bench.invalid \
            --known $known \
            --ssh $private_key \
            --gpg $fixture --gpg $fixture \
            --fingerprint 5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23 \
            --fingerprint 968479A1AFF927E37D1A566BB5690EEEBB952194 \
            --repository $tmp/source \
            --branch main
    typeset real_payload=$(<$tmp/capture/stdin)
    out=$(run_real_receiver "$real_payload")
    assert 'real appliers complete through exemplar' "$out" '*RECEIVER_STATUS=0*'
    assert_not 'real appliers do not execute literal placeholders' "$out" '*%q*'
    assert_not 'real appliers retain transcript context' "$out" '*no job control*'
    assert 'known_hosts is installed' "$(<$tmp/root/etc/barnyard/known_hosts)" "$(<$known)"
    assert 'private key is installed' "$(<$tmp/root/etc/barnyard/id_barnyard)" "$(<$private_key)"
    assert 'two real GPG imports run' "${$(wc -l < $tmp/gpg-imports)// /}" 2
    assert 'two real GPG trusts run' "${$(wc -l < $tmp/gpg-trusts)// /}" 2
    assert 'first trust gets its fingerprint' "$(sed -n '1p' $tmp/gpg-trusts)" \
        5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23
    assert 'second trust gets its fingerprint' "$(sed -n '2p' $tmp/gpg-trusts)" \
        968479A1AFF927E37D1A566BB5690EEEBB952194
    assert 'clone installs a bare mirror' \
        "$(git -C $tmp/root/var/lib/barnyard/repository rev-parse --is-bare-repository)" true
    assert 'clone installs the branch file' "$(<$tmp/root/etc/barnyard/branch)" main

    typeset previous_head=$(git -C $tmp/root/var/lib/barnyard/repository rev-parse HEAD)
    invalid=$(printf '%s' "$real_payload" |
        jq --arg url "$tmp/does-not-exist" '.repository.url = $url')
    out=$(run_real_receiver "$invalid")
    assert_not 'failed replacement clone returns nonzero' "$out" '*RECEIVER_STATUS=0*'
    assert 'failed replacement preserves the previous mirror' \
        "$(git -C $tmp/root/var/lib/barnyard/repository rev-parse HEAD)" "$previous_head"

    print
    if (( failures )); then
        print -u 2 "bootstrap: $failures failure(s)"
        exit 1
    fi
    print 'bootstrap: all tests passed'
} always {
    [[ -d $tmp ]] && rm -rf $tmp
}
