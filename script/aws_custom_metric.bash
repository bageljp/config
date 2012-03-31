#!/bin/bash
#-----------------------------------------------------------
#
# Author(s): K.Kadoyama
#
# Usage:
#   aws_custom_metric.bash [option]
#       option -
#           load        : LoadAverage
#           mem         : MEMUtilization
#           swap        : SWAPUtilization
#           disk        : DISKUtilization
#           url         : HTTPCode_200
#           cert        : SSLCert
#           proc_httpd  : ProcCountApache
#           proc_nginx  : ProcCountNginx
#
# Current Version: 1.0.3
#
# Revision History:
#
#   Version 1.0.3 by K.Kadoyama (2012/03/20)
#     - Define add ${CONF_AWS_GLOBAL}.
#
#   Version 1.0.2 by K.Kadoyama (2012/01/16)
#     - Define is change.
#
#   Version 1.0.1 by K.Kadoyama (2012/01/16)
#     - func_disk_put, func_proc_httpd_put, func_proc_nginx_put is corrected.
#
#   Version 1.0.0 by K.Kadoyama (2011/11/24)
#     - Initial new.
#
#   Version 0.1.0 by K.Kadoyama (2011/11/24)
#     - Created.
#
# Example:
#
#   # crontab -l
#   */5 * * * * /path/to/aws_custom_metric.bash mem swap load disk url > /dev/null 2>&1
#   0 1 * * *   /path/to/aws_custom_metric.bash cert > /dev/null 2>&1
#
#-----------------------------------------------------------

#===========================================================
# Define
#===========================================================
# global conf
#-----------------------------------------------------------
export CONF_AWS_GLOBAL="/etc/profile.d/aws-apitools-common.sh"
if [ -r ${CONF_AWS_GLOBAL} ]; then
    source ${CONF_AWS_GLOBAL}
else
    export AWS_PATH="/opt/aws"
    export AWS_CREDENTIAL_FILE="/opt/aws/credentials.txt"
    export EC2_PRIVATE_KEY="/path/to/pk-XXXXXXXXXX.pem"
    export EC2_CERT="/path/to/cert-XXXXXXXXXXX.pem"
    export EC2_URL="https://ec2.ap-northeast-1.amazonaws.com"
    export EC2_REGION="ap-northeast-1"
    export AWS_CLOUDWATCH_HOME="/opt/aws/apitools/mon"
    export JAVA_HOME="/usr/lib/jvm/jre"
fi
export AWS_CLOUDWATCH_URL="https://monitoring.amazonaws.com"
export PATH="${AWS_CLOUDWATCH_HOME}/bin:/opt/aws/bin:${PATH}"

export SH_ORIG="${0##*/}"
export CMD_MON_PUT="${AWS_CLOUDWATCH_HOME}/bin/mon-put-data"
export CMD_PS="/bin/ps"
export LOG_FAC="local0"

# use func_disk_put
#-----------------------------------------------------------
LIST_DISK[0]="/"
#LIST_DISK[1]="/storage"

# use func_http_put
#-----------------------------------------------------------
#LIST_HTTP_URL[0]="http://example.com/check.html"

# use func_cert_put
#-----------------------------------------------------------
# wget http://prefetch.net/code/ssl-cert-check
SH_SSL_CHECK="/path/to/ssl-cert-check"
SSL_EXPIRE_DAYS="30"
LIST_CERT_URL[0]="127.0.0.1:443"

# use func_proc_httpd_put
#-----------------------------------------------------------
PROC_HTTPD="httpd$"

# use func_proc_nginx_put
#-----------------------------------------------------------
PROC_NGINX="^nginx"

# get ec2 instance id
#-----------------------------------------------------------
instanceid="`curl -s http://169.254.169.254/latest/meta-data/instance-id`"



#===========================================================
# Function
#===========================================================
#-----------------------------------------------------------
# Usage:
#   func_log $1 $2
#     $1 -> info , warn or warning, err or error.
#     $2 -> messages.
#-----------------------------------------------------------
func_log() {
    if [ $# -lt 2 ]; then
        logger -p ${LOG_FAC}.warning "### WARN[${SH_ORIG}]: argument error."
        return 1
    fi
    case "$1" in
        info)
            logger -p ${LOG_FAC}.info "### INFO[${SH_ORIG}]: $2"
            ;;
        warn | warning)
            logger -p ${LOG_FAC}.warning "### WARN[${SH_ORIG}]: $2"
            ;;
        err | error)
            logger -p ${LOG_FAC}.error "### ERROR[${SH_ORIG}]: $2"
            ;;
        *)
            logger -p ${LOG_FAC}.error "### WAN[${SH_ORIG}]: Log facility is not defined. Original message is [$2]"
    esac
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_chk_cmd $1
#     $1 -> check command.
#-----------------------------------------------------------
func_chk_cmd() {
    which "$1" > /dev/null 2>&1
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "error" "$1 is not found."
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_load_put
#-----------------------------------------------------------
func_load_put() {
    loadavg1="`uptime | awk '{print $(NF-2)}'`"
    loadavg5="`uptime | awk '{print $(NF-1)}'`"
    loadavg15="`uptime | awk '{print $NF}'`"

    ${CMD_MON_PUT} -m "LoadAverage" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${loadavg1%,} -u "Count"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "load average put error. [${loadavg1%,} ${loadavg5%,} ${loadavg15}]"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_mem_put
#-----------------------------------------------------------
func_mem_put() {
    func_chk_cmd "bc"
    [ $? -ne 0 ] && return 2
    memtotal="`free -m | awk '/Mem:/ {print $2}'`"
    memfree="`free -m | awk '/buffers\/cache/ {print $4}'`"
    if [ ${memtotal} -eq 0 ]; then
        func_log "info" "memory is zero."
        return 0
    else
        memused=`echo "scale=3; 100-${memfree}*100/${memtotal}" | bc`
        [ "x" == "x${memused%%.*}" ] && memused="0${memused}"

        ${CMD_MON_PUT} -m "MEMUtilization" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${memused} -u "Percent"
        ret=$?
        if [ ${ret} -ne 0 ]; then
            func_log "warn" "memory put error. [${memused}]"
            return 1
        fi
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_swap_put
#-----------------------------------------------------------
func_swap_put() {
    func_chk_cmd "bc"
    [ $? -ne 0 ] && return 2
    swaptotal="`free -m | awk '/Swap:/ {print $2}'`"
    swapfree="`free -m | awk '/Swap:/ {print $NF}'`"
    if [ ${swaptotal} -eq 0 ]; then
        func_log "info" "swap is zero."
        return 0
    else
        swapused=`echo "scale=3; 100-${swapfree}*100/${swaptotal}" | bc`
        ${CMD_MON_PUT} -m "SWAPUtilization" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${swapused} -u "Percent"
        ret=$?
        if [ ${ret} -ne 0 ]; then
            func_log "warn" "swap put error. [${swapused}]"
            return 1
        fi
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_disk_put
#-----------------------------------------------------------
func_disk_put() {
    func_chk_cmd "bc"
    [ $? -ne 0 ] && return 2
    maxused=0
    maxmount="non"
    for i in ${LIST_DISK[@]}; do
        diskline="`df -k -P | awk '{print $(NF-4),$(NF-2),$NF}' | grep ${i}$`"
        if [ "x" == "x${diskline}" ]; then
            func_log "info" "${i} is not found."
            continue
        fi
        disktotal="`echo ${diskline} | awk '{print $1}'`"
        diskfree="`echo ${diskline} | awk '{print $2}'`"
        diskmount="`echo ${diskline} | awk '{print $3}'`"
        if [ ${disktotal} -eq 0 ]; then
            func_log "info" "${diskmount} disksize is zero."
            continue
        fi
        diskused=`echo "scale=3; 100-${diskfree}*100/${disktotal}" | bc`
        [ "`echo ${diskused} | cut -c1`" = "." ] && diskused="0${diskused}"
        if [ ${maxused%%.*} -lt ${diskused%%.*} ]; then
           maxused="${diskused}"
           maxmount="${diskmount}"
        fi
    done

    ${CMD_MON_PUT} -m "DISKUtilization" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${maxused} -u "Percent"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "disk put error. [${maxused} ${maxmount}]"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_url_put
#-----------------------------------------------------------
func_url_put() {
    cnturl=0
    for i in ${LIST_HTTP_URL[@]}; do
        curl -I -s ${i} | grep ^HTTP | grep "200 OK" > /dev/null 2>&1
        ret=$?
        [ ${ret} -eq 0 ] && cnturl="$((${cnturl}+1))"
    done

    ${CMD_MON_PUT} -m "HTTPCode_200" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${cnturl} -u "Count"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "http url put error. [${cnturl}]"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_cert_put
#-----------------------------------------------------------
func_cert_put() {
    func_chk_cmd "${SH_SSL_CHECK}"
    [ $? -ne 0 ] && return 2
    cntcert=0
    for i in ${LIST_CERT_URL[@]}; do
        ${SH_SSL_CHECK} -s ${i%:*} -p ${i#*:} -x ${SSL_EXPIRE_DAYS} | grep Valid > /dev/null 2>&1
        ret=$?
        [ ${ret} -eq 0 ] && cntcert="$((${cntcert}+1))"
    done

    ${CMD_MON_PUT} -m "SSLCert" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${cntcert} -u "Count"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "ssl cert put error. [${cntcert}]"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_proc_httpd_put
#-----------------------------------------------------------
func_proc_httpd_put() {
    cnthttpd="`${CMD_PS} -eo 'command' | grep ${PROC_HTTPD} | grep -v grep | wc -l`"

    ${CMD_MON_PUT} -m "ProcCountApache" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${cnthttpd} -u "Count"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "apache process put error. [${cnthttpd}]"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------
# Usage:
#   func_proc_nginx_put
#-----------------------------------------------------------
func_proc_nginx_put() {
    cntnginx="`${CMD_PS} -eo 'command' | grep ${PROC_NGINX} | grep -v grep | wc -l`"

    ${CMD_MON_PUT} -m "ProcCountNginx" -n "System/Linux" -d "InstanceId=${instanceid}" -v ${cntnginx} -u "Count"
    ret=$?
    if [ ${ret} -ne 0 ]; then
        func_log "warn" "nginx process put error. [${cntnginx}]"
        return 1
    fi
    return 0
}



#===========================================================
# Check
#===========================================================
func_chk_cmd "${CMD_MON_PUT}"
[ $? -ne 0 ] && exit $?



#===========================================================
# Main
#===========================================================
if [ $# -eq 0 ]; then
    func_load_put
    func_mem_put
    func_swap_put
    func_disk_put
    func_url_put
    func_cert_put
    func_proc_httpd_put
    func_proc_nginx_put
else
    for opts in $@; do
        case ${opts} in
            load)
                func_load_put
                ;;
            mem)
                func_mem_put
                ;;
            swap)
                func_swap_put
                ;;
            disk)
                func_disk_put
                ;;
            url)
                func_url_put
                ;;
            cert)
                func_cert_put
                ;;
            proc_httpd)
                func_proc_httpd_put
                ;;
            proc_nginx)
                func_proc_nginx_put
                ;;
            *)
                echo "Usage: ${SH_ORIG} [option]"
                echo "    option -"
                echo "        load        : LoadAverage"
                echo "        mem         : MEMUtilization"
                echo "        swap        : SWAPUtilization"
                echo "        disk        : DISKUtilization"
                echo "        url         : HTTPCode_200"
                echo "        cert        : SSLCert"
                echo "        proc_httpd  : ProcCountApache"
                echo "        proc_nginx  : ProcCountNginx"
                ;;
        esac
    done
fi

exit 0

#===========================================================
# End.
#   0     -> normal end.
#   other -> abnormal end.
#===========================================================
