#!/bin/bash
# shellcheck disable=SC1091
set -eu

# Unmounts image file

# Load functions, environment variables and dependencies
. functions.sh;
. env.sh;
. options.sh;
. dependencies.sh;

#Program logic
main(){
  echo_info "$(basename $0) started";
  cleanup
}

# Run program
main;
