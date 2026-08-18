function :help:locale {
    help=$(<${functions_source[:help:locale]:A:h}/help.md)
}

function :args:locale {
    eval "$(args -UC -bx h,help -- "$@")"
}

function :execute:locale {
    delegate "$@"
}
