function_exists(){
    declare -f -F $1 > /dev/null
    return $?
}

function_summary(){
    type $1 | sed '1,3d;$d'
}

############################
# Parameter helper functions
############################
# Displays help
display_help(){
    cat << EOF

PURPOSE: Creates encrypted raspberry pis running kali linux
    
USAGE: $0 [OPTIONS] configuration_dir

EXAMPLE:
    $0 --device /dev/sda /examples/kali-complete 
    - Executes script using examples/kali-complete/cryptmypi.conf
    - using /dev/sdb as destination block device
    
OPTIONS:

    -d, --device <device>       Block device to use on stage 2
                                (overrides _BLKDEV configuration)

    --force-stage1, --rebuild   Overrides previous builds without confirmation
    --force-stage2              Writes to block device without confirmation
    --force-both-stages         Executes stage 1 and 2 without confirmation
    --skip-stage1, --no-rebuild Skips stage 1 (if a previous build exists)

    -s, --simulate              Simulate execution flow (does not call hooks)
    --keep_build_dir            When rebuilding stage 1, use last build as base
                                (default cleans up removing old build)
    -h, --help                  Display this help and exit
    -o,--output <file>          Redirects stdout and stderr to <file>

EOF
}
