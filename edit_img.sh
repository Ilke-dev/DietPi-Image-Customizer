#!/bin/bash

# Function to display help
show_help() {
  echo "Usage: $0 [-h] [-t dietpi.txt] [-w dietpi-wifi.txt] [-c cmdline.txt] [-s Automation_Custom_Script.sh] [-p Automation_Custom_PreScript.sh] [-f ./custom-files/] [-i dietpi.img.xz]"
  echo
  echo "Options:"
  echo "  -h                                    Show this help message and exit"
  echo "  -t dietpi.txt                         Path to the dietpi.txt file"
  echo "  -w dietpi-wifi.txt                    Path to the dietpi-wifi.txt file (optional)"
  echo "  -c cmdline.txt                        Path to the cmdline.txt file (optional)"
  echo "  -s Automation_Custom_Script.sh        Path to the Automation_Custom_Script.sh file (optional)"
  echo "  -p Automation_Custom_PreScript.sh     Path to the Automation_Custom_PreScript.sh file (optional)"
  echo "  -f ./custom-files/                    Path to the directory containing additional custom files (optional, image will be auto-resized to fit)"
  echo "  -i dietpi.img.xz                      Path or URL to the dietpi.img.xz file"
}

# Parse command line options
while getopts ":ht:w:c:s:p:f:i:" opt; do
  case ${opt} in
    h )
      show_help
      exit 0
      ;;
    t )
      DIETPI_TXT="$OPTARG"
      ;;
    w )
      DIETPI_WIFI_TXT="$OPTARG"
      ;;
    c )
      CMDLINE_TXT="$OPTARG"
      ;;
    s )
      SCRIPT="$OPTARG"
      ;;
    p )
      PRE_SCRIPT="$OPTARG"
      ;;
    f )
      FILES_DIR="$OPTARG"
      ;;
    i )
      DIETPI_IMG_XZ="$OPTARG"
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      show_help
      exit 1
      ;;
    : )
      echo "Invalid option: -$OPTARG requires an argument" 1>&2
      show_help
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Check if required arguments are provided
if [ -z "$DIETPI_TXT" ] || [ -z "$DIETPI_IMG_XZ" ]; then
  echo "Error: Missing required arguments" 1>&2
  show_help
  exit 1
fi

# Set optional arguments to empty strings, if not provided
DIETPI_WIFI_TXT="${DIETPI_WIFI_TXT:-}"
CMDLINE_TXT="${CMDLINE_TXT:-}"
SCRIPT="${SCRIPT:-}"
PRE_SCRIPT="${PRE_SCRIPT:-}"
FILES_DIR="${FILES_DIR:-}"

# Unpack the xz archive to the /tmp folder
TMP_DIR=$(mktemp -d)
CURRENT_DIR=$(pwd)

# Function to clean up and exit on error
cleanup_and_exit() {
  echo -e "\e[31mError: $1\e[0m"

  if [ ! -z "${MOUNT_BOOT_DIR+x}" ]; then
    sudo umount "$MOUNT_BOOT_DIR"
  fi

  if [ ! -z "${MOUNT_FS_DIR+x}" ]; then
    sudo umount "$MOUNT_FS_DIR"
  fi

  if [ ! -z "${LOOP_DEVICE+x}" ]; then
    sudo losetup -d "$LOOP_DEVICE"
  fi
  
  rm -rf "$TMP_DIR"
  exit 1
}

print_ok() {
  echo -e "\e[32m$1\e[0m"
}

# Check if the third argument is a URL
if [[ "$DIETPI_IMG_XZ" =~ ^https?:// ]]; then
  print_ok "Downloading image from URL..."
  FILENAME=$(basename "$DIETPI_IMG_XZ")
  curl -# -L "$DIETPI_IMG_XZ" -o "$TMP_DIR/$FILENAME" || cleanup_and_exit "Failed to download image"

  # Download the SHA256 checksum file
  print_ok "Downloading SHA256 checksum file..."
  curl -# -L "${DIETPI_IMG_XZ}.sha256" -o "$TMP_DIR/$FILENAME.sha256" || cleanup_and_exit "Failed to download SHA256 checksum"

  # Download the signature file
  print_ok "Downloading signature file..."
  curl -# -L "${DIETPI_IMG_XZ}.asc" -o "$TMP_DIR/$FILENAME.asc" || cleanup_and_exit "Failed to download signature"

  # Verify the SHA256 checksum  
  print_ok "Verifying SHA256 checksum..."
  sed -i "s|$(basename "$DIETPI_IMG_XZ")|$TMP_DIR/$FILENAME|" "$TMP_DIR/$FILENAME.sha256"
  sha256sum -c "$TMP_DIR/$FILENAME.sha256" > /dev/null 2>&1 || cleanup_and_exit "SHA256 checksum verification failed"

  print_ok "Importing public key..."
  # Download the public key of "MichaIng <micha@dietpi.com>"
  gpg --quiet --keyserver hkp://keyserver.ubuntu.com --recv-keys C2C4D1DEF7C96C6EDF3937B2536B2A4A2E72D870 || cleanup_and_exit "Failed to import public key"
  # Verify the signature
  print_ok "Verifying signature..."
  gpg --quiet --verify "$TMP_DIR/$FILENAME.asc" "$TMP_DIR/$FILENAME" || cleanup_and_exit "Signature verification failed"

  DIETPI_IMG_XZ="$TMP_DIR/$FILENAME"
else
  FILENAME=$(basename "$DIETPI_IMG_XZ")
fi

print_ok "Unpacking xz archive..."
xz -d -k -c "$DIETPI_IMG_XZ" > "$TMP_DIR/${FILENAME%.xz}" || cleanup_and_exit "Failed to unpack xz archive"

# Expand image to fit custom files if needed
if [ -n "$FILES_DIR" ]; then
    for tool in sfdisk e2fsck resize2fs; do
        command -v "$tool" > /dev/null 2>&1 || cleanup_and_exit "Required tool '$tool' not found (install e2fsprogs and util-linux)"
    done

    FILES_SIZE=$(du -sb "$FILES_DIR" | awk '{print $1}')
    EXTRA_MB=$(( (FILES_SIZE * 3 / 2 / 1048576) + 1 ))
    [ "$EXTRA_MB" -lt 10 ] && EXTRA_MB=10

    print_ok "Expanding image by ${EXTRA_MB}MB to fit custom files..."
    truncate -s "+${EXTRA_MB}M" "$TMP_DIR/${FILENAME%.xz}" || cleanup_and_exit "Failed to expand image"

    print_ok "Resizing root partition..."
    echo ", +" | sfdisk -N 2 "$TMP_DIR/${FILENAME%.xz}" > /dev/null || cleanup_and_exit "Failed to resize partition"
fi

# Mount the Disk Image File to a unique /tmp folder
print_ok "Mounting image..."
sudo losetup -f -P "$TMP_DIR/${FILENAME%.xz}" || cleanup_and_exit "Failed to set up loop device"
LOOP_DEVICE=$(losetup -l | grep "$TMP_DIR/${FILENAME%.xz}" | awk '{print $1}')
lsblk --raw --output "NAME,MAJ:MIN" --noheadings $LOOP_DEVICE | tail -n +2 | while read dev node; do
  MAJ=$(echo $node | cut -d: -f1)
  MIN=$(echo $node | cut -d: -f2)
  [ ! -e "/dev/$dev" ] &&  mknod "/dev/$dev" b $MAJ $MIN
done

# Resize filesystem if image was expanded
if [ -n "$FILES_DIR" ]; then
    print_ok "Resizing root filesystem..."
    sudo e2fsck -f -p "${LOOP_DEVICE}p2" > /dev/null 2>&1 || true
    sudo resize2fs "${LOOP_DEVICE}p2" > /dev/null 2>&1 || cleanup_and_exit "Failed to resize filesystem"
fi

MOUNT_BOOT_DIR=$(mktemp -d)
MOUNT_FS_DIR=$(mktemp -d)
sudo mount "${LOOP_DEVICE}p1" "$MOUNT_BOOT_DIR" || cleanup_and_exit "Failed to mount boot image"
sudo mount "${LOOP_DEVICE}p2" "$MOUNT_FS_DIR" || cleanup_and_exit "Failed to mount file system image"

# Copy the txt files to the mounted folder
print_ok "Copying dietpi.txt config file..."
sudo cp "$DIETPI_TXT" "$MOUNT_BOOT_DIR/dietpi.txt" || cleanup_and_exit "Failed to copy dietpi.txt"

if [ -n "$DIETPI_WIFI_TXT" ]; then
    print_ok "Copying dietpi-wifi.txt config file..."
    sudo cp "$DIETPI_WIFI_TXT" "$MOUNT_BOOT_DIR/dietpi-wifi.txt" || cleanup_and_exit "Failed to copy dietpi-wifi.txt"
fi

if [ -n "$CMDLINE_TXT" ]; then
    print_ok "Copying cmdline.txt config file..."
    sudo cp "$CMDLINE_TXT" "$MOUNT_BOOT_DIR/cmdline.txt" || cleanup_and_exit "Failed to copy cmdline.txt"
fi

if [ -n "$SCRIPT" ]; then
    print_ok "Copying Automation_Custom_Script.sh script file..."
    sudo cp "$SCRIPT" "$MOUNT_BOOT_DIR/Automation_Custom_Script.sh" || \
        cleanup_and_exit "Failed to copy Automation_Custom_Script.sh"
fi

if [ -n "$PRE_SCRIPT" ]; then
    print_ok "Copying Automation_Custom_PreScript.sh script file..."
    sudo cp "$PRE_SCRIPT" "$MOUNT_BOOT_DIR/Automation_Custom_PreScript.sh" || \
        cleanup_and_exit "Failed to copy Automation_Custom_PreScript.sh"
fi

if [ -n "$FILES_DIR" ]; then
    print_ok "Copying custom files directory..."
    sudo cp -r "$FILES_DIR" "$MOUNT_FS_DIR/boot/" || cleanup_and_exit "Failed to copy custom files directory"
fi

# Unmount the folder
print_ok "Unmounting image..."
sudo umount "$MOUNT_BOOT_DIR" || cleanup_and_exit "Failed to unmount boot image"
sudo umount "$MOUNT_FS_DIR" || cleanup_and_exit "Failed to unmount file system image"
sudo losetup -d "$LOOP_DEVICE" || cleanup_and_exit "Failed to detach loop device"

# Archive the Disk Image File into a xz archive
print_ok "Creating xz archive..."
MODIFIED_IMG_XZ="$CURRENT_DIR/${FILENAME%.img.xz}-modified.img.xz"
xz -v -z -c "$TMP_DIR/${FILENAME%.xz}" > "$MODIFIED_IMG_XZ" || cleanup_and_exit "Failed to create xz archive"

# Clean up
rm -rf "$TMP_DIR"
print_ok "Process completed. Modified image saved as $MODIFIED_IMG_XZ"
