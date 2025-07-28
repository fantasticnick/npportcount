#!/bin/bash

#Exit immediately if any command fails.
set -e

#Ensure the script is run as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root / Пожалуйста, запустите от root"
  exit 1
fi

#Create secure working directory
mkdir -p /etc/npportcount
chmod 700 /etc/npportcount

#Install required packages (iptables, ip6tables, cron)
apt-get update
apt-get install -y iptables ip6tables cron

#Prompt for port(s)
read -p "Enter port or port range (example: 80 or 8000:8100): " PORTSPEC

#Define protocols
PROTOS=("tcp" "udp")

#Setup IPv4/IPv6 chains and rules
for IPVER in 4 6; do
  if [[ "$IPVER" == "4" ]]; then
    IPT="iptables"
  else
    IPT="ip6tables"
  fi

  $IPT -N NPPORTCOUNT || true
  for proto in "${PROTOS[@]}"; do
    $IPT -A INPUT -p "$proto" --dport "$PORTSPEC" -j NPPORTCOUNT || true
    $IPT -A OUTPUT -p "$proto" --sport "$PORTSPEC" -j NPPORTCOUNT || true
  done
done

#Create daily cron job for logging
cat > /etc/npportcount/log.sh << 'EOF'
#!/bin/bash
DATE=$(date +"%Y-%m-%d %H:%M:%S")
echo "=== $DATE ===" >> /var/log/npportcount.log
for IPVER in 4 6; do
  if [[ "$IPVER" == "4" ]]; then
    IPT="iptables"
  else
    IPT="ip6tables"
  fi
  echo "IPv$IPVER:" >> /var/log/npportcount.log
  $IPT -L NPPORTCOUNT -v -x >> /var/log/npportcount.log
done
echo >> /var/log/npportcount.log
EOF

chmod 700 /etc/npportcount/log.sh

#Uninstall script
cat > /etc/npportcount/uninstall.sh << 'EOF'
#!/bin/bash

#Exit on any error
set -e

#Check for root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

#Define protocols and IP versions
PROTOS=("tcp" "udp")

#Remove iptables and ip6tables rules
for IPVER in 4 6; do
  if [[ "$IPVER" == "4" ]]; then
    IPT="iptables"
  else
    IPT="ip6tables"
  fi

  #Removing rules INPUT/OUTPUT
  for proto in "${PROTOS[@]}"; do
    $IPT -D INPUT -p "$proto" -j NPPORTCOUNT 2>/dev/null || true
    $IPT -D OUTPUT -p "$proto" -j NPPORTCOUNT 2>/dev/null || true
  done

  #Removing NPPORTCOUNT
  $IPT -F NPPORTCOUNT 2>/dev/null || true
  $IPT -X NPPORTCOUNT 2>/dev/null || true
done

#Remove cron job
crontab -l 2>/dev/null | grep -v "/etc/npportcount/log.sh" | crontab -

#Remove script and directory
rm -rf /etc/npportcount

echo "npportcount has been fully removed."
echo "Manual cleanup (optional): /var/log/npportcount.log"
EOF

chmod 700 /etc/npportcount/uninstall.sh

#Register cron job (once per day at 00:30)
(crontab -l 2>/dev/null; echo "30 0 * * * /etc/npportcount/log.sh") | crontab -

echo "Installation complete."
echo "Log: /var/log/npportcount.log"
