#!/bin/bash
set -e
# Create a configurable kali pi build

# Load functions and environment variables and dependencies
. env.sh;
. functions.sh;
. dependencies.sh;

#Program logic
execute()
{
    check_preconditions;
    install_dependencies;
    prepare_image;
    write_to_disk;
}

# Run Program
main(){
    echo_info "starting $(basename $0) at $(date)";
    log_file='build-'$(date '+%Y-%m-%d-%H:%M:%S')'.log'
    execute | tee "${_BUILDDIR}"/"${log_file}" || true
    echo_info "starting $(basename $0) at $(date)";
}
main;
