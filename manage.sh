#!/bin/bash
#

CA_KEY_FILE = "jcca.key"
CA_CRT_FILE = "jcca.crt"

function requirements() {
    which yubico-piv-tool > /dev/null
    if [[ $? -gt 0  ]]; then
        echo "Missing dependency - yubico-piv-tool"
        echo "sudo apt install yubico-piv-tool"
        exit
    fi

    which ykman > /dev/null
    if [[ $? -gt 0  ]]; then
        echo "Missing dependency - ykman"
        echo "sudo apt install ykman"
        exit
    fi
}

function warning() {
    echo "This will create new current yubikey"
    echo "Press ENTER to continue, CTRL-C to cancel"
    read enter
}

function fullreset() {
    echo "This will reset FIDO, U2F, PIV, OTP, existing certificate, private key and pins!"
    echo "Press ENTER to continue or CTRL-C to cancel"
    read enter

    ykman piv reset -f
    ykman fido reset -f 
    ykman otp delete -f 1 
    ykman otp delete -f 2 
}

function pivinit() {
    echo "This will reset existing certificate, private key and pins!"
    echo "This will not reset FIDO"
    echo "Press ENTER to continue or CTRL-C to cancel"
    read enter

    echo "No spaces or special characters"
    read -p "Enter username (firstname.lastname): " name
    if [ -z $name ]; then
        echo "Username not provided"
        exit
    fi

    ykman piv reset -f    

    pin=`shuf --random-source=/dev/urandom -i 0-9 -r -n 6 | paste -sd ''`
    puk=`shuf --random-source=/dev/urandom -i 0-9 -r -n 8 | paste -sd ''`

    echo "[*] Generating private key for user $name"
    ykman piv keys generate -a ECCP384 -P 123456 9a $name.pub

    makecsr "123456"
    makecert
    importcert
    log 

    echo "[*] Setting random PIN & PUK codes"
    yubico-piv-tool -v -a change-pin --pin=123456 --new-pin=$pin
    yubico-piv-tool -v -a change-puk --pin=12345678 --new-pin=$puk

    echo ""
    echo "=============================="
    echo ""
    echo "PIN: $pin"
    echo "PUK: $puk"

    echo "These codes are not saved"
    echo "Press ENTER to continue"
    read enter
}

function log(){
    mkdir -p certificates
    mkdir -p logs

    # yubikey log
    yserial=$(ykman info |grep Serial | awk '{print $3}');
    pivserial=$(ykman piv info |grep Serial | awk '{print $2}')
    d=$(date +"%Y-%m-%d")
    t=$(date +"%H:%M:%S")
    if [ ! -f logs/yubikey.log ]; then
        echo "Date,Time,CommonName,YubikeySerial,CertificateSerial" > logs/yubikey.log
    fi

    echo "$d,$t,$name,$yserial,$pivserial" >> logs/yubikey.log

    # certificate log
    timestamp=$(date +"%Y_%m_%d_%H_%M_%S")
    mv $name.pem certificates/$timestamp-$name.pem
    mv $name.pub certificates/$timestamp-$name.pub
    rm $name.csr
}

function renewonly() {
    echo "This will reset existing certificate"
    echo "Press ENTER to continue or CTRL-C to cancel"
    read enter

    read -p "Enter username (firstname.lastname): " name
    if [ -z $name ]; then
        echo "Username not provided"
        exit
    fi

    read -p "Enter existing PIN: " pin
    if [ -z $pin ]; then
        echo "PIN not provided"
        exit
    fi

    yubico-piv-tool -a verify-pin --pin=$pin
    if [ $? -ne 0  ]; then
        echo "Wrong PIN"
        exit
    fi

    makecsr $pin
    makecert
    importcert
    log

    echo "Press enter"
    read kala
}

function makecsr() {
    echo "[*] Generating CSR for user $name"
    ykman piv keys export  9a $name.pub
    ykman piv certificates request 9a $name.pub $name.csr -a SHA512 --subject="CN=$name" --pin $1
}

function importcert(){
    echo "[*] Import into yubikey"
    ykman piv certificates import 9a $name.pem
}

function makecert(){
    echo "[*] Sign with CA key"
    openssl x509 -req -days 365 -in $name.csr -out $name.pem -CA $CA_CRT_FILE -CAkey $CA_KEY_FILE -sha512 -CAcreateserial
}

function enablemodes(){
    echo "[*] Enabling PIV, FIDO2, FIDO U2F modes"
    ykman config usb -e PIV -f 
    sleep 3
    ykman config usb -e U2F -f 
    sleep 3
    ykman config usb -e FIDO2 -f
    sleep 3
}

function header(){
    clear
    echo "[*] Checking for yubikey"
    ykman info 
    if [ $? -ne 0  ]; then
        echo "Yubikey not found"
        exit
    fi
    echo ""
    echo ""
    ykman info |grep "PIV" | cut -f2 | grep "Enabled"
    if [ $? -ne 0  ]; then
        echo "PIV mode not enabled"
        enablemodes
    fi
    ykman piv info
    if [ $? -ne 0  ]; then
        echo "Yubikey not found"
        exit
    fi
    echo ""
    echo ""
}

function menu() {
    echo "Please choose one of the following options:"
    echo "  1) Reset Yubikey to factory defaults"
    echo "  2) Create PIV private key and certificate"
    echo "  3) Renew PIV certificate - uses existing private key and pin"
    echo "  4) Change PIN"
    echo "  5) Change PUK"
    echo "  6) Change FIDO PIN"
    echo "  q) Quit"
    echo ""
}


requirements
while true
do
    header
	menu
	read -p "Choose action: " choice
    case $choice in
        1)  fullreset
            ;;
        2)
            pivinit
            ;;
        3)
            renewonly
            ;;
        4)
            yubico-piv-tool -a change-pin
            ;;
        5)
            yubico-piv-tool -a change-puk
            ;;
        6)  
            ykman fido access change-pin 
            ;;
        q)
            exit
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 0."
            ;;
    esac
done

