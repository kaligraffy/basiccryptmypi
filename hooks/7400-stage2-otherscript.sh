#!/bin/bash
set -e



if [ -z "${_STAGE2_OTHERSCRIPT}" ]; then
    _STAGE2_OTHERSCRIPT='stage2-otherscript.sh'
        echo_warn "Other script _STAGE2_OTHERSCRIPT is not set on config: Setting default value ${_STAGE2_OTHERSCRIPT}"
fi


_STAGE2_OTHERSCRIPT_PATH="${_OTHER_SCRIPTS_DIR}/${_STAGE2_OTHERSCRIPT}"


echo_debug "Checking if stage2 other script ${_STAGE2_OTHERSCRIPT_PATH} exists ..."
test -f "${_STAGE2_OTHERSCRIPT_PATH}" && {
    echo_debug "   ${_STAGE2_OTHERSCRIPT_PATH} found!"
    cp "${_STAGE2_OTHERSCRIPT_PATH}" "${_CHROOT_ROOT}/"
    chmod +x "${_CHROOT_ROOT}/${_STAGE2_OTHERSCRIPT}"
    echo_debug "## Script execution ############################################################"
    chroot ${_CHROOT_ROOT} /bin/bash -c "/root/${_STAGE2_OTHERSCRIPT}"
    echo_debug "## End of Script execution #####################################################"
    rm "${_CHROOT_ROOT}/${_STAGE2_OTHERSCRIPT}"
} || {
    echo_debug "    SKIPPING: Optional stage2 other script was not found (and will not be executed)."
}
