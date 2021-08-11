#!/usr/bin/env bash
set -e
SSHD_SDEBUG=${SSHD_SDEBUG-${SDEBUG-}}
DEBUG=${DEBUG-}
SYNC_SSHKEYS_TIMER=${SYNC_SSHKEYS_TIMER:-60}
UIDS_START=${UIDS_START:-1000}
VERBOSE=${VERBOSE-}
if [[ -n $DEBUG ]];then
    VERBOSE="-v"
fi
log() { echo "$@">&2; }
debuglog() {
    if [[ -n "$DEBUG" ]];then echo "$@" >&2;fi
}
vv() { log "$@"; "$@"; }
execute_hooks() {
    local step="$1"
    local hdir="$INIT_HOOKS_DIR/${step}"
    if [ ! -d "$hdir" ];then return 0;fi
    shift
    while read f;do
        if ( echo "$f" | egrep -q "\.sh$" );then
            log "running shell hook($step): $f"
            . "${f}"
        else
            log "running executable hook($step): $f"
            "$f" "$@"
        fi
    done < <(find "$hdir" -type f -executable 2>/dev/null | sort -V; )
}
print_fingerprints() {
    local BASE_DIR=${1-'/etc/ssh'}
    for item in dsa rsa ecdsa ed25519;do
        echo ">>> Fingerprints for ${item} host key"
        ssh-keygen -E md5 -lf ${BASE_DIR}/ssh_host_${item}_key
        ssh-keygen -E sha256 -lf ${BASE_DIR}/ssh_host_${item}_key
        ssh-keygen -E sha512 -lf ${BASE_DIR}/ssh_host_${item}_key
    done
}

if [[ -n $SSHD_SDEBUG ]];then set -x;fi

SSH_CONFIG=/etc/ssh/sshd_config
export INIT_HOOKS_DIR="${INIT_HOOKS_DIR:-/hooks}"
export TZ="${TZ:-Europe/Paris}"

execute_hooks pre "$@"

echo $TZ > /etc/timezone
cp $VERBOSE -f /usr/share/zoneinfo/$TZ /etc/localtime
export MAX_RETRY=${MAX_RETRY:-6}
if [[ -n "$SSHD_SDEBUG" ]];then
    set -x
fi
touch $SSH_CONFIG
if [ -e "$SSH_CONFIG".in ];then
    vv frep $SSH_CONFIG.in:$SSH_CONFIG --overwrite
fi
# Copy default config from cache
if [ ! "$(ls -A /etc/ssh)" ]; then
   rsync -az $VERBOSE /etc/ssh.cache/ /etc/ssh/
fi

execute_hooks pre_keys "$@"

# Generate Host keys, if required
if ls /etc/ssh/keys/ssh_host_* 1> /dev/null 2>&1; then
    echo ">> Host keys in keys directory"
    print_fingerprints /etc/ssh/keys
elif ls /etc/ssh/ssh_host_* 1> /dev/null 2>&1; then
    echo ">> Host keys exist in default location"
    # Don't do anything
    print_fingerprints
else
    echo ">> Generating new host keys"
    mkdir -p $VERBOSE /etc/ssh/keys
    ssh-keygen -A
    mv $VERBOSE /etc/ssh/ssh_host_* /etc/ssh/keys/
    print_fingerprints /etc/ssh/keys
fi

sync_ssh_user_keys() {
    debuglog "Syncing sshkeys"

    execute_hooks pre_users_keys "$@"

    for i in /etc/authorized_keys /etc/ssh/keys;do
        if [ -e "${i}.in" ];then
            rsync -azv --chown=0:0 "${i}.in/" "${i}/"
        fi
    done

    execute_hooks pre_users_chmod_keys "$@"

    # Fix permissions, if writable
    for sshconfigdir in ~/.ssh /etc/authorized_keys;do
        chown 0:0 $sshconfigdir
        chmod g-w,o-rw,o+x $sshconfigdir
        while read i;do
            chown $VERBOSE 0:0 $i
            chmod $VERBOSE g-wx,o-wx $i
            chmod $VERBOSE u+r $i
        done < <(find $sshconfigdir -type f -mindepth 1 2>/dev/null )
    done

    execute_hooks post_users_keys "$@"

    for i in /etc/ssh/keys;do
        chown -Rfv 0:0 $i
        while read f;do chmod $VERBOSE -f 710 $f; done < <(find ${i} -type d)
        while read f;do chmod $VERBOSE -f 600 $f; done < <(find ${i} -type f)
    done

    execute_hooks post_sys_keys "$@"

}

infinite_sync_ssh_user_keys() {
    while true;do
        sleep $SYNC_SSHKEYS_TIMER
        sync_ssh_user_keys
    done
}


sync_ssh_user_keys
# sync for the lifetime of the container keys every minute
infinite_sync_ssh_user_keys&

execute_hooks pre_users "$@"

# Add users if SSH_USERS=user:uid:gid set
HAS_USERS=
LOGIN_SHELL=${LOGIN_SHELL:-/bin/bash}
VIAKEY_GID=${VIAKEY_GID:-5888}
HOMES=${HOMES:-/home}
passwd -d root
addgroup -g ${VIAKEY_GID} viakey || true
if [ -n "${SSH_USERS}" ]; then
    USERS=$(echo $SSH_USERS | tr "," "\n")
    userinc=${UIDS_START}
    for U in $USERS; do
        IFS=':' read -ra UA <<< "$U"
        uname=${UA[0]}
        uid=${UA[1]:-${userinc}}
        gid=${UA[2]:-${uid}}
        pw=${UA[3]:-}
        h=${UA[4]:-${HOMES}/${uname}}
        sh=${UA[5]:-$LOGIN_SHELL}
        if [[ "${uname}" = "root" ]];then uid=0;gid=0;fi
        if [ ! -e "/etc/authorized_keys/${uname}" ]; then
            log "WARNING: No SSH authorized_keys found for ${uname}!"
        fi
        if [[ $uname != "root" ]];then
            log ">> Adding or modifying user ${uname} with uid: ${uid}, gid: ${gid}."
            getent group  $gid >/dev/null 2>&1 || addgroup -g ${gid} ${uname}grp
            if ! ( getent passwd ${uname}    >/dev/null 2>&1 );then
                useradd -m -s "${sh}" -g ${uid} -u ${uid} ${uname}
            fi
            usermod -o -d ${h} -s ${sh} -u ${uid} ${uname}
            addgroup ${uname} $(getent group $gid|cut -d: -f1)
        fi
        passwd -u ${uname} || true
        if [[ -n "${pw}" ]];then
            log "Setting password for $uname"
            printf "${pw}\n${pw}\n" | passwd "${uname}"
        else
            log "Disabling password for $uname"
            addgroup ${uname} viakey
            passwd -d ${uname} || true
        fi
        HAS_USERS=1
        userinc=$(($userinc +1))
    done
fi

# Update MOTD
if [ -v MOTD ]; then
    echo -e "$MOTD" > /etc/motd
fi

execute_hooks post "$@"

if [ -e acls.sh ] ;then
    log "Acls setup"
    /acls.sh || /bin/true
fi

execute_hooks postacls "$@"

rm $VERBOSE -f /run/rsyslogd.pid
cp $VERBOSE -rf /fail2ban/* /etc/fail2ban
if [ -e /run/fail2ban ];then rm $VERBOSE -f /run/fail2ban/fail2ban.*;fi
frep --overwrite /fail2ban/jail.d/alpine-ssh.conf:/etc/fail2ban/jail.d/alpine-ssh.conf

execute_hooks pre_run "$@"

# Warn if no authorized_keys
if [[ -z "$HAS_USERS" ]] && [ ! -e ~/.ssh/authorized_keys ] && [[ "$(ls -A /etc/authorized_keys)" = "" ]] ; then
  echo "WARNING: No SSH authorized_keys found!"
fi

log "SSHD Internal IP: $(hostname  -i)"

exec /bin/supervisord.sh
