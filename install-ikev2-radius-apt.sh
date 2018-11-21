#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
clear
VER=1.1.0
echo "#############################################################"
echo "# Install IKEV2 VPN for Ubuntu"
echo "# Intro: https://willnet.net"
echo "# Version:$VER"
echo "#############################################################"
echo ""

__INTERACTIVE=""
if [ -t 1 ] ; then
    __INTERACTIVE="1"
fi

__green(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;32m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}

__red(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;40m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}

__yellow(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;33m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}
# Install IKEV2
function install_ikev2(){
    rootness
    install_lib
    get_public_ip
    pre_install
    install_strongswan
    get_key
    configure_ipsec
    configure_strongswan
    configure_secrets
    configure_radius_server
    enable_ip_forward
	get_interface
    iptables_set
    service strongswan restart
    success_info
}
# Make sure only root can run our script
function rootness(){
if [[ $EUID -ne 0 ]]; then
   echo "Error:This script must be run as root!" 1>&2
   exit 1
fi
}
#install necessary lib
function install_lib(){
    apt-get -y update
    apt-get -y install curl
}
# Get IP address of the server
function get_public_ip(){
    echo "Getting public IP, Please wait a moment..."
    publicIP=`curl -s checkip.dyndns.com | cut -d' ' -f 6  | cut -d'<' -f 1`
    if [ -z $IP ]; then
        publicIP=`curl -s ifconfig.me/ip`
    fi
}
# Pre-installation settings
function pre_install(){
	echo ""
    echo "please choose the type of your server(Xen\KVM\ESXI\BareMetal: 1  ,  OpenVZ: 2):"
    read -p "your choice(1 or 2):" os_choice
    if [ "$os_choice" = "1" ]; then
        os="1"
        os_str="Xen\KVM\ESXI\BareMetal"
        else
            if [ "$os_choice" = "2" ]; then
                os="2"
                os_str="OpenVZ"
                else
                echo "wrong choice!"
                exit 1
            fi
    fi
    echo "please input the domain of your VPS:"
    read -p "domain or IP(default_value:${publicIP}):" domain
    if [ "$domain" = "" ]; then
        domain=$publicIP
    fi
    echo "please enter radius server ip address:"
    read -p "radius server ip:" radius_server
    if [ "$radius_server" = "" ]; then
        echo "you must enter an ip address!"
        exit 1
    fi
    echo "please enter radius server secret:"
    read -p "radius server secret:" radius_secret
    echo "please input the dns server 1 ip address(default is 8.8.8.8):"
    read -p "dns server 1:" dns_1
    if [ "$dns_1" = "" ]; then
        dns_1=8.8.8.8
    fi
    echo "please input the dns server 2 ip address(default is 8.8.4.4):"
    read -p "dns server 2:" dns_2
    if [ "$dns_2" = "" ]; then
        dns_2=8.8.4.4
    fi
    echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    echo "Please confirm the information:"
    echo ""
    echo -e "the type of your server: [$(__green $os_str)]"
    echo -e "the domain or IP of your server: [$(__green $domain)]"
    echo -e "the radius server: [$(__green $radius_server)]"
    echo -e "the radius server secret: [$(__green $radius_secret)]"
    echo -e "the dns server 1: [$(__green $dns_1)]"
    echo -e "the dns server 2: [$(__green $dns_2)]"
        echo -e "$(__yellow "These are the certificate you MUST be prepared:")"
        echo -e "[$(__green "ca.cert.pem")]:The CA cert or the chain cert."
        echo -e "[$(__green "server.cert.pem")]:Your server cert."
        echo -e "[$(__green "server.pem")]:Your  key of the server cert."
        echo -e "[$(__yellow "Please copy these file to the same directory of this script before start!")]"
 
    echo ""
    echo "Press any key to start...or Press Ctrl+C to cancel"
    char=`get_char`
    #Current folder
    cur_dir=`pwd`
    cd $cur_dir
}
function install_strongswan(){
    apt-get -y install strongswan libstrongswan-extra-plugins
}
# configure cert and key
function get_key(){
    cd $cur_dir
    if [ ! -d my_key ];then
        mkdir my_key
    fi
    import_cert

    echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    cp -f ca.cert.pem /etc/ipsec.d/cacerts/
    cp -f server.cert.pem /etc/ipsec.d/certs/
    cp -f server.pem /etc/ipsec.d/private/
    cp -f client.cert.pem /etc/ipsec.d/certs/
    cp -f client.pem  /etc/ipsec.d/private/
    echo "Cert copy completed"
}

# import cert if user has ssl certificate
function import_cert(){
   cd $cur_dir
   if [ -f ca.cert.pem ];then
        cp -f ca.cert.pem my_key/ca.cert.pem
        echo -e "ca.cert.pem [$(__green "found")]"
    else
        echo -e "ca.cert.pem [$(__red "Not found!")]"
        exit
    fi
    if [ -f server.cert.pem ];then
        cp -f server.cert.pem my_key/server.cert.pem
        cp -f server.cert.pem my_key/client.cert.pem
        echo -e "server.cert.pem [$(__green "found")]"
        echo -e "client.cert.pem [$(__green "auto create")]"
    else
        echo -e "server.cert.pem [$(__red "Not found!")]"
        exit
    fi
    if [ -f server.pem ];then
        cp -f server.pem my_key/server.pem
        cp -f server.pem my_key/client.pem
        echo -e "server.pem [$(__green "found")]"
        echo -e "client.pem [$(__green "auto create")]"
    else
        echo -e "server.pem [$(__red "Not found!")]"
        exit
    fi
    cd my_key
}

# configure the ipsec.conf
function configure_ipsec(){
 cat > /etc/ipsec.conf<<-EOF
config setup
    uniqueids=never 
conn ikev2
    keyexchange=ikev2
    ike=aes256-sha256-modp2048,3des-sha1-modp2048,aes256-sha1-modp2048!
    esp=aes256-sha256,3des-sha1,aes256-sha1!
    rekey=no
    left=%defaultroute
    leftid=${domain}
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=eap-radius
    #rightauth=eap-mschapv2
    rightsourceip=10.31.0.0/24
    rightsendcert=never
    eap_identity=%identity
    dpdaction=clear
    fragmentation=yes
    auto=add
EOF
}

# configure the strongswan.conf
function configure_strongswan(){
 cat > /etc/strongswan.conf<<-EOF
 charon {
        load_modular = yes
        duplicheck.enable = no
        compress = yes
        plugins {
                include strongswan.d/charon/*.conf
        }
        dns1 = ${dns_1}
        dns2 = ${dns_2}
        nbns1 = 8.8.8.8
        nbns2 = 8.8.4.4
}
include strongswan.d/*.conf
EOF
}

# configure the ipsec.secrets
function configure_secrets(){
    cat > /etc/ipsec.secrets<<-EOF
: RSA server.pem
#: PSK "myPSKkey"
#: XAUTH "myXAUTHPass"
username : EAP "password"
EOF
}

# configure the eap-radius.conf
function configure_radius_server(){
    cat > /etc/strongswan.d/charon/eap-radius.conf<<-EOF
eap-radius {
    load = yes
    dae {
    }
    forward {
    }
    servers {
            server_a {
                            address = ${radius_server}
                            secret = ${radius_secret}
                            }
    }
    xauth {
    }
}
EOF
}

function SNAT_set(){
    echo "Use SNAT could implove the speed,but your server MUST have static ip address."
    read -p "yes or no?(default_value:no):" use_SNAT
    if [ "$use_SNAT" = "yes" ]; then
        use_SNAT_str="1"
        echo -e "$(__yellow "ip address info:")"
        ip address | grep inet
        echo "Some servers has elastic IP (AWS) or mapping IP.In this case,you should input the IP address which is binding in network interface."
        read -p "static ip or network interface ip (default_value:${local_ip}):" static_ip
    if [ "$static_ip" = "" ]; then
        static_ip=$local_ip
    fi
    else
        use_SNAT_str="0"
    fi
}
function get_interface(){
	interface=`ip route | grep default | awk -F"[ ]" '{print $5}'`
	local_ip=`ip address |grep inet|grep $interface |awk  -F"[ /]" '{print $6}'`
}


# iptables check
function enable_ip_forward(){
    cat > /etc/sysctl.d/10-ipsec.conf<<-EOF
net.ipv4.ip_forward=1
EOF
    sysctl --system
}

# iptables set
function iptables_set(){
    echo "Use SNAT could improve the speed,but your server MUST have static ip address."
    read -p "yes or no?(default_value:no):" use_SNAT
    if [ "$use_SNAT" = "yes" ]; then
        use_SNAT_str="1"
        echo -e "$(__yellow "ip address info:")"
        ip address | grep inet
        echo "Some servers has elastic IP (AWS) or mapping IP.In this case,you should input the IP address which is binding in network interface."
        read -p "static ip or network interface ip (default_value:${local_ip}):" static_ip
    if [ "$static_ip" = "" ]; then
        static_ip=$local_ip
    fi
    else
        use_SNAT_str="0"
    fi
    echo "[$(__yellow "Important")]Please enter the name of the interface which can be connected to the public network."
    if [ "$os" = "1" ]; then   
        read -p "Network card interface(default_value:${interface}):" input_interface
        if [ "$input_interface" = "" ]; then
            input_interface=$interface
        fi
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -s 10.31.0.0/24  -j ACCEPT
        iptables -A INPUT -i $input_interface -p esp -j ACCEPT
        iptables -A INPUT -i $input_interface -p udp --dport 500 -j ACCEPT
        iptables -A INPUT -i $input_interface -p udp --dport 4500 -j ACCEPT
        #iptables -A FORWARD -j REJECT
        if [ "$use_SNAT_str" = "1" ]; then
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $input_interface -j SNAT --to-source $static_ip
        else
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $input_interface -j MASQUERADE
        fi
   else
        read -p "Network card interface(default_value:venet0):" input_interface
        if [ "$input_interface" = "" ]; then
            input_interface="venet0"
        fi
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -s 10.31.0.0/24  -j ACCEPT
        iptables -A INPUT -i $input_interface -p esp -j ACCEPT
        iptables -A INPUT -i $input_interface -p udp --dport 500 -j ACCEPT
        iptables -A INPUT -i $input_interface -p udp --dport 4500 -j ACCEPT
        #iptables -A FORWARD -j REJECT
        if [ "$use_SNAT_str" = "1" ]; then
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $input_interface -j SNAT --to-source $static_ip
        else
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $input_interface -j MASQUERADE
        fi           
    fi
        iptables-save > /etc/iptables.rules
        cat > /etc/network/if-up.d/iptables<<-EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
        chmod +x /etc/network/if-up.d/iptables
        mkdir -p /etc/networkd-dispatcher/routable.d
        cp /etc/network/if-up.d/iptables /etc/networkd-dispatcher/routable.d/iptables
}
# echo the success info
function success_info(){
    echo "#############################################################"
    echo -e "# [$(__green "Install Complete")]"
    echo -e "#############################################################"
    echo -e ""
}

# Initialization step
install_ikev2
