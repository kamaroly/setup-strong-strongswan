#!/bin/sh
#    Setup Strong strongSwan server for Ubuntu and Debian
#
#    Copyright (C) 2014-2015 Phil Plückthun <phil@plckthn.me>
#    Based on Strongswan on Docker
#    https://github.com/philplckthun/docker-strongswan
#
#    This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
#    Unported License: http://creativecommons.org/licenses/by-sa/3.0/

if [ `id -u` -ne 0 ]
then
  echo "Please start this script with root privileges!"
  echo "Try again with sudo."
  exit 0
fi

#################################################################
# Variables

STRONGSWAN_TMP="/tmp/strongswan"
STRONGSWAN_VERSION="5.3.4"
#STRONGSWAN_USER
#STRONGSWAN_PSK

#################################################################
# Functions

function call() {
  eval "$@ > /dev/null 2>&1"
}

function generateKey() {
  P1=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
  P2=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
  P3=`cat /dev/urandom | tr -cd abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789 | head -c 3`
  KEY="$P1$P2$P3"
}

function bigEcho() {
  echo ""
  echo "============================================================"
  echo "$@"
  echo "============================================================"
  echo ""
}

function pacapt() {
  eval "$STRONGSWAN_TMP/pacapt $@"
}

function backupCredentials() {
  if [ -f /etc/ipsec.secrets ]; then
    cp /etc/ipsec.secrets /etc/ipsec.secrets.backup
  fi

  if [ -f /etc/ppp/l2tp-secrets ]; then
    cp /etc/ppp/l2tp-secrets /etc/ppp/l2tp-secrets.backup
  fi
}

function writeCredentials() {
  bigEcho "Saving credentials"

  cat > /etc/ipsec.secrets <<EOF
# This file holds shared secrets or RSA private keys for authentication.
# RSA private key for this host, authenticating it to any other host
# which knows the public part.  Suitable public keys, for ipsec.conf, DNS,
# or configuration of other implementations, can be extracted conveniently
# with "ipsec showhostkey".

: PSK "$STRONGSWAN_PSK"

$STRONGSWAN_USER : EAP "$STRONGSWAN_PASSWORD"
$STRONGSWAN_USER : XAUTH "$STRONGSWAN_PASSWORD"
EOF

  cat > /etc/ppp/l2tp-secrets <<EOF
# This file holds secrets for L2TP authentication.
# Username  Server  Secret  Hosts
"$STRONGSWAN_USER" "*" "$STRONGSWAN_PASSWORD" "*"
EOF
}

function getCredentials() {
  bigEcho "Querying for credentials"

  if [ "$STRONGSWAN_PSK" = "" ]; then
    echo "The VPN needs a PSK (Pre-shared key)."
    echo "Do you wish to set it yourself?"
    echo "(Otherwise a random one is generated)"
    while true; do
      read -p "" yn
      case $yn in
        [Yy]* ) echo ""; echo "Enter your preferred key:"; read -p "" STRONGSWAN_PSK; break;;
        [Nn]* ) generateKey; STRONGSWAN_PSK=KEY; break;;
        * ) echo "Please answer with Yes or No [y|n].";;
      esac
    done

    echo ""
    echo "The PSK is: '$STRONGSWAN_PSK'."
    echo ""
  fi

  #################################################################

  if [ "$STRONGSWAN_USER" = "" ]; then
    read -p "Please enter your preferred username [user]: " STRONGSWAN_USER

    if [ "$STRONGSWAN_USER" = "" ]
    then
      STRONGSWAN_USER="vpn"
    fi
  fi

  #################################################################

  if [ "$STRONGSWAN_PASSWORD" = "" ]; then
    echo "The VPN user '$STRONGSWAN_USER' needs a password."
    echo "Do you wish to set it yourself?"
    echo "(Otherwise a random one is generated)"
    while true; do
      read -p "" yn
      case $yn in
        [Yy]* ) echo ""; echo "Enter your preferred key:"; read -p "" STRONGSWAN_PASSWORD; break;;
        [Nn]* ) generateKey; STRONGSWAN_PASSWORD=KEY; break;;
        * ) echo "Please answer with Yes or No [y|n].";;
      esac
    done

    echo ""
    echo "The password is: '$STRONGSWAN_PASSWORD'."
    echo ""
  fi
}

#################################################################

echo "This script will install strongSwan on this machine."
echo "Do you wish to continue?"

while true; do
  read -p "" yn
  case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit 0;;
      * ) echo "Please answer with Yes or No [y|n].";;
  esac
done

#################################################################

# Clean up and create compilation environment
call rm -rf $STRONGSWAN_TMP
call mkdir -p $STRONGSWAN_TMP

curl -sSL "https://github.com/icy/pacapt/raw/ng/pacapt" > $STRONGSWAN_TMP/pacapt
if [ "$?" = "1" ]
then
  bigEcho "An unexpected error occured while downloading pacapt!"
  exit 0
fi

call chmod +x $STRONGSWAN_TMP/pacapt

echo ""

#################################################################

bigEcho "Installing necessary dependencies"

pacapt -S
pacapt -S make g++ gcc libgmp-dev iptables xl2tpd libssl-dev

if [ "$?" = "1" ]
then
  bigEcho "An unexpected error occured!"
  exit 0
fi

#################################################################

bigEcho "Installing StrongSwan..."

call mkdir -p $STRONGSWAN_TMP/src
curl -sSL "https://download.strongswan.org/strongswan-$STRONGSWAN_VERSION.tar.gz" | tar -zxC $STRONGSWAN_TMP/src --strip-components 1

if [ "$?" = "1" ]
then
  bigEcho "An unexpected error occured while downloading strongSwan source!"
  exit 0
fi

cd $STRONGSWAN_TMP/src
./configure --prefix=/usr --sysconfdir=/etc \
  --enable-eap-radius \
  --enable-eap-mschapv2 \
  --enable-eap-identity \
  --enable-eap-md5 \
  --enable-eap-mschapv2 \
  --enable-eap-tls \
  --enable-eap-ttls \
  --enable-eap-peap \
  --enable-eap-tnc \
  --enable-eap-dynamic \
  --enable-xauth-eap \
  --enable-openssl
make
make install

#################################################################

bigEcho "Cleaning up..."

call rm -rf $STRONGSWAN_TMP

#################################################################

bigEcho "Preparing various configuration files..."

cat > /etc/ipsec.conf <<EOF
# ipsec.conf - strongSwan IPsec configuration file

config setup
  uniqueids=no
  charondebug="cfg 2, dmn 2, ike 2, net 0"

conn %default
  dpdaction=clear
  dpddelay=300s
  rekey=no
  left=%defaultroute
  leftfirewall=yes
  right=%any
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  auto=add

#######################################
# L2TP Connections
#######################################

conn L2TP-IKEv1-PSK
  type=transport
  keyexchange=ikev1
  authby=secret
  leftprotoport=udp/l2tp
  left=%any
  right=%any
  rekey=no
  forceencaps=yes

#######################################
# Default non L2TP Connections
#######################################

conn Non-L2TP
  leftsubnet=0.0.0.0/0
  rightsubnet=10.0.0.0/24
  rightsourceip=10.0.0.0/24

#######################################
# EAP Connections
#######################################

# This detects a supported EAP method
conn IKEv2-EAP
  also=Non-L2TP
  keyexchange=ikev2
  eap_identity=%any
  rightauth=eap-dynamic

#######################################
# PSK Connections
#######################################

conn IKEv2-PSK
  also=Non-L2TP
  keyexchange=ikev2
  authby=secret

# Cisco IPSec
conn IKEv1-PSK-XAuth
  also=Non-L2TP
  keyexchange=ikev1
  leftauth=psk
  rightauth=psk
  rightauth2=xauth

EOF

cat > /etc/strongswan.conf <<EOF
# /etc/strongswan.conf - strongSwan configuration file
# strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details

charon {
  load_modular = yes
  send_vendor_id = yes
  plugins {
    include strongswan.d/charon/*.conf
    attr {
      dns = 8.8.8.8, 8.8.4.4
    }
  }
}

include strongswan.d/*.conf
EOF

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
auth file = /etc/ppp/l2tp-secrets
debug avp = yes
debug network = yes
debug state = yes
debug tunnel = yes
[lns default]
ip range = 10.1.0.2-10.1.0.254
local ip = 10.1.0.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
;ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
EOF

#################################################################

if [[ -f /etc/ipsec.secrets ]] || [[ -f /etc/ppp/l2tp-secrets ]]; then
  echo "Do you wish to replace your old credentials? (Including a backup)"

  while true; do
    read -p "" yn
    case $yn in
        [Yy]* ) backupCredentials; getCredentials; writeCredentials; break;;
        [Nn]* ) break;;
        * ) echo "Please answer with Yes or No [y|n].";;
    esac
  done
fi

#################################################################

bigEcho "Applying changes..."

iptables --table nat --append POSTROUTING --jump MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
  echo 0 > $each/accept_redirects
  echo 0 > $each/send_redirects
done

#################################################################

bigEcho "Success!\n# Don't forget to open UDP ports 1701, 4500 and 500."

sleep 2
exit 0
