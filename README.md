# clientvpn-cli

This script is meant to serve as a helper for the AWS Client VPN service. It makes it easy to manage certificates and update client configuration files for use with the service.

## Goals
* Make the maintenance of a local PKI easy!
* Generate root CA, server, and client certificates with simple CLI commands and guided input prompts
* Easily upload server and client certificates to Amazon Certificate Manager
* Append client certificate and private key to client configuration files when mutual authentication is used.

## Dependencies
* git
* [EasyRSA](https://github.com/OpenVPN/easy-rsa) (and OpenSSL by proxy)
* AWS CLI

## Options
* **--build-pki**: checks if EasyRSA is installed and builds your PKI. You can also issue this option to destroy and recreate your PKI.
* **--build-server**: Build a server certificate and private key. You can optionally run this command first and skip --build-pki.
* **--build-client**: Build a client certificate and private key. You can optionally run this command first and skip --build-pki.
* **--upload-cert**: Upload your client and server certificates to ACM from the command line. 
* **--download-config**: Download client configuration file from AWS.
* **--update-config**: Run this option to update your client configuration file with the necessary OpenVPN directives for mutual authentication.

## Getting Started

### Script setup
This script assumes that you have a default EasyRSA installation in the home directory for the user calling the script. If you don't the script can install it for you. 

Please note the other dependencies above. git is used to install EasyRSA and AWS CLI is used for any actions that require interaction with AWS APIs. Please ensure that you have both installed and configured on your system.

There is one modifiable variable, CONFDIR, in the script file. You can choose to place your downloaded configuration files in a different directory than you user's HOME directory. 

Take care to omit the trailing forward slash (/) from your directory if changing the CONFDIR variable. Some aspects of the script will not work if it's included. 

### Building a PKI
You can issue `--build-pki`, `--build-server`, or `--build-client` as your first command to build your PKI. `--build-server` or `--build-client` will additionally set up a server or client certificate and private key, respectively, after setting up the PKI.

If your system does not have EasyRSA installed, you can choose to have this script install it for you. You will be prompted with options to specify while your PKI is created, such as whether or not you want your private keys to be encrypted and what you'd like to name the files that are created.

Example order of operations:
```bash
./clientvpn-cli --build-pki
./clientvpn-cli --build-server
./clientvpn-cli --build-client
```
--OR--

```bash
./clientvpn-cli --build-server
./clientvpn-cli --build-client
```
NOTE: Running `--build-pki` after having created a PKI on your system will destroy and recreate your entire PKI, including certs and keys located in the default directories. EasyRSA will prompt you before destroying the existing PKI, but use this option with caution.

### Uploading your certificates to Amazon Certificate Manager (ACM)
Run with `--upload-cert` to upload your client and/or server certificate(s) to ACM. You will be prompted asking that name of the certificate you'd like to upload

### Downloading your client configuration file from AWS
Run with `--download-config` to download your client configuration file from AWS. You will be prompted with which Client VPN endpoint you'd like to download the configuration for.

### Appending mutual authentication parameters to the client configuration file
Run with `--update-config` to append your client certificate and private key to the .ovpn configuration file. Ensure to omit the file extension ".ovpn" or the script will not be able to locate the file.
