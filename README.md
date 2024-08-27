# DietPi Image Customization Script

This script customizes a DietPi image by modifying its configuration files (`dietpi.txt` and optionally `dietpi-wifi.txt`). It supports downloading the image from a URL, verifying its integrity, and repacking it after customization.

## Usage

```bash
./edit_img.sh [-h] [-t dietpi.txt] [-w dietpi-wifi.txt] [-i dietpi.img.xz]
```

## Options
-h Show the help message and exit.
-t dietpi.txt Path to the dietpi.txt file (required).
-w dietpi-wifi.txt Path to the dietpi-wifi.txt file (optional).
-i dietpi.img.xz Path or URL to the dietpi.img.xz file (required).

## Example
```bash
./edit_img.sh -t /path/to/dietpi.txt -w /path/to/dietpi-wifi.txt -i /path/to/dietpi.img.xz
```

[![Demo with URL download](https://asciinema.org/a/NGIFjNhs4suD1DKgbhgTJmwMD.svg)](https://asciinema.org/a/NGIFjNhs4suD1DKgbhgTJmwMD)

## Description
- Help Message: Displays usage information.
- Argument Parsing: Parses command-line arguments to get paths to the dietpi.txt, dietpi-wifi.txt, and dietpi.img.xz files.
- Download and Verify Image: If the image is provided as a URL, it downloads the image, its SHA256 checksum, and its signature. It verifies the checksum and the GPG signature.
- Unpack Image: Unpacks the .xz image file.
- Mount Image: Mounts the image to a temporary directory.
- Copy Configuration Files: Copies the dietpi.txt and dietpi-wifi.txt files to the mounted image.
- Unmount and Repack Image: Unmounts the image and repacks it into a new .xz archive.
- Cleanup: Cleans up temporary files and directories.

## Requirements
- bash
- curl
- gpg
- sha256sum
- xz
- sudo
- losetup
- mount

## Error Handling
The script includes error handling to clean up temporary files and directories if any step fails. It prints error messages in red and success messages in green.

## Notes
- Ensure you have the necessary permissions to run sudo commands.
- The script assumes the public key for verifying the GPG signature is available on the keyserver hkp://keyserver.ubuntu.com.

## License
This project is licensed under the MIT License. 