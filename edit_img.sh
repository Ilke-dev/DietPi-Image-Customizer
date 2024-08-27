#!/bin/bash

# Function to display help
show_help() {
  echo "Usage: $0 [-h] [-t dietpi.txt] [-w dietpi-wifi.txt] [-i dietpi.img.xz]"
  echo
  echo "Options:"
  echo "  -h                Show this help message and exit"
  echo "  -t dietpi.txt     Path to the dietpi.txt file"
  echo "  -w dietpi-wifi.txt Path to the dietpi-wifi.txt file (optional)"
  echo "  -i dietpi.img.xz  Path or URL to the dietpi.img.xz file"
}

# Parse command line options
while getopts ":ht:w:i:" opt; do
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

# If DIETPI_WIFI_TXT is not provided, set it to an empty string
DIETPI_WIFI_TXT="${DIETPI_WIFI_TXT:-}"

# Unpack the xz archive to the /tmp folder
TMP_DIR=$(mktemp -d)
CURRENT_DIR=$(pwd)

# Function to clean up and exit on error
cleanup_and_exit() {
  echo -e "\e[31mError: $1\e[0m"
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

# Mount the Disk Image File to a unique /tmp folder
print_ok "Mounting image..."
sudo losetup -f -P "$TMP_DIR/${FILENAME%.xz}" || cleanup_and_exit "Failed to set up loop device"
LOOP_DEVICE=$(losetup -l | grep "$TMP_DIR/${FILENAME%.xz}" | awk '{print $1}')
MOUNT_DIR=$(mktemp -d)
sudo mount "${LOOP_DEVICE}p1" "$MOUNT_DIR" || cleanup_and_exit "Failed to mount image"

# Copy the txt files to the mounted folder
print_ok "Copying dietpi config txt files..."
sudo cp "$DIETPI_TXT" "$MOUNT_DIR/dietpi.txt" || cleanup_and_exit "Failed to copy dietpi.txt"

if [ -n "$DIETPI_WIFI_TXT" ]; then
    sudo cp "$DIETPI_WIFI_TXT" "$MOUNT_DIR/dietpi-wifi.txt" || cleanup_and_exit "Failed to copy dietpi-wifi.txt"
fi 

# Unmount the folder
print_ok "Unmounting image..."
sudo umount "$MOUNT_DIR" || cleanup_and_exit "Failed to unmount image"
sudo losetup -d "$LOOP_DEVICE" || cleanup_and_exit "Failed to detach loop device"

# Archive the Disk Image File into a xz archive
print_ok "Creating xz archive..."
MODIFIED_IMG_XZ="$CURRENT_DIR/${FILENAME%.img.xz}-modified.img.xz"
xz -vvv -z -c "$TMP_DIR/${FILENAME%.xz}" > "$MODIFIED_IMG_XZ" || cleanup_and_exit "Failed to create xz archive"

# Clean up
rm -rf "$TMP_DIR"
print_ok "Process completed. Modified image saved as $MODIFIED_IMG_XZ"