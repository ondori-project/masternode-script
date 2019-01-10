#!/bin/bash

CONFIG_FILE='rstr.conf'
CONFIGFOLDER='/root/.RSTRCore'

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}

function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=22619
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Ondori Masternode Private Key${NC}. Leave it blank and press ENTER to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  rstrd -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep rstrd)" ]; then
   echo -e "${RED}Ondori server could not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$(rstr-cli masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 30
    COINKEY=$(rstr-cli masternode genkey)
  fi
  rstr-cli stop
  echo "Waiting for rstrd/rstr-cli processes to exit..."
  killall rstr-cli
  killall -w rstrd 
fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
masternodeaddr=$NODEIP:22620
externalip=$NODEIP:22620
masternodeprivkey=$COINKEY
EOF
}

function important_information() {
 echo -e "================================================================================================================================"
 echo -e "Ondori Masternode is up and running listening on port ${RED}22620${NC}."
 echo -e "Configuration file is: ${RED}/root/.RSTRCore/rstr.conf${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:22620${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 echo -e "Use ${RED}rstr-cli getinfo${NC} to check your connections and ${RED}rstr-cli masternode status${NC} to check your Masternode status."
 echo -e "${GREEN}Wait for connections before starting the masternode in your local wallet!${NC}"
 echo -e "================================================================================================================================"
}


function install_dep() {
echo "Ondori (RSTR) Masternode Installation Started."
echo "Installing Dependencies..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install nano htop git -y
sudo apt-get install software-properties-common -y
sudo apt-get install build-essential libtool autotools-dev pkg-config libssl-dev -y
sudo apt-get install libboost-all-dev libminiupnpc-dev -y
sudo apt-get install autoconf automake -y
sudo add-apt-repository ppa:bitcoin/bitcoin -y
sudo apt-get update
sudo apt-get install libdb4.8-dev libdb4.8++-dev -y
sudo apt-get install build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils -y
}

function create_swap() {
 echo -e "Checking if swap space is needed."
 PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
 SWAP=$(swapon -s)
 if [[ "$PHYMEM" -lt "2"  &&  -z "$SWAP" ]]
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM without SWAP, creating 2G swap file.${NC}"
    SWAPFILE=$(mktemp)
    dd if=/dev/zero of=$SWAPFILE bs=1024 count=2M
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon -a $SWAPFILE
 else
  echo -e "${GREEN}The server running with at least 2G of RAM, or a SWAP file is already in place.${NC}"
 fi
 clear
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow 22620/tcp comment "rstr masternode port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function install_rstr() {
echo "Cloning GitHub..."
sudo git clone https://github.com/ondori-project/rstr.git
cd rstr
echo "Autogen & Configuring..."
sudo ./autogen.sh
sudo ./configure --disable-tests --disable-gui-tests
echo "Compiling & Installing..."
sudo make && sudo make install
}

function start_node() {
echo "Starting your Ondori Masternode..."
rstrd -daemon
}

function add_cron() {
read -p "Would you like to add a cronjob? (y/n) [Note: if you plan to run multiple masternodes on one VPS via IPv6, enter n]" askcron
if [ $askcron = 'n' ] || [ $askcron = 'no' ] || [ $askcron = 'N' ] || [ $askcron = 'No' ]; then
	important_information
	exit
fi
echo "Adding & Configuring Cron..."
username=`id -un`
if [ -f /etc/rc.local ]; then
	read -p "The file /etc/rc.local already exists and will be replaced. Do you agree? [y/n]" cont
	if [ $cont = 'y' ] || [ $cont = 'yes' ] || [ $cont = 'Y' ] || [ $cont = 'Yes' ]; then
		sudo rm -f /etc/rc.local
	fi
fi
echo "#!/bin/bash" > ~/rc.local
echo "sleep 1" >> ~/rc.local
echo "sudo -u $username -H /home/$username/rstrd -daemon" >> ~/rc.local
echo "exit 0" >> ~/rc.local
chmod +x ~/rc.local
sudo mv ~/rc.local /etc/rc.local
}

###Main###
clear


install_dep
create_swap
create_config
install_rstr
get_ip
create_key
update_config
enable_firewall
start_node
add_cron
important_information