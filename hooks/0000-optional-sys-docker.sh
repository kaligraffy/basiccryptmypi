#!/bin/bash
set -eu

# REFERENCES
#   https://www.docker.com/blog/happy-pi-day-docker-raspberry-pi/
#   https://github.com/docker/docker.github.io/blob/595616145a53d68fb5be1d603e97666cefcb5293/install/linux/docker-ce/debian.md
#   https://docs.docker.com/engine/install/debian/
#   https://gist.github.com/decidedlygray/1288c0265457e5f2426d4c3b768dfcef

echo_debug "Attempting to install docker "
echo_warn "### Docker service may experience conflicts VPN services/connections ###"

echo_debug "    Updating /boot/cmdline.txt to enable cgroup "
# Needed to avoid "cgroups: memory cgroup not supported on this system"
#   see https://github.com/moby/moby/issues/35587
#       cgroup_enable works on kernel 4.9 upwards
#       cgroup_memory will be dropped in 4.14, but works on < 4.9
#       keeping both for now
sed -i "s#rootwait#cgroup_enable=memory cgroup_memory=1 rootwait#g" ${_CHROOT_ROOT}/boot/cmdline.txt

echo_debug "    Updating iptables  (issue: default kali iptables was stalling)"
# systemctl start and stop commands would hang/stall due to pristine iptables on kali-linux-2020.1a-rpi3-nexmon-64.img.xz
chroot_package_install "$_CHROOT_ROOT" iptables
chroot_execute "$_CHROOT_ROOT" update-alternatives --set iptables /usr/sbin/iptables-legacy
chroot_execute "$_CHROOT_ROOT" update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

echo_debug "    Installing docker "
chroot_package_install "$_CHROOT_ROOT" docker.io

echo_debug "    Enabling service "
chroot_execute "$_CHROOT_ROOT" systemctl enable docker
# chroot_execute systemctl start docker
echo_debug " docker hook call completed"
