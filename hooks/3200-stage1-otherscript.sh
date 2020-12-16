#!/bin/bash
set -e

if [ -z "${_STAGE1_OTHERSCRIPT}" ]; then
    _STAGE1_OTHERSCRIPT='stage1-otherscript.sh'
        echo_warn "Other script _STAGE1_OTHERSCRIPT is not set on config: Setting default value ${_STAGE1_OTHERSCRIPT}"
fi

_STAGE1_OTHERSCRIPT_PATH="${_OTHER_SCRIPTS_DIR}/${_STAGE1_OTHERSCRIPT}"

echo_debug "Checking if stage1 other script ${_STAGE1_OTHERSCRIPT_PATH} exists ..."
test -f "${_STAGE1_OTHERSCRIPT_PATH}" && {
    echo_debug "   ${_STAGE1_OTHERSCRIPT_PATH} found!"
    cp "${_STAGE1_OTHERSCRIPT_PATH}" "${_CHROOT_ROOT}/"
    chmod +x "${_CHROOT_ROOT}/${_STAGE1_OTHERSCRIPT}"
    echo_debug "## Script execution ############################################################"
    chroot ${_CHROOT_ROOT} /bin/bash -c "/root/${_STAGE1_OTHERSCRIPT}"
    echo_debug "## End of Script execution #####################################################"
    rm "${_CHROOT_ROOT}/${_STAGE1_OTHERSCRIPT}"
} || {
    echo_debug "    SKIPPING: Optional stage1 other script was not found (and will not be executed)."
}
