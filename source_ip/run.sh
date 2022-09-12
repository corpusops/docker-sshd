#!/usr/bin/env bash
set -e
SDEBUG=${SDEBUG-}
if [[ -n "$SDEBUG" ]];then set -x;fi
OUTIP=${OUTIP-}
SUBNET=${SUBNET-}
BRIDGE_SSHD=${BRIDGE_SSHD:-br-sshd}
log() { echo "$@">&2; }
vv() { log "$@";"$@"; }
if [[ -z $SUBNET ]] || [[ -z $OUTIP ]];then
    log 'missing $OUTIP or $SUBNET'
    exit 1
fi
# in the IPTABLES NAT::POSTROUTING rules
# we always want that our SNAT rules are first, way before docker MASQUERADE rules
ipt="iptables -w -t nat"
ippost="$ipt -S POSTROUTING"
RULE="-s $SUBNET ! -d $SUBNET -j SNAT --to-source $OUTIP"
RULE="-s $SUBNET/24 ! -o br-sshd -j SNAT --to-source $OUTIP"
get_snat_number() {
    $ippost|grep -E -nv "^-P"|grep -E "$SUBNET.*SNAT.*$OUTIP"|head -n1|awk -F: '{print $1}'
}
while [ infinite ];do
    if ( $ippost | grep -E -q SNAT );then
        snatnumber=$(get_snat_number)
        number=$($ippost|grep -E -v "^-P"|grep -nv SNAT|head -n1|awk -F: '{print $1}')
    fi
    if [[ -n $snatnumber ]] && [[ -n $number ]] && [[ $snatnumber -gt $number ]];then
        log "Flushing SNAT to $OUTIP as docker rules messed it"
        vv $ipt -D POSTROUTING $RULE
    fi
    snatnumber=$(get_snat_number)
    if [[ -z $snatnumber ]];then
        log "Adding SNAT to $OUTIP"
        $ipt -I POSTROUTING 1 $RULE
    fi
    snatnumber=$(get_snat_number)
    sleep 5
done
# vim:set et sts=4 ts=4 tw=0:
