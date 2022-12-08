Using the `zsh_parse_arguments`.

Boolean flags where `h` is the short argument and `help` is the long argument.

```
function f {
    eval "$(zsh_parse_arguments h,help "$@")"
    print $o_help
}

f -h
f --help
```

A toggle with just a long argument. See below for creating short argument
toggles.

```
function f {
    eval "$(zsh_parse_arguments ,frobinate! "$@")"
    print $o_frobinate
}

f --frobinate
f --no-frobinate
```

A count argument.

```
function f {
    eval "$(zsh_parse_arguments c,count# "$@")"
    print $o_frobinate
}

f -c -c -c
f -ccc
f --count -c --count
```

A parameterized scalar argument.

```
function f {
    eval "$(zsh_parse_arguments v,value: "$@")"
    print $o_frobinate
}

f -v value
f -vvalue
f --value value
f --value=value
f --value=value --value=overwriten
```

A parameterized array argument.

```
function f {
    eval "$(zsh_parse_arguments v,value: "$@")"
    printf "%d (%s)" ${#value[@]} "${value[@]}"
}

f -vvalue -v value --value value --value=value
```

Just a short argument.

```
function f {
    eval "$(zsh_parse_arguments v,: "$@")"
    print $o_frobinate

}

f -vvalue
```

Just a long argument.

```
function f {
    eval "$(zsh_parse_arguments ,help "$@")"
    print $o_frobinate

}

f --help
```

Assigning a default value.

TODO Could do `v,values@=1 ,values=2 v,=3`.

```
function f {
    eval "$(zsh_parse_arguments v,value:=default n,negate:=0 c,count#=3 "$@")"
    print $o_value $o_negate $o_count

}

f
```

Creating a short toggle with an extra flag.

```
function f {
    eval "$(zsh_parse_arguments frobinate=F,frobinate! frobinate=f,: "$@")"
    print $frobinate
}

f -F
f --no-frobinate
f --frobinate
f -f
```
