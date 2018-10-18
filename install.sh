#!/bin/bash

# The location where the /bin, /packet_forwarder and /lora_gateway folders will
# be created
INSTALL_DIR="$HOME"

# Stop on the first sign of trouble
set -ueo pipefail

# Version is the first argument to the installer, or "spi" if the argument is
# not set
VERSION=${1:-spi}

echo "The Things Network Gateway installer"
echo "Flavor $VERSION"

# Request gateway configuration data
# There are two ways to do it, manually specify everything
# or rely on the gateway EUI and retrieve settings files from remote (recommended)
echo "Gateway configuration:"

# Try to get gateway ID from MAC address

# Get first non-loopback network device that is currently connected
GATEWAY_EUI_NIC=$(ip -oneline link show up 2>&1 | grep -v LOOPBACK | sed -E 's/^[0-9]+: ([0-9a-z]+): .*/\1/' | head -1)
if [[ -z $GATEWAY_EUI_NIC ]]; then
    echo "ERROR: No network interface found. Cannot set gateway ID."
    exit 1
fi

# Then get EUI based on the MAC address of that device
GATEWAY_EUI=$(cat /sys/class/net/$GATEWAY_EUI_NIC/address | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
GATEWAY_EUI=${GATEWAY_EUI^^} # toupper

echo "Detected EUI $GATEWAY_EUI from $GATEWAY_EUI_NIC"

printf "       Host name [ttn-gateway]:"
read NEW_HOSTNAME
if [[ $NEW_HOSTNAME == "" ]]; then NEW_HOSTNAME="ttn-gateway"; fi

printf "       Descriptive name [ttn-ic880a]:"
read GATEWAY_NAME
if [[ $GATEWAY_NAME == "" ]]; then GATEWAY_NAME="ttn-ic880a"; fi

printf "       Contact email: "
read GATEWAY_EMAIL

printf "       Latitude [0]: "
read GATEWAY_LAT
if [[ $GATEWAY_LAT == "" ]]; then GATEWAY_LAT=0; fi

printf "       Longitude [0]: "
read GATEWAY_LON
if [[ $GATEWAY_LON == "" ]]; then GATEWAY_LON=0; fi

printf "       Altitude [0]: "
read GATEWAY_ALT
if [[ $GATEWAY_ALT == "" ]]; then GATEWAY_ALT=0; fi


# Change hostname if needed
CURRENT_HOSTNAME=$(hostname)

if [[ $NEW_HOSTNAME != $CURRENT_HOSTNAME ]]; then
    echo "Updating hostname to '$NEW_HOSTNAME'..."
    hostname $NEW_HOSTNAME
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/" /etc/hosts
fi

# Install LoRaWAN packet forwarder repositories
mkdir -p "$INSTALL_DIR"
pushd "$INSTALL_DIR"

# Build LoRa gateway app
if [ ! -d lora_gateway ]; then
    git clone https://github.com/Lora-net/lora_gateway.git --depth 1
fi
pushd lora_gateway

sed -i -e 's/PLATFORM= kerlink/PLATFORM= imst_rpi/g' "$INSTALL_DIR/lora_gateway/libloragw/library.cfg"

make

popd

# Build packet forwarder
if [ ! -d packet_forwarder ]; then
    git clone -b add_fake_gps_time https://github.com/frazar/packet_forwarder.git --depth 1
fi
pushd packet_forwarder

make

popd

# Symlink poly packet forwarder
mkdir -p "$INSTALL_DIR/bin"
if [ -f "$INSTALL_DIR/bin/lora_pkt_fwd" ]; then rm "$INSTALL_DIR/bin/lora_pkt_fwd"; fi
ln -s "$INSTALL_DIR/packet_forwarder/lora_pkt_fwd/lora_pkt_fwd" "$INSTALL_DIR/bin/lora_pkt_fwd"
cp ./packet_forwarder/lora_pkt_fwd/global_conf.json ./bin/global_conf.json

popd

# Copy service files
echo $(pwd)
sed -i -e "s/INSTALL_DIR=\/home\/pi\/ttn-gateway/INSTALL_DIR=${INSTALL_DIR////\\/}/g" ./start.sh
cp ./start.sh "$INSTALL_DIR/bin/"

sed -i -e "s/WorkingDirectory=\/opt\/ttn-gateway\/bin\//WorkingDirectory=${INSTALL_DIR////\\/}\/bin\//g" ./ttn-gateway.service
sed -i -e "s/ExecStart=\/opt\/ttn-gateway\/bin\/start.sh/ExecStart=${INSTALL_DIR////\\/}\/bin\/start.sh/g" ./ttn-gateway.service

sudo cp ttn-gateway.service /lib/systemd/system/
sudo systemctl enable ttn-gateway.service

echo "Gateway EUI is: $GATEWAY_EUI"
echo "The hostname is: $NEW_HOSTNAME"
echo "Remember to put your configuration file in '$INSTALL_DIR/bin/local_conf.json'"
echo
echo "Installation completed."

