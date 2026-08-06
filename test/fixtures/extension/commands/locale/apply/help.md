# desc
Set the system locale from the module configuration.
# opt help
Display help for `barnyard locale apply`.
# man
## DESCRIPTION
`barnyard locale apply` sets the machine's system locale to the configured
language with `update-locale`, defaulting to `en_US.UTF-8` when the module
sets none, then prints the resulting `/etc/default/locale`. The language is
taken from the module configuration on the apply envelope, never from argv.
## OPTIONS
> options
