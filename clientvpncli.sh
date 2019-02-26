#!/bin/bash

set -eC

##########################################################################################################################
# Change the variable below to reflect the directory where you're storing your OpenVPN client configuration files.       #
# This script assumes your home directory by default.                                                                    #
##########################################################################################################################
CONFDIR="$HOME"

##########################################################################################
# Changing the below variables will effectively break the functionality of the script.   #
# This script assumes a default installation of EasyRSA. Change at your own risk!        #
##########################################################################################
FILE="$HOME/easy-rsa/easyrsa3/easyrsa"
PKI="$HOME/easy-rsa/easyrsa3/pki/ca.crt"
PRIVATE="$HOME/easy-rsa/easyrsa3/pki/private/"
ISSUED="$HOME/easy-rsa/easyrsa3/pki/issued/"
AWS="$HOME/.aws/credentials"
easyrsa="cd $HOME/easy-rsa/easyrsa3"

check_easyrsa_install () {
#Ensure EasyRSA is in the user's home directory. If it's not, install it.
if [ -e "$FILE" ]; then
        echo "$FILE found."
else
        read -p "$FILE not found... would you like me to install EasyRSA in $HOME? (Y/N) " answer
	
	case $answer in
		Y|y)
			install_easyrsa
                        ;;
                N|n)
			echo "Please install the latest version of EasyRSA using git."
			exit 1
                        ;;
                *)
                        echo >&2 "Input \""$answer"\" not recognized. Aborting."
                        exit 1
                        ;;
	esac
fi
}

install_easyrsa () {
	#Ensure we're in the home directory
	cd $HOME
	
	#Check if git is installed. If it is, proceed with installation
	if [ -x "$(command -v git)" ]; then
		echo "git is installed. Proceeding with installation!"
		git clone https://github.com/OpenVPN/easy-rsa.git
	else
		echo >&2 "This script depends on git. Please install git using your distribution's package manager."
		exit 1
	fi
}

check_pki () {
	#Check if root CA certificate exists
	if [ -e $PKI ]; then
		echo "Root CA certificate exists. Continuing."
	#If it doesn't, initialize the PKI
	else
		echo >&2 "Root CA doesn't exist. Creating PKI!"
		check_easyrsa_install
		build_pki
	fi
}

build_pki () {
	#Switch to EasyRSA directory
	$easyrsa

	#Read input for private key encryption
	read -p "Would you like your root CA's private key to be encrypted? (Y/N) " answer

	#Initialize PKI and root CA. Decide whether or not to encrypt the CA's private key
	case $answer in
		Y|y)
			./easyrsa init-pki
			./easyrsa build-ca
			;;
		N|n)
			./easyrsa init-pki
			./easyrsa build-ca nopass
			;;
		*)
			echo >&2 "Input \""$answer"\" not recognized. Aborting."
			exit 1
			;;
	esac
}

build_server () {
	#Read input for server name and private key encryption
	read -p "Enter the name for your server: " server
	read -p "Would you like your server's private key to be encrypted? Note that encrypted keys cannot be uploaded to ACM. (Y/N) " answer
	
	#Switch to EasyRSA directory and build a server cert & key based on above answer
	$easyrsa

	case $answer in
                Y|y)
                        ./easyrsa build-server-full "$server"
                        ;;
                N|n)
                        ./easyrsa build-server-full "$server" nopass
                        ;;
                *)
                        echo >&2 "Input \""$answer"\" not recognized. Aborting."
                        exit 1
                        ;;
        esac
}

build_client () {
        #Read input for client name and private key encryption
        read -p "Enter the name for your client: " client
        read -p "Would you like your client's private key to be encrypted? Note that encrypted keys cannot be uploaded to ACM. (Y/N) " answer

        #Switch to EasyRSA directory and build a client cert & key based on above answer
        $easyrsa

        case $answer in
                Y|y)
                        ./easyrsa build-client-full "$client"
                        ;;
                N|n)
                        ./easyrsa build-client-full "$client" nopass
                        ;;
                *)
                        echo >&2 "Input \""$answer"\" not recognized. Aborting."
                        exit 1
                        ;;
        esac
}

update_config () {
	#Prompt user with $CONFDIR contents
	printf "\nContents of your configuration directory:\n----------"
	ls -l $CONFDIR | awk '{print $10}'
	printf "\n"

	#Read input for config filename and check if it exists
	read -p "Enter the name of your configuration file (omit .ovpn): " config
	check_config "$config"

	#Prompt user with $ISSUED contents
	printf "\nContents of your issued certificates directory:\n----------"
	ls -l $ISSUED | awk '{print $10}'
	printf "\n"

	#Read input for client name
        read -p "Enter the name of your client (omit .crt): " client
	
	#Pass values to function
	mutual_auth "$config" "$client"
	
}

check_config () {
	#Check if config file exists in home directory
	if [ -e "${CONFDIR}/${1}".ovpn ]; then
        	echo "${CONFDIR}/${1}.ovpn found."
	else
        	echo >&2 "${1}.ovpn not found in ${CONFDIR}. Aborting."
		exit 1
	fi
}

mutual_auth () {
	#Check if the certificate and private key exist. Append values to the client config file. 
	if [[ -e ${ISSUED}${2}.crt && -e ${PRIVATE}${2}.key ]]; then
		cert="$(openssl x509 -in ${ISSUED}${2}.crt -outform PEM)"
		key="$(cat ${PRIVATE}${2}.key)"
		printf "<cert>\n$cert\n</cert>\n<key>\n$key\n</key>\n" >> ${CONFDIR}/${1}.ovpn
		echo "Certificate and private key appended to ${CONFDIR}/${1}.ovpn"
	else
		echo >&2 "Certificate and private key named \""${2}"\" do not exist."
		exit 1
	fi	
}

check_aws () {
	#Check if AWS credentials exist
	if [ -e $AWS ]; then
		echo "AWS credentials file exists! Continuing."
	else
		echo "AWS credentials file does not exist. Please download AWS CLI and/or run 'aws configure'"
		exit 1
	fi
}

upload_cert () {
	#Ensure AWS CLI is installed
	check_aws

	#Prompt user with $ISSUED contents
        printf "\nContents of your issued certificates directory:\n----------"
        ls -l $ISSUED | awk '{print $10}'
	printf "\n"

	#Read input for cert filename and check if it exists
	read -p "Enter the name of the certificate you would like to upload (omit .crt): " cert

	#Which region should we upload the cert to?
	read -p "Which region would you like to upload the certificate to (e.g. us-east-1)? " region

	if [[ -e ${ISSUED}${cert}.crt && -e ${PRIVATE}${cert}.key ]]; then
		aws acm import-certificate --certificate file://"${ISSUED}${cert}".crt --private-key file://"${PRIVATE}${cert}".key --certificate-chain file://"${PKI}" --region "$region" --output table
	else
		echo >&2 "Certificate and private key named \""${cert}"\" do not exist."
		exit 1
	fi
}

download_config () {
	#Ensure AWS CLI is installed
	check_aws

	#List available CVPN endpoints
	read -p "Enter the region where your Client VPN endpoint is located: " region
	printf "\nAvailable Endpoints:\n\nEndpoint ID\t\t\t\tCIDR Range\n------\t\t\t\t\t------\n"
	aws ec2 describe-client-vpn-endpoints --region "$region" --output text | awk '/CLIENTVPNENDPOINTS/ {print $3,"\t",$2,"\t";}'
	printf "\n"

	#Read input for CVPN endpoint ID
	read -p "Enter your Client VPN endpoint ID: " id
	
	#Read the name for the config file
	read -p "Enter the name for your client configuration file: " config
	
	#Ensure AWS CLI is installed and make the API call to download the config
	aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id "${id}" --output text>"${CONFDIR}/${config}".ovpn --region "$region"

	#Decide whether or not the above operation succeeded
	if [ $? -eq 0 ]; then
		echo "Configuration successfully saved to ${CONFDIR}/${config}.ovpn"
	else
		echo "An error occured. Exiting."
		exit 1
	fi
}

# Main execution starts here
if [[ $# -eq 1 ]]; then

	case ${1} in
		--build-pki)
			check_easyrsa_install
                	build_pki
                	;;
		--build-server)
			check_pki
			build_server
			;;
		--build-client)
			check_pki
			build_client
			;;
		--upload-cert)
			upload_cert
			;;
		--update-config)
			update_config
			;;
		--download-config)
			download_config
			;;
		*)
			echo "${0}: Unknown argument \""${1}"\"" >&2
			;;
	esac
else
	echo >&2 "Invalid number of arguments passed."
fi	
