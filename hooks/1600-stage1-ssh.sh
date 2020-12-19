#!/bin/bash
set -eu

ssh_setup(){
  echo_info "$FUNCNAME[0] started at $(date) ";
  sshd_config="${_CHROOT_ROOT}/etc/ssh/sshd_config"
  ssh_authorized_keys="${_CHROOT_ROOT}/.ssh/authorized_keys"

  test -f "${_SSH_LOCAL_KEYFILE}" || {
      echo_error "ERROR: Obligatory SSH keyfile '${_SSH_LOCAL_KEYFILE}' could not be found. "
      exit 1
  }

  # Append our key to the default user's authorized_keys file
  echo_debug "Creating authorized_keys file"
  mkdir -p "${_CHROOT_ROOT}/.ssh/"
  cat "${_SSH_LOCAL_KEYFILE}.pub" > "${ssh_authorized_keys}"
  chmod 600 "${ssh_authorized_keys}"

  # Creating box's default user own key
  assure_box_sshkey "${_HOSTNAME}"

  # Update sshd settings
  cp -p "${sshd_config}" "${sshd_config}.bak"

  cat << EOF >> "${sshd_config}"
  PasswordAuthentication $(_SSH_PASSWORD_AUTHENTICATION)
  Port 2222
  ChallengeResponseAuthentication no
  PubkeyAuthentication yes
  AuthorizedKeysFile .ssh/authorized_keys
EOF

}
ssh_setup;
