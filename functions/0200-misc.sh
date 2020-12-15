#!/bin/bash
function_exists(){
    declare -f -F $1 > /dev/null
    return $?
}

function_summary(){
    type $1 | sed '1,3d;$d'
}
