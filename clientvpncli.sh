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
	#Check if AWS binary exists/is executable
	if [ -x "$(command -v aws)" ]; then
        :
	else
		echo "AWS binary file does not exist. Please download AWS CLI."
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
		aws acm import-certificate --certificate file://"${ISSUED}${cert}".crt --private-key file://"${PRIVATE}${cert}".key \
                --certificate-chain file://"${PKI}" --region "$region" --output table
	else
		echo >&2 "Certificate and private key named \""${cert}"\" do not exist."
		exit 1
	fi
}

download_config () {
	#Ensure AWS CLI is installed
	check_aws

	#List available CVPN endpoints
    read -p "Enter the region where your Client VPN endpoint is located (e.g. us-east-1): " region
	aws ec2 describe-client-vpn-endpoints --region "$region" --query \
            ClientVpnEndpoints[].'{Description:Description,EndpointID:ClientVpnEndpointId,ClientCIDR:ClientCidrBlock}' --output table
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

create_endpoint() {
    #Ensure AWS CLI is installed
    check_aws

    #Read inputs from user and create the endpoint
    read -p "Enter a description for your Client VPN endpoint: " desc
    read -p "Would you like your endpoint to use TCP or UDP for transport? (T/U) " proto
    
    #Set proto
    case ${proto} in
            T|t)
                protocol="tcp"
                ;;
            U|u)
                protocol="udp"
                ;;
            *)
                echo >&2 "Input \""${proto}"\" not recognized. Aborting."
                exit 1
                ;;
    esac

    read -p "Enter your Client CIDR block (e.g. 192.168.0.0/16): " cidr
    read -p "Enter the region you would like to create your Client VPN endpoint in (e.g. us-east-1): " region
    aws acm list-certificates --output table --region "$region"
    printf "\n"
    read -p "Please select a server certificate ARN from the above list: " server
    read -p "Would you like to use mutual authentication? (Y/N) " mutual

    #Set initial API call
    command="aws ec2 create-client-vpn-endpoint --description ${desc} --transport-protocol "${protocol}" --client-cidr-block "${cidr}" \
            --server-certificate-arn "${server}" --output table"
    
    #Case statement for above decision
    case ${mutual} in
        Y|y)
            aws acm list-certificates --output table --region "$region"
            printf "\n"
            read -p "Please select a client certificate ARN from the above list: " client
            ;;
        N|n)
            ;;
        *)
            echo >&2 "Input \""${mutual}"\" not recognized. Aborting."
            exit 1
            ;;
    esac

    read -p "Would you like to use Active Directory authentication? (Y/N) " ad

    #Case statement for above decision
    case ${ad} in
        Y|y)
            aws ds describe-directories --output table --query \
                    DirectoryDescriptions[].'{Description:Description,ID:DirectoryId,Name:Name,Type:Type,VPC:VpcSettings.VpcId}' --region "$region"
            printf "\n"
            read -p "Please select a directory ID from the above: " dir
            ;;
        N|n)
            ;;
        *)
            echo >&2 "Input \""${ad}"\" not recognized. Aborting."
            exit 1
            ;;
    esac

    #Decision whether or not a form of authentication was specified
    if [[ "${mutual}" == 'n' || "${mutual}" == 'N' ]] && [[ "${ad}" == 'n' || "${ad}" == 'N' ]]; then
        echo >&2 "At least one form of authentication must be specified. Aborting."
        exit 1
    elif [[ "${mutual}" == 'n' || "${mutual}" == 'N' ]] && [[ "${ad}" == 'y' ||  "${ad}" == 'Y' ]]; then
        command=""${command}" --authentication-options Type=directory-service-authentication,ActiveDirectory={DirectoryId="${dir}"}"
    elif [[ "${mutual}" == 'y' || "${mutual}" == 'Y' ]] && [[ "${ad}" == 'n' || "${ad}" == 'N' ]]; then
        command=""${command}" --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn="${client}"}"
    else
        command=""${command}" --authentication-options Type=directory-service-authentication,ActiveDirectory={DirectoryId="${dir}"} \
                Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn="${client}"}"
    fi

    read -p "Would you like to enable CloudWatch Logs? (Y/N) " logs

    #Case statement for above decision
    case ${logs} in
        Y|y)
            aws logs describe-log-groups --output table --query logGroups[].'{Name:logGroupName}' --region "$region"
            printf "\n"
            read -p "Please select a log group from the above list: " group
            aws logs describe-log-streams --log-group-name "${group}" --output table --query logStreams[].'{Name:logStreamName}' --region "$region"
            printf "\n"
            read -p "Please select a log stream from the above list: " stream
            command=""${command}" --connection-log-options Enabled=true,CloudwatchLogGroup="${group}",CloudwatchLogStream="${stream}""
            ;;
        N|n)
            command=""${command}" --connection-log-options Enabled=false"
            ;;
        *)
            echo >&2 "Input \""${logs}"\" not recognized. Aborting."
            exit 1
            ;;
    esac
    
    read -p "Would you like to use custom DNS servers? (Y/N) " dns

    case ${dns} in
        Y|y)
            read -p "DNS server 1: " dns1
            read -p "DNS server 2: " dns2
            command=""${command}" --dns-servers "${dns1}" "${dns2}""
            ;;
        N|n)
            ;;
        *)
            echo >&2 "Input \""${dns}"\" not recognized. Aborting."
            exit 1
            ;;
    esac
    
    $command
}

associate_subnet() {
    # Takes in user input and associates specified subnets to a CVPN endpoint
    check_aws
    read -p "Please enter the region where your Client VPN endpoint resides (e.g. us-east-1) " region
    aws ec2 describe-client-vpn-endpoints --region "$region" --query \
            ClientVpnEndpoints[].'{Description:Description,EndpointID:ClientVpnEndpointId,ClientCIDR:ClientCidrBlock}' --output table
    printf "\n"
    read -p "Please choose your Client VPN endpoint: " endpoint
    
    bool=true
    while [ "$bool" = true ]; do
        aws ec2 describe-subnets --region "$region" --query \
                Subnets[].'{SubnetID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,VPC:VpcId}' --output table
        printf "\n"
        read -p "Please choose the subnet ID you would like to associate: " subnet
        aws ec2 associate-client-vpn-target-network --client-vpn-endpoint-id "$endpoint" --subnet-id "$subnet" --region "$region" --output table
        printf "\n"
        read -p "Would you like to associate another subnet? (Y/N) " answer
        case ${answer} in
            Y|y)
                ;;
            N|n)
                bool=false
                ;;
            *)
                echo >&2 "Input \""${answer}"\" not recognized. Aborting."
                exit 1
                ;;
        esac
    done         
}

authorize_ingress() {
    # Authorize network CIDRs
    check_aws
    read -p "Please enter the region where your Client VPN endpoint resides (e.g. us-east-1) " region
    aws ec2 describe-client-vpn-endpoints --region "$region" --query \
        ClientVpnEndpoints[].'{Description:Description,EndpointID:ClientVpnEndpointId,ClientCIDR:ClientCidrBlock}' --output table
    printf "\n"
    read -p "Please choose your Client VPN endpoint: " endpoint
    
    bool=true
    while [ "$bool" = true ]; do
        read -p "Please enter a destination CIDR to authorize (e.g. 192.168.0.0/16) " cidr
        read -p "Will you be authorizing only for a specific Active Directory group? (Y/N) " ad
        
        case ${ad} in
            Y|y)
                read -p "Enter the ID of the Active Directory group: " id
                aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id "$endpoint" --target-network-cidr "$cidr" --access-group-id "$id" \
                        --region "$region" --output table
                ;;
            N|n)
                aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id "$endpoint" --target-network-cidr "$cidr" --region "$region" \
                    --authorize-all-groups --output table
                ;;
            *)
                echo >&2 "Input \""${ad}"\" not recognized. Aborting."
                exit 1
                ;;

        esac

        read -p "Would you like to authorize another network? (Y/N) " answer

        case ${answer} in
            Y|y)
                ;;
            N|n)
                bool=false
                ;;
            *)
                echo >&2 "Input \""${answer}"\" not recognized. Aborting."
                exit 1
                ;;
        esac
    done
}

create_route() {
    # Takes in input parameters and creates a route in the specified CVPN route table
    check_aws
    read -p "Please enter the region where your Client VPN endpoint resides (e.g. us-east-1) " region
    aws ec2 describe-client-vpn-endpoints --region "$region" --query \
        ClientVpnEndpoints[].'{Description:Description,EndpointID:ClientVpnEndpointId,ClientCIDR:ClientCidrBlock}' --output table
    printf "\n"
    read -p "Please choose your Client VPN endpoint: " endpoint

    bool=true
    while [ "$bool" = true ]; do
        read -p "Please enter a destination CIDR to add to your route table (e.g. 192.168.0.0/16) " cidr
        aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$endpoint" --region "$region" --query \
            ClientVpnTargetNetworks[].'{EndpointID:ClientVpnEndpointId,SubnetID:TargetNetworkId,VPC:VpcId,Status:Status.Code}' --output table
        printf "\n"
        read -p "Please choose the subnet ID for the target of your route entry: " subnet
        aws ec2 create-client-vpn-route --client-vpn-endpoint-id "$endpoint" --region "$region" --destination-cidr-block "$cidr" --target-vpc-subnet-id "$subnet" --output table
        printf "\n"
        read -p "Would you like to add an additional route? (Y/N) " answer

        case ${answer} in
            Y|y)
                ;;
            N|n)
                bool=false
                ;;
            *)
                echo >&2 "Input \""${answer}"\" not recognized. Aborting."
                exit 1
                ;;
        esac
    done
}


# Main execution starts here
if [ $# -eq 1 ]; then

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
        --create-endpoint)
            create_endpoint
            ;;
        --associate-subnet)
            associate_subnet
            ;;
        --authorize-ingress)
            authorize_ingress
            ;;
        --create-route)
            create_route
            ;;
        *)
            echo "${0}: Unknown argument \""${1}"\"" >&2
            ;;
    esac
else 
    echo >&2 "Invalid number of arguments passed."
fi	
