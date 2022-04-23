yq -o=json '.' < development.yaml | jq  -r '
    [
        .machines | to_entries[] | .key as $machine | .value | to_entries as $a | $a | keys[] |
            $machine, ., $a[.].key,
                ($a[.].value | to_entries as $b | ($b | length), ($b[] | .key, (
                  .value as $v | ($v | if type == "array" then ($v | length), $v else (0, $v) end)
                  )))
    ] | flatten | @sh
'
