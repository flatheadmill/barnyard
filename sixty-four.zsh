#!/usr/bin/env zsh

# Sketch of formatting a little-endian 64-bit number.

function sixty_four {
    typeset number=${1:-} count=8
    while (( number )); do
        printf '\x'"$( printf '%X' "$(( number & 16#FF ))" )"
        number=$(( number >> 8 ))
        (( count-- ))
    done
    while (( count )); do
        printf '\x00'
        (( count-- ))
    done
}

function main {
    typeset foo=$(sixty_four $(( 16#ff_12_aa_0a )))
    printf '%s' "$foo" | hexdump -C
}

main "$@"
