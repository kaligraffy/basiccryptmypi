#!/bin/bash
set -eu

# shellcheck disable=2155
declare -r _start_time="$(date +%s)";

# shellcheck disable=2155
declare -r _base_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";

#can be overridden in env.sh
declare _build_dir="${_build_dir:-"${_base_dir}/build"}"
declare _chroot_dir="${_chroot_dir:-"${_base_dir}/disk"}"; #shouldn't be set to build dir
declare _image_file="${_image_file:-"${_build_dir}/image.img"}";

declare _apt_cmd=${_apt_cmd:-"eatmydata apt-get -qq -y"};
declare _apt_https="${_apt_https:-0}";
declare _64bit="${_64bit:-0}";
declare _log_level="${_log_level:-"INFO"}";
declare _encrypted_volume_path=${_encrypted_volume_path:-"/dev/mapper/crypt"}; #set this to something else in your env file if you already have something called crypt on your system
declare _log_file="${_log_file:-"${_base_dir}/build.log"}";
declare _image_file_size_modifier=${_image_file_size_modifier:-"1.1"}; #amount to multiply the existing image (when making the system image) by, i.e 1.1 is 1.1 x the downloaded image size. 
declare _extra_packages=${_extra_packages:-""};
declare _no_prompts=${_no_prompts:-0}
#Don't change
declare _block_device_boot="";
declare _block_device_root="";

# shellcheck disable=2155
declare _luks_mapping_name="$(basename "${_encrypted_volume_path}")";

# Runs on script exit, tidies up the mounts.
trap_on_exit(){
  print_function_name;
  local end_time;
  end_time="$(($(date +%s)-_start_time))"
  
  #trap arg $2 is only set to 0 when the script might need to clean up the mounts, see usage in main()
  if (( $2 == 0 )); then
    cleanup;
  fi
  
  #trap arg 1 is only set to 0 to signify the script has successfully ran, see main()
  if (( $1 == 1 )); then 
    print_info "$(basename "$0") failed. Script took ${end_time} seconds";
  else
    print_info "$(basename "$0") finished successfully. Script took ${end_time} seconds";
  fi
}

# Attempt to clean up the mounts
cleanup(){
  print_function_name;
  tidy_umount "${_build_dir}/mount" || true
  tidy_umount "${_build_dir}/boot" || true

  chroot_teardown || true 
  tidy_umount "${_block_device_boot}" || true 
  tidy_umount "${_block_device_root}" || true 
  tidy_umount "${_chroot_dir}" || true 
  if [ -b "${_encrypted_volume_path}" ]; then
    cryptsetup -v luksClose "${_luks_mapping_name}" || true
    cryptsetup -v remove "${_luks_mapping_name}" || true
  fi
  cleanup_loop_devices || true     
}

# Auxiliary method for detaching loop_device in cleanup method 
cleanup_loop_devices(){
  print_function_name;
  loop_devices="$(losetup -a | cut -d':' -f 1 | tr '\n' ' ')";
  if check_variable_is_set "$loop_devices" ; then
    for loop_device in $loop_devices; do
      if losetup -l "${loop_device}p1" &> /dev/null ; then print_debug "loop device, detach it"; losetup -d "${loop_device}p1"; fi
      if losetup -l "${loop_device}p2" &> /dev/null; then print_debug "loop device, detach it"; losetup -d "${loop_device}p2"; fi
      if losetup -l "${loop_device}" &> /dev/null ; then print_debug "loop device, detach it"; losetup -d "${loop_device}"; fi
    done
  fi
}

# Checks if script was run as root
check_run_as_root(){
  print_function_name;
  if (( EUID != 0 )); then
    print_error "This script must be run as root/sudo. For usage call sudo ./cryptmypi ";
    exit 1;
  fi
}

# Installs packages on build pc
install_dependencies() {
  print_function_name;

  apt-get -qq -y install \
        binfmt-support \
        qemu-user-static \
        coreutils \
        parted \
        zip \
        grep \
        rsync \
        xz-utils \
        btrfs-progs \
        eatmydata \
        pv ;
}

# Sets the defaults
# the actual unmounting is performed in the clean up trap which is called on script exit
unmount(){
  print_function_name;
  set_defaults > /dev/null; #output suppressed if just unmounting
}

#mounts the disk, so you can manually chroot into the disk
#useful for troubleshooting sometimes
mount_only(){
  print_function_name;
  set_defaults > /dev/null; #output suppressed if just unmounting
  if (( _image_mode == 1 )); then 
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
  fi
  echo "${_luks_password}" | cryptsetup -v luksOpen "${_block_device_root}" "${_luks_mapping_name}"
  mount_chroot;
    
  # probably don't want make the chroot binds if there is nothing in your filesystem so, check for an arbitrary folder that was copied over in your chroot directory
  if [ -d "${_chroot_dir}/dev" ]; then
    chroot_setup;
  fi
}

# Mount and call mkinitramfs inside the chroot directory
make_initramfs(){
  print_function_name;
  mount_only;
  chroot_mkinitramfs_setup;
}

# build the image or write it to disk
build(){
  print_function_name;
  install_dependencies;
  set_defaults;
  download_image;
  extract_image;
  # Check for a build directory
  create_build_directory
  # Write to physical disk or image and modify it
  if (( _image_mode == 1 )); then 
    partition_image_file;
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
    partition_disk;
  fi
  format_filesystem;
  mount_chroot;
  btrfs_setup
  copy_image_on_loopback_to_disk;
  chroot_all_setup;
  print_dd_command;
}

# Fix for using mmcblk0pX devices, adds a p used later on
fix_block_device_names(){
  # check device exists/folder exists
  print_function_name;
  
  if ! check_variable_is_set "${_output_block_device}"; then
    exit 1;
  fi

  local prefix=""
  #if the device contains mmcblk, prefix is set so the device name is picked up correctly
  if [[ "${_output_block_device}" == *'mmcblk'* ]]; then
    prefix='p'
  fi
  #Set the proper name of the output block device's partitions
  #e.g /dev/sda1 /dev/sda2 etc.
  _block_device_boot="${_output_block_device}${prefix}1"
  _block_device_root="${_output_block_device}${prefix}2"
}

# Create the build directory
create_build_directory(){
  if [ -d "${_build_dir}" ]; then
    local prompt="Build directory ${_build_dir} already exists. Recreate it? (y/N)  ";
    if [ -z "$(ls -A "${_build_dir}")" ] || ask_yes_or_no "$prompt" || (( _no_prompts == 1 )) ; then  
      rm -rf "${_build_dir}" ;
      mkdir "${_build_dir}" ; 
    else
      print_info "Not rebuilding"
      exit 1;
    fi
  else
    mkdir "${_build_dir}"; 
  fi
  sync;
}

# Extracts the image so it can be mounted
extract_image() {
  print_function_name;

  local image_name;
  local image_path;
  # shellcheck disable=2155
  image_name="$(basename "${_image_url}")";
  # shellcheck disable=2155
  image_path="${_base_dir}/${image_name}";
  # shellcheck disable=2155
  local extracted_image="${_base_dir}/$(basename ${_image_url} | sed 's#.xz##' | sed 's#.zip##')";

  #If no prompts is set and extracted image exists then continue to extract
  if [[ -e "${extracted_image}" ]] && (( _no_prompts == 1 )); then
    return 0;
  fi  
    
  if [[ -e "${extracted_image}" ]] ; then
    local prompt="${extracted_image} found, re-extract? (y/N)  "
    if ! ask_yes_or_no "$prompt"; then
       return 0;
    fi
  fi
  
  if check_variable_is_set "${_image_sha256}" ; then
      if ! echo "${_image_sha256}"  "$image_path" | sha256sum --check --status; then
        print_error "invalid checksum";
        exit 1;
      fi
      print_info "valid checksum";
  fi

  print_info "starting extract";
  #If theres a problem extracting, delete the partially extracted file and exit
  trap 'rm $(echo $extracted_image); exit 1' ERR SIGINT;
  case ${image_path} in
    *.xz)
        print_info "extracting with xz";
        pv "${image_path}" | xz --decompress --stdout > "$extracted_image";
        ;;
    *.zip)
        print_info "extracting with unzip";
        unzip -p "$image_path" > "$extracted_image";
        ;;
    *)
        print_error "unknown extension type on image: $image_path";
        exit 1;
        ;;
  esac
  trap - ERR SIGINT;
  print_info "finished extract";
}

# Mounts the extracted image via losetup
copy_image_on_loopback_to_disk(){
  print_function_name;
  # shellcheck disable=2155
  local extracted_image="${_base_dir}/$(basename ${_image_url} | sed 's#.xz##' | sed 's#.zip##')";
  local loop_device;
  
  loop_device=$(losetup -P -f --read-only --show "$extracted_image");
  partprobe "${loop_device}";
  check_directory_and_mount "${loop_device}p2" "${_build_dir}/mount";
  check_directory_and_mount "${loop_device}p1" "${_build_dir}/boot";

  rsync_local "${_build_dir}/boot" "${_chroot_dir}/"
  rsync_local "${_build_dir}/mount/"* "${_chroot_dir}"
}

# Check disk is correct before writing
#if no prompts is set, it skips the check
check_disk_is_correct(){
  print_function_name;
  if [ ! -b "${_output_block_device}" ]; then
    print_error "${_output_block_device} is not a block device" 
    exit 0
  fi
  
  if (( _no_prompts == 0 )); then
    local prompt="Device is ${_output_block_device}? (y/N) "
    print_info "$(lsblk)";
    print_warning "CHECK THE DISK IS CORRECT";

    if ! ask_yes_or_no "$prompt" ; then
        exit 0
    fi
  fi
  
 check_device_mounted ${_block_device_boot}
 check_device_mounted ${_block_device_root}
}

# Download an image file to the file directory
download_image(){
  print_function_name;

  local image_name;
  local image_out_file;

  image_name=$(basename "${_image_url}");
  image_out_file="${_base_dir}/${image_name}"
  
  wget -nc "${_image_url}" -O "${image_out_file}" || true
  
}

# Sets the locale (e.g. en_US, en_UK)
locale_setup(){
  print_function_name;
  
  chroot_package_install locales
  
  print_debug "Uncommenting locale ${_locale} for inclusion in generation"
  sed -i "s/^# *\(${_locale}\)/\1/" "${_chroot_dir}/etc/locale.gen";
  
  #REMOVE ANY LANG,LANGUAGE,LC_ALL configuration in the locale file, before adding in our locale
  sed -i 's/^\(LANG=.*\)/#\1/g' "${_chroot_dir}/etc/default/locale";
  sed -i 's/^\(LANGUAGE=.*\)/#\1/g' "${_chroot_dir}/etc/default/locale";
  sed -i 's/^\(LC_ALL.*\)/#\1/g' "${_chroot_dir}/etc/default/locale";
  
  print_debug "Updating /etc/default/locale";
  atomic_append "LANG=${_locale}" "${_chroot_dir}/etc/default/locale";
  atomic_append "LANGUAGE=${_locale}"  "${_chroot_dir}/etc/default/locale"
  atomic_append "LC_ALL=${_locale}"  "${_chroot_dir}/etc/default/locale"

  print_debug "Updating env variables";
  chroot "${_chroot_dir}" /bin/bash -x <<- EOT
export LANG="${_locale}";
export LANGUAGE="${_locale}";
export LC_ALL="${_locale}"
locale-gen
EOT

}

# Sets up encryption settings in chroot
encryption_setup(){
  print_function_name;
  local fs_type
  fs_type=${_filesystem_type};
  chroot_package_install cryptsetup busybox

  # Creating symbolic link to e2fsck
  #TODO This may not be needed
  chroot "${_chroot_dir}" /bin/bash -c "test -L /sbin/fsck.luks || ln -s /sbin/e2fsck /sbin/fsck.luks"

  # Indicate kernel to use initramfs - facilitates loading drivers
  sed -i 's|^initramfs.*|\#&|g' "${_chroot_dir}/boot/config.txt";
  atomic_append 'initramfs initramfs.gz followkernel' "${_chroot_dir}/boot/config.txt";
  
  # Update /boot/cmdline.txt to boot crypt
  sed -i "s|root=.* |root=${_encrypted_volume_path} cryptdevice=/dev/mmcblk0p2:${_luks_mapping_name} |g" "${_chroot_dir}/boot/cmdline.txt"
  sed -i "s|rootfstype=.* |rootfstype=${fs_type} |g" "${_chroot_dir}/boot/cmdline.txt"
  
  #disable init script for pios
  sed -i "s|init=.* | |g" "${_chroot_dir}/boot/cmdline.txt"

  #force 64bit if set
  if (( _64bit == 1 )); then
    print_info 'Set 64bit mode'
    atomic_append 'arm_64bit=1' "${_chroot_dir}/boot/config.txt";
  fi
  
  # Enable cryptsetup when building initramfs
  atomic_append 'CRYPTSETUP=y' "${_chroot_dir}/etc/cryptsetup-initramfs/conf-hook"  
  
  # Setup /etc/fstab
    case $fs_type in
    "btrfs")   
cat << EOF > "${_chroot_dir}/etc/fstab"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
${_encrypted_volume_path}  /            $fs_type    defaults,noatime,subvol=@/root  0  1
#Example config you may like to use:
#${_encrypted_volume_path}  /.snapshots  $fs_type    defaults,noatime,subvol=@/.snapshots  0  1    
#${_encrypted_volume_path}  /var/log     $fs_type    defaults,noatime,subvol=@/var_log  0  1    
#${_encrypted_volume_path}  /home        $fs_type    defaults,noatime,subvol=@/home  0  1
EOF
    ;;
    "ext4") 
cat << EOF > "${_chroot_dir}/etc/fstab"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
${_encrypted_volume_path}  /    $fs_type    defaults,noatime  0       1
EOF
    ;;
    *) print_error "filesystem not supported"
       exit 1
    ;;
  esac

  #Setup crypttab
  cat << EOF > "${_chroot_dir}/etc/crypttab"
#<target name> <source device>         <key file>      <options>
$(basename "${_encrypted_volume_path}")    /dev/mmcblk0p2    none    luks
EOF

  # Create a hook to include our crypttab in the initramfs
  cp -p "${_base_dir}/zz-cryptsetup" "${_chroot_dir}/etc/initramfs-tools/hooks/zz-cryptsetup";
  
  # Adding dm_mod, dm_crypt to initramfs modules
  #dm_mod needed for pios, oddly doesn't seem to be needed for kali 
  atomic_append 'dm_mod' "${_chroot_dir}/etc/initramfs-tools/modules";
  atomic_append 'dm_crypt' "${_chroot_dir}/etc/initramfs-tools/modules";
  
  # Disable autoresize
  chroot_execute 'systemctl disable rpi-resizerootfs.service'
  chroot_execute 'systemctl disable rpiwiggle.service'
}

# Encrypt & Write SD
partition_disk(){  
  print_function_name;
  parted_disk_setup "${_output_block_device}" 
}

# Makes an image file N * the size of the extracted image, then partitions the disk
partition_image_file(){
  print_function_name;
  local image_file=${_image_file};
  # shellcheck disable=2155
  local extracted_image="${_base_dir}/$(basename ${_image_url} | sed 's#.xz##' | sed 's#.zip##')";
  local extracted_image_file_size;
  local image_file_size;
  
  extracted_image_file_size="$(du -k "${extracted_image}" | cut -f1)"
  image_file_size="$(echo "${extracted_image_file_size} * ${_image_file_size_modifier}" | bc | cut -d'.' -f1)"; 
  touch "$image_file";
  fallocate -l "${image_file_size}KiB" "${image_file}"
  parted_disk_setup "${image_file}" 
}

# Mounts the image which will be the new system image on loopback interface
loopback_image_file(){
  print_function_name;
  local image_file=${_image_file};
  local loop_device;
  loop_device=$(losetup -P -f --show "${image_file}");
  partprobe "${loop_device}";
  
  _block_device_boot="${loop_device}p1" 
  _block_device_root="${loop_device}p2"
}

# Makes a luks container and formats the new disk/image
format_filesystem(){
  print_function_name;

  # Create LUKS
  print_debug "Attempting to create LUKS ${_block_device_root} "
  
  # shellcheck disable=2086
  echo "${_luks_password}" | cryptsetup -v ${_luks_configuration} luksFormat "${_block_device_root}"
  echo "${_luks_password}" | cryptsetup -v luksOpen "${_block_device_root}" "${_luks_mapping_name}"

  make_filesystem "vfat" "${_block_device_boot}"
  make_filesystem "${_filesystem_type}" "${_encrypted_volume_path}"
  
  sync
}

# Check if btrfs is the file system, if so install required packages
filesystem_setup(){
  fs_type="${_filesystem_type}"
  
  case $fs_type in
    "btrfs") 
      print_debug "- Setting up btrfs-progs in chroot"
      chroot_package_install btrfs-progs
      print_debug "- Adding btrfs module to initramfs-tools/modules"
      atomic_append "btrfs" "${_chroot_dir}/etc/initramfs-tools/modules";
      print_debug "- Enabling journalling"
      sed -i "s|rootflags=noload|""|g" "${_chroot_dir}/boot/cmdline.txt";
      ;;
    *) print_debug "skipping, fs not supported or ext4";;
  esac

}

# Formats the disk or image
parted_disk_setup()
{
  print_function_name;
  parted "$1" --script -- mklabel msdos
  parted "$1" --script -- mkpart primary fat32 1MiB 256MiB
  parted -a minimal "$1" --script -- mkpart primary 256MiB 100%
  sync;
}

# Calls mkfs for a given filesystem
# arguments: a filesystem type, e.g. btrfs, ext4 and a device
make_filesystem(){
  print_function_name;
  local fs_type=$1
  local device=$2
  case $fs_type in
    "vfat") 
            mkfs.vfat -n BOOT -F 32 -v "$device"; 
            print_debug "created vfat partition on $device"
            ;;
    "ext4") 
            features="-O ^64bit,^metadata_csum"
            mkfs.ext4 "$features" -L ROOTFS "$device"; 
            print_debug "created ext4 partition on $device"
            ;;
    "btrfs")
            mkfs.btrfs -f -L ROOTFS "$device"; 
            print_debug "created btrfs partition on $device"
            ;;
    *) 
            exit 1
            ;;
  esac
}

# Needed for emulated images in qemu
arm_setup(){
  print_function_name;
  cp /usr/bin/qemu-aarch64-static "${_chroot_dir}/usr/bin/"
}

#Opens the crypt and mounts it
mount_chroot(){
  print_function_name;
  check_directory_and_mount "${_encrypted_volume_path}" "${_chroot_dir}"
  check_directory_and_mount "${_block_device_boot}" "${_chroot_dir}/boot"
}

####CHROOT FUNCTIONS####
#mount dev,sys,proc in chroot so they are available for apt 
chroot_setup(){
  local chroot_dir="${_chroot_dir}"
  print_function_name;
 
  sync
  # mount binds
  check_mount_bind "/dev" "${chroot_dir}/dev/"; 
  check_mount_bind "/dev/pts" "${chroot_dir}/dev/pts";
  check_mount_bind "/sys" "${chroot_dir}/sys/";
  check_mount_bind "/tmp" "${chroot_dir}/tmp/";
  check_mount_bind "/run" "${chroot_dir}/run/";

  #procs special, so it does it a different way
  if [[ $(mount -t proc "/proc" "${chroot_dir}/proc/"; echo $?) != 0 ]]; then
      print_error "failure mounting ${chroot_dir}/proc/";
      exit 1;
  fi
}

#unmount dev,sys,proc in chroot
chroot_teardown(){
  print_function_name;
  local chroot_dir="${_chroot_dir}"

  print_debug "unmounting binds"
  tidy_umount "${chroot_dir}/dev/"
  tidy_umount "${chroot_dir}/sys/"
  tidy_umount "${chroot_dir}/proc/"
  tidy_umount "${chroot_dir}/tmp/"  
  tidy_umount "${chroot_dir}/run/"  
}

#must run before ANY apt calls
#speeds up apt
chroot_apt_setup(){
  print_function_name;
  local chroot_root="${_chroot_dir}"
  
  #prefer https if set, otherwise don't change
  if (( _apt_https == 1 )); then
    sed -i 's|http:|https:|g' "${chroot_root}/etc/apt/sources.list";
  fi
  
  if [ ! -f "${chroot_root}/etc/resolv.conf" ] || check_variable_is_set "${_dns}" ; then
    print_info "${chroot_root}/etc/resolv.conf does not exist or _dns is set";
    print_info "Setting nameserver to ${_dns} in ${chroot_root}/etc/resolv.conf";
    if [ -f "${chroot_root}/etc/resolv.conf" ]; then
      #if there was one, then back it up
      mv "${chroot_root}/etc/resolv.conf" "${chroot_root}/etc/resolv.conf.bak";
    fi
    echo -e "nameserver ${_dns}" > "${chroot_root}/etc/resolv.conf";
  fi
  
  #Update apt and install eatmydata to speed up things later
  chroot_execute 'apt-get clean'
  chroot_execute 'apt-get -qq -y update'
  chroot_execute 'apt-get -qq -y install eatmydata'
  if check_variable_is_set "${_extra_packages}"; then
    chroot_execute "${_apt_cmd} install ${_extra_packages}"
  fi
  
  #Corrupt package install fix code
  if ! chroot_execute "${_apt_cmd} --fix-broken install"; then
    if ! chroot_execute 'dpkg --configure -a'; then
        print_error "apt corrupted, manual intervention required";
        exit 1;
    fi
  fi
}

#installs packages from build
#arguments: a list of packages
chroot_package_install(){
  local packages=("$@")
  for package in "${packages[@]}"
  do
    print_info "installing $package";
    chroot_execute "${_apt_cmd} install ${package}" 
  done
}

#removes packages from build
#arguments: a list of packages
chroot_package_purge(){
  local packages=("$@")
  for package in "${packages[@]}"
  do
    print_info "purging $package";
    chroot_execute "${_apt_cmd} purge ${package}"
  done
  chroot_execute "${_apt_cmd} autoremove"
} 

#run a command in chroot
chroot_execute(){
  local chroot_dir="${_chroot_dir}";
  local status
  print_debug "running: ${*}"
  # shellcheck disable=2068,2086
  chroot ${chroot_dir} ${@} 
  status=${?}

  if [[ "${status}" -ne 0 ]]; then
    print_error "retval of chroot: ${status}, command failed"
    exit 1;
  fi
  
}

#generates the initramfs.gz file in /boot
chroot_mkinitramfs_setup(){
  print_function_name;
  local chroot_root="${_chroot_dir}"
  local modules_dir="${_chroot_dir}/lib/modules/";
  local kernel_version;
  chroot_execute 'mount -o remount,rw /boot '
  
  kernel_version=$(find "${modules_dir}" -maxdepth 1 -regex ".*${_kernel_version_filter}.*" | tail -n 1 | xargs basename);
  
  print_debug "running update-initramfs, mkinitramfs"
  chroot_execute 'update-initramfs -u -k all'
  chroot_execute "mkinitramfs -o /boot/initramfs.gz -v ${kernel_version}"
  
  #revert temp dns change
  if [ -f "${chroot_root}/etc/resolv.conf.bak" ]; then
    mv "${chroot_root}/etc/resolv.conf.bak" "${chroot_root}/etc/resolv.conf";
  fi
}

#wrapper script for all the setup functions called in build
chroot_all_setup(){
  chroot_setup;
  arm_setup;
  chroot_apt_setup;
  locale_setup
  filesystem_setup;
  encryption_setup;
  chroot_mkinitramfs_setup;
}

btrfs_setup(){
  local chroot_dir="${_chroot_dir}"
  local fs_type="${_filesystem_type}";
  
  case $fs_type in
    "btrfs")
        btrfs subvolume create "${_chroot_dir}/@"  
        btrfs subvolume create "${_chroot_dir}/@/root"
        
        #created automatically by snapper
        #btrfs subvolume create "${_chroot_dir}/@/.snapshots"
        
        #optional 
        #TODO mount home, var log here too 
        #btrfs subvolume create "${_chroot_dir}/@/var_log"
        #btrfs subvolume create "${_chroot_dir}/@/home"
        
        btrfs subvolume set-default "${_chroot_dir}/@/root"
        
        print_info "remounting into new root subvolume"
        umount "${_chroot_dir}/boot"
        umount "${_chroot_dir}";
        mount_chroot
        ;;
    *) 
        exit 1;
        ;;
  esac
}

#unmounts and tidies up the folder
tidy_umount(){
  if umount -q -R "$1"; then
    print_info "umounted $1";
    
    if [ -b "${1}" ]; then print_debug "block device, return"; return 0; fi

    if grep -q '/dev\|/sys\|/proc\|/tmp\|/run'  <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    
    if [ -d "${1}" ]; then print_debug "some directory, if empty delete it"; rmdir "${1}" || true; fi
    return 0    
  fi
  
  print_debug "failed to umount $1";
  return 1  
}

# method default parameter settings, if a variable is "" or unset, sets it to a reasonable default 
set_defaults(){
  print_function_name;
  set +eu
  set_default "_no_prompts" "0"  
  set_default "_log_level" "INFO"
  set_default "_luks_password" "CHANGEME"
  set_default "_filesystem_type" "ext4"
  set_default "_luks_configuration" "--type luks2 --cipher aes-xts-plain64 --key-size 512 --use-random --hash sha512 --pbkdf argon2i --iter-time 5000"
  set_default "_locale" "en_GB.UTF-8"
  set_default "_image_mode" "1"
  set_default "_image_sha256" ""
  set_default "_image_url" "MANDATORY"
  set_default "_kernel_version_filter" "MANDATORY"
  set_default "_output_block_device" "MANDATORY"
  set -eu
}

#sets a given variable_name $1 to a default value $2
#if the default passed in is set to value 'MANDATORY', then exit script as then
#a function has been called without a mandatory
#variable set
set_default(){
   local var_name="$1"
   local default_value="$2"
   local current_value;
   current_value="$(eval echo "\$${var_name}")"
   if check_variable_is_set "${current_value}" ; then
     print_info "${var_name} is set to '${current_value}'";
   else
     if [[ $default_value == 'MANDATORY' ]]; then
       print_error "${var_name} was not set and is mandatory, please amend env.sh'";
       exit 1;
     fi
     print_info "${var_name} set to default value '${default_value}'";
     export "${var_name}"="${default_value}";
   fi
}

#prompts user for a reply
#returns 0 for yes or 1 for no
ask_yes_or_no(){
  local prompt;
  local answer;
  prompt="${1}";
  echo "$prompt"
  while read -r -n 1 -s answer; do
    if [[ $answer = [YyNn] ]]; then
      [[ $answer = [Yy] ]] && retval=0;
      [[ $answer = [Nn] ]] && retval=1;
      break;
    fi
  done
  
  return $retval;
}

#checks if a variable is set or empty ''
check_variable_is_set(){
  #set
  retval=0
  
  if [[ ! ${1} ]] || [[ -z "${1}" ]]; then
    #not set
    retval=1
  fi
  
  return $retval;
}
#mounts a bind, exits on failure
check_mount_bind(){
  # mount a bind
  if ! mount -o bind "$1" "$2" ; then
    print_error "failure mounting $2";
    exit 1;
  fi
}

#mounts 1=$1 to $2, creates folder if not there
check_directory_and_mount(){
  print_debug "mounting $1 to $2";
  if [ ! -d "$2" ]; then 
    mkdir "$2";
    print_debug "created $2";
  fi
  
  if ! mount "$1" "$2" ; then
    print_error "failure mounting $1 to $2";
    exit 1;
  fi
  print_debug "mounted $1 to $2";
}

#appends config to a file after checking if it's already in the file
#$1 the config value $2 the filename
atomic_append(){
  CONFIG="$1";
  FILE="$2";
  if ! grep -qx "${CONFIG}" "${FILE}" ; then
    echo "${CONFIG}" >> "${FILE}";
  fi
}

# Rsync for local copying, preserve all attributes, show progress
#arguments $1 - to $2 - from
rsync_local(){
  print_function_name;
  print_info "starting copy of ${*}";
  if ! rsync --hard-links --no-i-r --archive --partial --info=progress2 "${@}"; then
    print_error 'rsync has failed';
    exit 1;
  fi

  print_info "finished copy";
  sync;
}

# Check if the disk about to be partitioned is already mounted, and prompt to unmount it
# Used prior to writing to disk as extra error checking
# $1 - device to check
check_device_mounted(){
   if grep -q "${1}"  '/proc/mounts'  ; then
     local prompt="${1} already mounted. Unmount and continue? (y/N)  ";
     if  ask_yes_or_no "$prompt" || (( _no_prompts == 1 )) ; then  
       umount "${1}" 
     else
      print_info "Exitting script"
      exit 1;
     fi
   fi
  sync;
}

####PRINT FUNCTIONS####
print_error(){ print_generic "ERROR" "${*}" ; }
print_warning(){ print_generic "WARN" "${*}" ; }
print_info(){ print_generic "INFO" "${*}" ; }
print_debug(){ print_generic "DEBUG" "${*}" ;}

print_generic(){
  declare -A log_levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
  local color_normal='\e[0m'; # No Color
  local color_error='\e[31m'; #red
  local color_warn='\e[33m'; #yellow
  local color_info='\e[32m'; #green
  local color_debug='\e[37m'; 
  local text_color;
  local log_level=${1};
  shift;
  
  #check if log level set properly
  [[ ${log_levels[$log_level]} ]] || exit 1;
  
  #choose color
  case ${log_level} in
        "DEBUG")
            text_color=${color_debug};
            ;;
        "INFO")
             text_color=${color_info};
            ;;
        "WARN")
             text_color=${color_warn};
            ;;
        "ERROR")
             text_color=${color_error};
            ;;
        *)
            text_color=${color_normal};
            ;;
  esac

  #check if log level is above script's log level, if not return and don't  log
  if (( ${log_levels[${log_level}]} >= ${log_levels[$_log_level]} )); then
    printf "${text_color}%s${color_normal}\\n" "$(date '+%H:%M:%S'): ${log_level}: ${*}" | tee -a "${_log_file}";
  fi
}

#tells you the command to copy the image to disk.
print_dd_command(){
  if (( _image_mode == 1 )); then
    print_info "To burn your disk run: dd if=${_image_file} of=${_output_block_device} bs=8M status=progress && sync";
    print_info "https://github.com/kaligraffy/dd-resize-root will dd and resize to the full disk if you've selected btrfs"
  fi
}

print_function_name(){
  print_info "function ${FUNCNAME[1]} started";
}
