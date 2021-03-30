#!/bin/bash
set -eu

declare -r _START_TIME="$(date +%s)";
declare -r _BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";

#can be overriden in env.sh
declare _BUILD_DIR="${_BUILD_DIR:-"${_BASE_DIR}/build"}"
declare _APT_CMD=${_APT_CMD:-"eatmydata apt-get -qq -y"};
declare _APT_HTTPS="${_APT_HTTPS:-0}";
declare _64BIT="${_64BIT:-0}";
declare _LOG_LEVEL="${_LOG_LEVEL:-1}";
declare _CHROOT_DIR="${_CHROOT_DIR:-"${_BASE_DIR}/disk"}"; #shouldn't be set to build dir
declare _ENCRYPTED_VOLUME_PATH=${_ENCRYPTED_VOLUME_PATH:-"/dev/mapper/crypt"}; #set this to something else in your env file if you already have something called crypt on your system
declare _IMAGE_FILE="${_IMAGE_FILE:-"${_BUILD_DIR}/image.img"}";
declare _LOG_FILE="${_LOG_FILE:-"${_BASE_DIR}/build.log"}";
declare image_file_size_modifier="1.1"; #amount to multiply the existing image (when making the system image) by, i.e 1.1 is 1.1 x the downloaded image size. 
declare _BLOCK_DEVICE_BOOT=""
declare _BLOCK_DEVICE_ROOT="" 
declare _EXTRA_PACKAGES=${_EXTRA_PACKAGES:-""}
declare _LUKS_MAPPING_NAME="$(basename ${_ENCRYPTED_VOLUME_PATH})"

# Runs on script exit, tidies up the mounts.
trap_on_exit(){
  print_function_name;
  local end_time;
  end_time="$(($(date +%s)-$_START_TIME))"
  cleanup;
  
  if (( $1 == 1 )); then 
    print_info "$(basename "$0") failed. Script took ${end_time} seconds";
  else
    print_info "$(basename "$0") finished successfully. Script took ${end_time} seconds";
  fi
}

# Cleanup stage 2
cleanup(){
  print_function_name;
  tidy_umount "${_BUILD_DIR}/mount" || true
  tidy_umount "${_BUILD_DIR}/boot" || true

  chroot_teardown || true 
  tidy_umount "${_BLOCK_DEVICE_BOOT}" || true 
  tidy_umount "${_BLOCK_DEVICE_ROOT}" || true 
  tidy_umount "${_CHROOT_DIR}" || true 
  if [ -b ${_ENCRYPTED_VOLUME_PATH} ]; then
    cryptsetup -v luksClose "${_LUKS_MAPPING_NAME}" || true
    cryptsetup -v remove "${_LUKS_MAPPING_NAME}" || true
  fi
  cleanup_loop_devices || true     
}

#auxiliary method for detaching loop_device in cleanup method 
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

#checks if script was run with root
check_run_as_root(){
  print_function_name;
  if (( EUID != 0 )); then
    print_error "This script must be run as root/sudo";
    exit 1;
  fi
}

#installs packages on build pc
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

unmount(){
  print_function_name;
  set_defaults > /dev/null; #output suppressed if just unmounting 
  cleanup;
}

mount_only(){
  print_function_name;
  set_defaults > /dev/null; #output suppressed if just unmounting  ;
  #trap 'trap_on_exit 1' EXIT;
  if (( _IMAGE_MODE == 1 )); then 
    loopback_image_file;
  else
    fix_block_device_names;
    check_disk_is_correct;
  fi
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen "${_BLOCK_DEVICE_ROOT}" "${_LUKS_MAPPING_NAME}"
  mount_chroot;
    
  #Probably don't want to call this if there is nothing in your filesystem so, check for an arbitrary folder that was copied over
  if [ -d "${_CHROOT_DIR}/dev" ]; then
    chroot_setup;
  fi
}

make_initramfs(){
  print_function_name;
  trap 'trap_on_exit 1' EXIT;
  mount_only;
  chroot_mkinitramfs_setup;
}

#Program logic
build(){
  print_function_name;
  install_dependencies;
  set_defaults;
  download_image;
  extract_image;
  #Check for a build directory
  create_build_directory
  trap 'trap_on_exit 1' EXIT;
  # Write to physical disk or image and modify it
  if (( _IMAGE_MODE == 1 )); then 
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

#Fix for using mmcblk0pX devices, adds a p used later on
fix_block_device_names(){
  # check device exists/folder exists
  print_function_name;
  
  if ! check_variable_is_set "${_OUTPUT_BLOCK_DEVICE}"; then
    exit 1;
  fi

  local prefix=""
  #if the device contains mmcblk, prefix is set so the device name is picked up correctly
  if [[ "${_OUTPUT_BLOCK_DEVICE}" == *'mmcblk'* ]]; then
    prefix='p'
  fi
  #Set the proper name of the output block device's partitions
  #e.g /dev/sda1 /dev/sda2 etc.
  _BLOCK_DEVICE_BOOT="${_OUTPUT_BLOCK_DEVICE}${prefix}1"
  _BLOCK_DEVICE_ROOT="${_OUTPUT_BLOCK_DEVICE}${prefix}2"
}

create_build_directory(){
  if [ -d "${_BUILD_DIR}" ]; then
    local prompt="Build directory ${_BUILD_DIR} already exists. Recreate it? (y/N)  ";
    if [ -z "$(ls -A ${_BUILD_DIR})" ] || ask_yes_or_no "$prompt" || (( _NO_PROMPTS == 1 )) ; then  
      rm -rf "${_BUILD_DIR}" ;
      mkdir "${_BUILD_DIR}" ; 
    else
      print_info "Not rebuilding"
      exit 1;
    fi
  else
    mkdir "${_BUILD_DIR}"; 
  fi
  sync;
}

#extracts the image so it can be mounted
extract_image() {
  print_function_name;

  local image_name;
  local image_path;
  image_name="$(basename "${_IMAGE_URL}")";
  image_path="${_BASE_DIR}/${image_name}";
  local extracted_image="${_BASE_DIR}/$(basename ${_IMAGE_URL} | sed 's#.xz##' | sed 's#.zip##')";

  #If no prompts is set and extracted image exists then continue to extract
  if [[ -e "${extracted_image}" ]] && (( _NO_PROMPTS == 1 )); then
    return 0;
  fi  
    
  if [[ -e "${extracted_image}" ]] ; then
    local prompt="${extracted_image} found, re-extract? (y/N)  "
    if ! ask_yes_or_no "$prompt"; then
       return 0;
    fi
  fi
  
  if check_variable_is_set "${_IMAGE_SHA256}" ]; then
      if ! echo "${_IMAGE_SHA256}"  "$image_path" | sha256sum --check --status; then
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

#mounts the extracted image via losetup
copy_image_on_loopback_to_disk(){
  print_function_name;
  local extracted_image="${_BASE_DIR}/$(basename ${_IMAGE_URL} | sed 's#.xz##' | sed 's#.zip##')";
  local loop_device;
  
  loop_device=$(losetup -P -f --read-only --show "$extracted_image");
  partprobe "${loop_device}";
  check_directory_and_mount "${loop_device}p2" "${_BUILD_DIR}/mount";
  check_directory_and_mount "${loop_device}p1" "${_BUILD_DIR}/boot";

  rsync_local "${_BUILD_DIR}/boot" "${_CHROOT_DIR}/"
  rsync_local "${_BUILD_DIR}/mount/"* "${_CHROOT_DIR}"
}

#prompts to check disk is correct before writing out to disk, 
#if no prompts is set, it skips the check
check_disk_is_correct(){
  print_function_name;
  if [ ! -b "${_OUTPUT_BLOCK_DEVICE}" ]; then
    print_error "${_OUTPUT_BLOCK_DEVICE} is not a block device" 
    exit 0
  fi
  
  if (( _NO_PROMPTS == 0 )); then
    local prompt="Device is ${_OUTPUT_BLOCK_DEVICE}? (y/N) "
    print_info "$(lsblk)";
    print_warning "CHECK THE DISK IS CORRECT";

    if ! ask_yes_or_no "$prompt" ; then
        exit 0
    fi
  fi
}

#Download an image file to the file directory
download_image(){
  print_function_name;

  local image_name;
  local image_out_file;

  image_name=$(basename "${_IMAGE_URL}");
  image_out_file="${_BASE_DIR}/${image_name}"
  
  wget -nc "${_IMAGE_URL}" -O "${image_out_file}" || true
  
}

#sets the locale (e.g. en_US, en_UK)
locale_setup(){
  print_function_name;
  
  chroot_package_install locales
  
  print_debug "Uncommenting locale ${_LOCALE} for inclusion in generation"
  sed -i "s/^# *\(${_LOCALE}\)/\1/" "${_CHROOT_DIR}/etc/locale.gen";
  
  print_debug "Updating /etc/default/locale";
  atomic_append "LANG=${_LOCALE}" "${_CHROOT_DIR}/etc/default/locale";
  atomic_append "LANGUAGE=${_LOCALE}"  "${_CHROOT_DIR}/etc/default/locale"
 # atomic_append "LC_ALL=${_LOCALE}"  "${_CHROOT_DIR}/etc/default/locale"

  print_debug "Updating env variables";
  chroot "${_CHROOT_DIR}" /bin/bash -x <<- EOT
export LANG="${_LOCALE}";
export LANGUAGE="${_LOCALE}";
locale-gen
EOT

}

#sets up encryption settings in chroot
encryption_setup(){
  print_function_name;
  local fs_type
  fs_type=${_FILESYSTEM_TYPE};
  chroot_package_install cryptsetup busybox

  # Creating symbolic link to e2fsck
  #TODO This may not be needed
  chroot "${_CHROOT_DIR}" /bin/bash -c "test -L /sbin/fsck.luks || ln -s /sbin/e2fsck /sbin/fsck.luks"

  # Indicate kernel to use initramfs - facilitates loading drivers
  sed -i 's|^initramfs.*|\#&|g' "${_CHROOT_DIR}/boot/config.txt";
  atomic_append 'initramfs initramfs.gz followkernel' "${_CHROOT_DIR}/boot/config.txt";
  
  # Update /boot/cmdline.txt to boot crypt
  sed -i "s|root=.* |root=${_ENCRYPTED_VOLUME_PATH} cryptdevice=/dev/mmcblk0p2:${_LUKS_MAPPING_NAME} |g" "${_CHROOT_DIR}/boot/cmdline.txt"
  sed -i "s|rootfstype=.* |rootfstype=${fs_type} |g" "${_CHROOT_DIR}/boot/cmdline.txt"
  
  #disable init script for pios
  sed -i "s|init=.* | |g" "${_CHROOT_DIR}/boot/cmdline.txt"

  #force 64bit if set
  if (( _64BIT == 1 )); then
    print_info 'Set 64bit mode'
    atomic_append 'arm_64bit=1' "${_CHROOT_DIR}/boot/config.txt";
  fi
  
  # Enable cryptsetup when building initramfs
  atomic_append 'CRYPTSETUP=y' "${_CHROOT_DIR}/etc/cryptsetup-initramfs/conf-hook"  
  
  # Setup /etc/fstab
    case $fs_type in
    "btrfs")   
cat << EOF > "${_CHROOT_DIR}/etc/fstab"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
${_ENCRYPTED_VOLUME_PATH}  /            $fs_type    defaults,noatime,subvol=@/root  0  1
#Example config you may like to use:
#${_ENCRYPTED_VOLUME_PATH}  /.snapshots  $fs_type    defaults,noatime,subvol=@/.snapshots  0  1    
#${_ENCRYPTED_VOLUME_PATH}  /var/log     $fs_type    defaults,noatime,subvol=@/var_log  0  1    
#${_ENCRYPTED_VOLUME_PATH}  /home        $fs_type    defaults,noatime,subvol=@/home  0  1
EOF
    ;;
    "ext4") 
cat << EOF > "${_CHROOT_DIR}/etc/fstab"
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
${_ENCRYPTED_VOLUME_PATH}  /    $fs_type    defaults,noatime  0       1
EOF
    ;;
    *) print_error "filesystem not supported"
       exit 1
    ;;
  esac

  #Setup crypttab
  cat << EOF > "${_CHROOT_DIR}/etc/crypttab"
#<target name> <source device>         <key file>      <options>
$(basename ${_ENCRYPTED_VOLUME_PATH})    /dev/mmcblk0p2    none    luks
EOF

  # Create a hook to include our crypttab in the initramfs
  cp -p "${_BASE_DIR}/zz-cryptsetup" "${_CHROOT_DIR}/etc/initramfs-tools/hooks/zz-cryptsetup";
  
  # Adding dm_mod, dm_crypt to initramfs modules
  #dm_mod needed for pios, oddly doesn't seem to be needed for kali 
  atomic_append 'dm_mod' "${_CHROOT_DIR}/etc/initramfs-tools/modules";
  atomic_append 'dm_crypt' "${_CHROOT_DIR}/etc/initramfs-tools/modules";
  
  # Disable autoresize
  chroot_execute 'systemctl disable rpi-resizerootfs.service'
  chroot_execute 'systemctl disable rpiwiggle.service'
}

# Encrypt & Write SD
partition_disk(){  
  print_function_name;
  parted_disk_setup "${_OUTPUT_BLOCK_DEVICE}" 
}

#makes an image file 1.1 * the size of the extracted image, then partitions the disk
partition_image_file(){
  print_function_name;
  local image_file=${_IMAGE_FILE};
  local extracted_image="${_BASE_DIR}/$(basename ${_IMAGE_URL} | sed 's#.xz##' | sed 's#.zip##')";
  local extracted_image_file_size;
  local image_file_size;
  
  extracted_image_file_size="$(du -k "${extracted_image}" | cut -f1)"
  image_file_size="$(echo "${extracted_image_file_size} * ${image_file_size_modifier}" | bc | cut -d'.' -f1)"; 
  touch "$image_file";
  fallocate -l "${image_file_size}KiB" "${image_file}"
  parted_disk_setup "${image_file}" 
}

# Mounts the image which will be the new system image on loopback interface
loopback_image_file(){
  print_function_name;
  local image_file=${_IMAGE_FILE};
  local loop_device;
  loop_device=$(losetup -P -f --show "${image_file}");
  partprobe "${loop_device}";
  
  _BLOCK_DEVICE_BOOT="${loop_device}p1" 
  _BLOCK_DEVICE_ROOT="${loop_device}p2"
}

# Makes a luks container and formats the new disk/image
format_filesystem(){
  print_function_name;

  # Create LUKS
  print_debug "Attempting to create LUKS ${_BLOCK_DEVICE_ROOT} "
  echo "${_LUKS_PASSWORD}" | cryptsetup -v ${_LUKS_CONFIGURATION} luksFormat "${_BLOCK_DEVICE_ROOT}"
  echo "${_LUKS_PASSWORD}" | cryptsetup -v luksOpen "${_BLOCK_DEVICE_ROOT}" "${_LUKS_MAPPING_NAME}"

  make_filesystem "vfat" "${_BLOCK_DEVICE_BOOT}"
  make_filesystem "${_FILESYSTEM_TYPE}" "${_ENCRYPTED_VOLUME_PATH}"
  
  sync
}

# Check if btrfs is the file system, if so install required packages
filesystem_setup(){
  fs_type="${_FILESYSTEM_TYPE}"
  
  case $fs_type in
    "btrfs") 
      print_debug "- Setting up btrfs-progs in chroot"
      chroot_package_install btrfs-progs
      print_debug "- Adding btrfs module to initramfs-tools/modules"
      atomic_append "btrfs" "${_CHROOT_DIR}/etc/initramfs-tools/modules";
      print_debug "- Enabling journalling"
      sed -i "s|rootflags=noload|""|g" "${_CHROOT_DIR}/boot/cmdline.txt";
      ;;
    *) print_debug "skipping, fs not supported or ext4";;
  esac

}

#formats the disk or image
parted_disk_setup()
{
  print_function_name;
  parted "$1" --script -- mklabel msdos
  parted "$1" --script -- mkpart primary fat32 1MiB 256MiB
  parted -a minimal "$1" --script -- mkpart primary 256MiB 100%
  sync;
}

#calls mkfs for a given filesystem
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

arm_setup(){
  print_function_name;
  cp /usr/bin/qemu-aarch64-static "${_CHROOT_DIR}/usr/bin/"
}

#Opens the crypt and mounts it
mount_chroot(){
  print_function_name;
  check_directory_and_mount "${_ENCRYPTED_VOLUME_PATH}" "${_CHROOT_DIR}"
  check_directory_and_mount "${_BLOCK_DEVICE_BOOT}" "${_CHROOT_DIR}/boot"
}

####CHROOT FUNCTIONS####
#mount dev,sys,proc in chroot so they are available for apt 
chroot_setup(){
  local chroot_dir="${_CHROOT_DIR}"
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
  local chroot_dir="${_CHROOT_DIR}"

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
  local chroot_root="${_CHROOT_DIR}"
  
  #prefer https if set, otherwise don't change
  if (( _APT_HTTPS == 1 )); then
    sed -i 's|http:|https:|g' "${chroot_root}/etc/apt/sources.list";
  fi
  
  if [ ! -f "${chroot_root}/etc/resolv.conf" ] || check_variable_is_set "${_DNS}" ; then
    print_info "${chroot_root}/etc/resolv.conf does not exist or _DNS is set";
    print_info "Setting nameserver to $_DNS in ${chroot_root}/etc/resolv.conf";
    if [ -f "${chroot_root}/etc/resolv.conf" ]; then
      #if there was one, then back it up
      mv "${chroot_root}/etc/resolv.conf" "${chroot_root}/etc/resolv.conf.bak";
    fi
    echo -e "nameserver ${_DNS}" > "${chroot_root}/etc/resolv.conf";
  fi
  
  #Update apt and install eatmydata to speed up things later
  chroot_execute 'apt-get -qq -y update'
  chroot_execute 'apt-get -qq -y install eatmydata'
  if check_variable_is_set ${_EXTRA_PACKAGES}; then
    chroot_execute "${_APT_CMD} install ${_EXTRA_PACKAGES}"
  fi
  
  #Corrupt package install fix code
  if ! chroot_execute "${_APT_CMD} --fix-broken install"; then
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
    chroot_execute "${_APT_CMD} install ${package}" 
  done
}

#removes packages from build
#arguments: a list of packages
chroot_package_purge(){
  local packages=("$@")
  for package in "${packages[@]}"
  do
    print_info "purging $package";
    chroot_execute "${_APT_CMD} purge ${package}"
  done
  chroot_execute "${_APT_CMD} autoremove"
} 

#run a command in chroot
chroot_execute(){
  local chroot_dir="${_CHROOT_DIR}";
  local status
  print_debug "Running: ${@}"
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
  local chroot_root="${_CHROOT_DIR}"
  local modules_dir="${_CHROOT_DIR}/lib/modules/";
  local kernel_version;
  chroot_execute 'mount -o remount,rw /boot '
  
  kernel_version=$(find "${modules_dir}" -maxdepth 1 -regex ".*${_KERNEL_VERSION_FILTER}.*" | tail -n 1 | xargs basename);
  
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
  local chroot_dir="${_CHROOT_DIR}"
  local fs_type="${_FILESYSTEM_TYPE}";
  
  case $fs_type in
    "btrfs")
        btrfs subvolume create "${_CHROOT_DIR}/@"  
        btrfs subvolume create "${_CHROOT_DIR}/@/root"
        
        #created automatically by snapper
        #btrfs subvolume create "${_CHROOT_DIR}/@/.snapshots"
        
        #optional 
        #TODO mount home, var log here too 
        #btrfs subvolume create "${_CHROOT_DIR}/@/var_log"
        #btrfs subvolume create "${_CHROOT_DIR}/@/home"
        
        btrfs subvolume set-default "${_CHROOT_DIR}/@/root"
        
        echo "remounting into new root subvol"
        umount "${_CHROOT_DIR}/boot"
        umount "${_CHROOT_DIR}";
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
    
    if [ -b $1 ]; then print_debug "block device, return"; return 0; fi

    if grep -q '/dev'  <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    if grep -q '/sys'  <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    if grep -q '/proc' <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    if grep -q '/tmp'  <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    if grep -q '/run'  <<< "$1" ; then print_debug "bind for chroot, return"; return 0; fi
    
    if [ -d "$1" ]; then print_debug "some directory, if empty delete it"; rmdir "$1" || true; fi
    return 0    
  fi
  
  print_debug "failed to umount $1";
  return 1  
}

# method default parameter settings, if a variable is "" or unset, sets it to a reasonable default 
set_defaults(){
  print_function_name;
  set +eu
  set_default "_NO_PROMPTS" "0"  
  set_default "_LOG_LEVEL" "1"
  set_default "_LUKS_PASSWORD" "CHANGEME"
  set_default "_FILESYSTEM_TYPE" "ext4"
  set_default "_LUKS_CONFIGURATION" "--type luks2 --cipher aes-xts-plain64 --key-size 512 --use-random --hash sha512 --pbkdf argon2i --iter-time 5000"
  set_default "_LOCALE" "en_US.UTF-8"
  set_default "_IMAGE_MODE" "1"
  set_default "_IMAGE_SHA256" ""
  set_default "_IMAGE_URL" "MANDATORY"
  set_default "_KERNEL_VERSION_FILTER" "MANDATORY"
  set_default "_OUTPUT_BLOCK_DEVICE" "MANDATORY"
  set -eu
}

#sets a given variable_name $1 to a default value $2
#if the default passed in is 'MANDATORY', then exit as then
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

#rsync for local copy
#arguments $1 - to $2 - from
rsync_local(){
  print_function_name;
  print_info "starting copy of ${*}";
  if rsync --hard-links --no-i-r --archive --partial --info=progress2 "${@}"; then
    print_info "finished copy of ${*}";
    sync;
  else
    print_error 'rsync has failed';
    exit 1;
  fi
}

####PRINT FUNCTIONS####
#Global variables
declare -x _COLOR_ERROR='\e[31m'; #red
declare -x _COLOR_WARN='\e[33m'; #yellow
declare -x _COLOR_INFO='\e[32m'; #green
declare -x _COLOR_DEBUG='\e[37m'; 
declare -x _COLOR_NORMAL='\e[0m'; # No Color
print_error(){  printf "${_COLOR_ERROR}%s${_COLOR_NORMAL}\n" "$(date '+%H:%M:%S'): ERROR: ${*}" | tee -a "${_LOG_FILE}"; }
print_warning(){   printf "${_COLOR_WARN}%s${_COLOR_NORMAL}\n" "$(date '+%H:%M:%S'): WARNING: ${*}" | tee -a "${_LOG_FILE}"; }
print_info(){   printf "${_COLOR_INFO}%s${_COLOR_NORMAL}\n" "$(date '+%H:%M:%S'): INFO: ${*}" | tee -a "${_LOG_FILE}"; }
print_debug(){
  if (( _LOG_LEVEL < 1 )); then
    printf "${_COLOR_DEBUG}%s${_COLOR_NORMAL}\n" "$(date '+%H:%M:%S'): DEBUG: ${*}";
  fi
  #even if output is suppressed by log level output it to the log file
  printf "${_COLOR_DEBUG}%s${_COLOR_NORMAL}\n" "$(date '+%H:%M:%S'): DEBUG: ${*}" >> "${_LOG_FILE}";
}

#tells you the command to copy the image to disk.
print_dd_command(){
  if (( _IMAGE_MODE == 1 )); then
    print_info "To burn your disk run: dd if=${_IMAGE_FILE} of=${_OUTPUT_BLOCK_DEVICE} bs=8M status=progress && sync";
    print_info "https://github.com/kaligraffy/dd-resize-root will dd and resize to the full disk if you've selected btrfs"
  fi
}

print_function_name(){
  print_info "function ${FUNCNAME[1]} started";
}
