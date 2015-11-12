#!/bin/bash -e
########################################################################
#** Version: 1.0
#* This script gives a hand in testing ssl connections as remembering
#* all that openssl commands was to much for my small brain. Default
#* port is HTTPS.
#
########################################################################
# author/copyright: <mic@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=~/.ssl-tester.sh

### {{{

dryrun=1
needsroot=1
ciphers=''
verbose=0

### }}}

starttls=""

# Unsetting this helper variable
_pre=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=(
    ["_awk"]="/usr/bin/awk"
    ["_cat"]="/bin/cat"
    ["_cp"]="/bin/cp"
    ["_grep"]="/bin/grep"
    ["_id"]="/usr/bin/id"
    ["_mkdir"]="/bin/mkdir"
    ["_openssl"]="/usr/bin/openssl"
    ["_pwd"]="/bin/pwd"
    ["_rm"]="/bin/rm"
    ["_rmdir"]="/bin/rmdir"
    ["_sed"]="/bin/sed"
    ["_sed_forced"]="/bin/sed"
    ["_tr"]="/usr/bin/tr"
)
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_sed" "_rm" "_rmdir" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

## functions ##

print_usage()
{
    echo "usage: $0 action [servername] [port]"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed_forced 's;^#\*;;'
}

print_version()
{
    $_grep "^#\*\* " $0 | $_sed 's;^#\*\*;;'
}

die()
{
    echo "$@"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: $@"
}

## logic ##

## first set the system tools
for t in ${!sys_tools[@]} ; do
    if [ -x "${sys_tools[$t]##* }" ] ; then
        export ${t}="${sys_tools[$t]}"
    else
        error "Missing system tool: ${sys_tools[$t]##* } must be installed."
    fi
done

[ -r "$conffile" ] && . $conffile

#* options:
while true ; do
    case "$1" in
#*      -c |--config conffile       alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -C |--allciphers            consider all ciphers
        -C|--allciphers)
            shift
            ciphers='ALL:eNULL'
        ;;
#*      -h |--help                  print this help
        -h|--help)
            print_help
            exit 0
        ;;
##*      -n |--dry-run               do not change anything
#        -n|--dry-run)
#            dryrun=0
#        ;;
#*      -q |--quiet                 contrary of verbose (see config)
        -q|--quiet)
            verbose=1
        ;;
#*      -s |--starttls protocol     use starttls (see 'man s_client')
        -s|--starttls)
            shift
            starttls="-starttls $1"
        ;;
#*      -v |--verbose               contrary of quiet (see config)
        -v|--verbose)
            verbose=0
        ;;
#*      -V |--version               print the version information
        -V|--version)
            print_version
            exit
        ;;
        -*|--*)
            error "option $1 not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ $dryrun -eq 0 ] ; then
    _pre="echo "
fi

if [ $needsroot -eq 0 ] ; then

    iam=$($_id -u)
    if [ $iam -ne 0 ] ; then
        if [ -x "$_sudo" ] ; then

            _pre="$_pre $_sudo"
        else
            error "Missing system tool: $_sudo must be installed."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

host=${2:-localhost}
port=${3:-443}

connect()
{
    $_openssl s_client $3 $starttls -connect $1:$2 2>&1
}

try_connect()
{
    echo "" | $_openssl s_client $3 $starttls -connect $1:$2 2>&1
}

list_ciphers()
{
    $_openssl ciphers $ciphers | $_sed 's;:; ;g'
}

get_certs()
{
    try_connect $1 $2 $3 | \
        $_awk 'BEGIN {printout=1;} \
                /-----BEGIN CERTIFICATE-----/ {printout=0;} \
                /-----END CERTIFICATE-----/ {printout=1; print $0} \
                {if (printout == 0) print $0}'
}

print_summary()
{
    get_certs $1 $2 $3 | $_openssl x509 -noout -text | \
        $_grep -A1 -e "Version: " -e "Signature Algorithm:" \
                    -e "Not Before:" -e "Subject:" -e "Public-Key:" \
                    -e "X509v3 Subject Key Identifier:" \
                    -e "X509v3 Subject Alternative Name:" \
                    -e "Authority Information Access:" \
                    -e "CA Issuers" | \
            $_sed 's/^ */ /' | \
            $_grep -v -e "--" -e "Modulus:" -e "Subject Public Key Info:" | \
            $_awk '/^\s$/ {exit}; {print $0};'
}

print_hostnames()
{
    get_certs $1 $2 $3 | $_openssl x509 -noout -text | \
        $_grep -e "Subject:" -e "DNS:"
}

#* actions:
case $1 in
#*      certs                       show the certificates involved
    cert*)
        try_connect $host $port -showcerts
        ;;
#*      ciphers                     test the cipher suite support on a server
    cip*)
        echo "Testing cipher suite on $host $port:"
        for c in $(list_ciphers) ; do
            retval=0
            res=$(try_connect $host $port "-cipher $c") || retval=1
            if [ $retval -eq 0 ] ; then
                echo -e "\e[0;39m[\e[1;32m*\e[1;39m] $c"
            else
                if [ $verbose -eq 0 ] ; then
                    res=$( echo -n $res | cut -d':' -f6)
                    echo -e "\e[0;39m[\e[1;31m*\e[0;39m] $c \e[0;33m$res"
                fi
            fi
        done
        ;;
#*      connect                     open a connection and hold it
    connect|open)
        connect $host $port
        ;;
#*      connect-test                just try to connect
    connect-test|test|try)
        try_connect $host $port
        ;;
#*      list-ciphers                list the ciphers available locally
    ls|list*)
        for c in $(list_ciphers) ; do
            echo $c
        done
        ;;
#*      print-cert                  print just the certificate
    print-cert)
        get_certs $host $port
    ;;
#*      print-certs                 print just the certificates involved
    print-certs)
        get_certs $host $port -showcerts
    ;;
#*      print-hostnames             print all the hostnames protected
    print-host*|host*)
        IFSOLD=$IFS
        IFS="$(echo -ne '\n\b')"
        info=( $(IFS=$IFSOLD; print_hostnames $host $port) )
        echo "This certificate was issued for:"
        IFS=","
        holder=( $( echo "${info[0]#*:}" ) )
        IFS=$IFSOLD
        for (( i=0; i<${#holder[@]}; i++ )); do
            echo -e " $(echo ${holder[$i]} | $_sed 's@CN@\\e[1;33mCN@') "\
                    "\e[0;39m"
        done
#        a=$(echo ${holder[0]#*:} | $_sed 's@CN@\\e[0;39mCN@')
        echo "The following additional hostnames (SAN) are registered:"
        echo -e -n "\e[0;33m"
        for h in ${info[1]} ; do
            h=${h#*:}
            echo "    ${h%,}"
        done
    ;;
#*      print-summary               print an overview of the certificate
    print-sum*|sum)
        print_summary $host $port
    ;;
    *)
        error "not supported.."
        ;;
esac
