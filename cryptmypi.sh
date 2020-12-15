#!/bin/bash
set -e

# SET ENVIRONMENT VARIABLES
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export _BASEDIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export _CURRDIR=$(pwd)
export _CONFDIRNAME="${1}"
export _CONFDIR=${_CURRDIR}/${_CONFDIRNAME}
export _USER_HOME=$(eval echo ~${SUDO_USER})
export _SHAREDCONFDIR=${_CURRDIR}/shared-config
export _BUILDDIR=${_CONFDIR}/build
export _FILESDIR=${_BASEDIR}/files
export _IMAGEDIR=${_FILESDIR}/images
export _CACHEDIR=${_FILESDIR}/cache
export _ENCRYPTED_VOLUME_NAME="crypt-1"
#0 = debug messages, 1+ = info, no debug messages 2+ = warnings 3+ = only errors
export _LOG_LEVEL=1
# Load configuration files
. ${_CONFDIR}/cryptmypi.conf
. ${_CURRDIR}/shared-config/shared-cryptmypi.conf
# Configuration dependent variables
export _IMAGENAME=$(basename ${_IMAGEURL})

# Default input variable values
_OUTPUT_TO_FILE=""
_STAGE1_CONFIRM=true
_STAGE2_CONFIRM=true
_BLKDEV_OVERRIDE=""
_SHOW_OPTIONS=false
_SIMULATE=false
_STAGE1_REBUILD=""
_RMBUILD_ONREBUILD=true

# Load Script Base Functions
for _FN in ${_BASEDIR}/functions/*.sh
do
    . ${_FN}
    echo_debug "- $(basename ${_FN}) loaded"
done

# Message on exit
exitMessage(){
    if [ $1 -gt 0 ]; then
        echo_error "Script failed at `date` with exit status $1 at line $2"
    else
        echo_info "Script completed at `date`"
    fi
}
# Cleanup on exit
cleanup(){
    chroot_umount || true
    umount ${_BLKDEV}* || true
    umount /mnt/cryptmypi || {
        umount -l /mnt/cryptmypi || true
        umount -f /dev/mapper/${_ENCRYPTED_VOLUME_NAME} || true
    }
    [ -d /mnt/cryptmypi ] && rm -r /mnt/cryptmypi || true
    cryptsetup luksClose $_ENCRYPTED_VOLUME_NAME || true
}

# EXIT Trap
trapExit () { exitMessage $1 $2 ; cleanup; }
trap 'trapExit $? $LINENO' EXIT

############################
# Validate All Preconditions
############################
stagePreconditions(){
    echo_info "$FUNCNAME started at `date` "

    # Creating Directories
    mkdir -p "${_IMAGEDIR}"
    mkdir -p "${_FILESDIR}"
    mkdir -p "${_BUILDDIR}"

    # Check if configuration name was provided
    if [  -z "$_CONFDIRNAME" ]; then
        echo_error "ERROR: Configuration directory was not supplied. "
        display_help
        exit 1
    fi

    # Check if configuration file is present
    if [ ! -f ${_CONFDIR}/cryptmypi.conf ]; then
        echo_error "ERROR: Cannot find ${_CONFDIR}/cryptmypi.conf"
        exit 1
    fi

    # Overriding _BLKDEV if _BLKDEV_OVERRIDE set
    [ -z "${_BLKDEV_OVERRIDE}" ] || _BLKDEV=${_BLKDEV_OVERRIDE}

    myhooks preconditions
}
############################
# STAGE 1 Image Preparation
############################
stage1(){
    echo_info "$FUNCNAME started at `date` "
    function_exists "stage1_hooks" && {
        function_summary stage1_hooks
        stage1_hooks
    }
}

############################
# STAGE 2 Encrypt & Write SD
############################
stage2(){
    echo_info "$FUNCNAME started at `date` "
    # Simple check for type of sdcard block device
    if echo ${_BLKDEV} | grep -qs "mmcblk"
    then
        __PARTITIONPREFIX=p
    else
        __PARTITIONPREFIX=""
    fi

    # Show Stage2 menu
    local _CONTINUE
    $_STAGE2_CONFIRM && {

    echo_warn "Cryptmypi will now write the build to disk."
    echo_warn "WARNING: CHECK DISK IS CORRECT"
    echo_info "$(lsblk)"
    echo_info "Type 'YES' if the selected device is correct:  ${_BLKDEV}"
    echo -n ": "
        read _CONTINUE
    } || {
        echo_debug "STAGE2 confirmation set to FALSE: skipping confirmation"
        echo_debug "STAGE2 will execute (assuming 'YES' input) ..."
        _CONTINUE='YES'
    }

    case "${_CONTINUE}" in
        'YES')
            function_exists "stage2_hooks" && {
                function_summary stage2_hooks
                stage2_hooks
            } || myhooks "stage2"
            ;;
        *)
            echo "Abort."
            exit 1
            ;;
    esac
}

############################
# EXECUTION LOGIC FLOW
############################
# Logic execution routine
execute(){
    stagePreconditions
    cd ${_BUILDDIR}
    case "$1" in
        'both')
            echo_info "# Executing both stages "
            stage1
            stage2
            ;;
        'stage2')
            echo_info "# Executing stage2 only "
            stage2
            ;;
        *)
            ;;
    esac
}

# Main logic routine
main(){
    echo_info "Starting Cryptmypi at $(date)"
    if [ ! -d ${_BUILDDIR} ]; then
        execute "both"
    else
        echo "Build directory already exists: ${_BUILDDIR}"

        local _CONTINUE
        while true
        do
            $_STAGE1_CONFIRM && {
                echo_info "Rebuild? (y/N)"
                read _CONTINUE
                _CONTINUE=`echo "${_CONTINUE}" | sed -e 's/\(.*\)/\L\1/'`
            } || {
                echo_debug "STAGE1 confirmation set to FALSE: skipping confirmation"
                $_STAGE1_REBUILD && {
                    echo_debug "Default set as REBUILD. STAGE1 will be rebuilt "
                    _CONTINUE='y'
                } || {
                    echo_debug "Default set as SKIP REBUILD. Skipping STAGE1 "
                    _CONTINUE='n'
                }
            }

            case "${_CONTINUE}" in
                'y')
                    $_RMBUILD_ONREBUILD && {
                        echo_debug "Removing current build files." #TESTING ONLY
                        $_SIMULATE || rm -Rf ${_BUILDDIR} 
                    } || echo_warn "--keep_build_dir set: Not cleaning old build."                    
                    execute "both"
                    break;
                    ;;
                'n') 
                    execute "stage2"
                    break;
                    ;;
                *)
                    echo "Invalid input."
                    ;;
            esac
        done
    fi
}
main

exit 0
