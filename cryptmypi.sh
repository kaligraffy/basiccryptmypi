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
  dependencies;
  check_preconditions;   
  prepare_image;
  write_to_disk;
}

# Run Program
main(){
    echo_info "starting $(basename $0) at $(date)";
    execute | tee ${_BUILDDIR}/build.log;
    echo_info "starting $(basename $0) at $(date)";
}
main;
