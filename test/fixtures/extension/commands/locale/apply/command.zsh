function :help:locale:apply {
    help=$(<${functions_source[:help:locale:apply]:A:h}/help.md)
}

function :args:locale:apply {
    eval "$(args -bx h,help -- "$@")"
}

function :execute:locale:apply {
    function localize {
        typeset language
        () {
            language=$(jq -r '.language // "en_US.UTF-8"' "$BARNYARD_CONFIGURATION")
        }
        () { print $language }
        () { update-locale --reset LANG=$language }
        () { cat /etc/default/locale }
    }
    block 'locale'
    {
        exemplar localize
    } always {
        caught
    } > >(indent)
}
