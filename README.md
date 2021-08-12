# SSHD
- build: ![docker.sshd](https://github.com/corpusops/docker.sshd/workflows/.github/workflows/cicd.yml/badge.svg?branch=master)

- Minimal Alpine Linux Docker image with `sshd` exposed and `rsync` installed.
  integration with:
    - logging (rsyslog)
    - logrotate logs
    - fail2ban

Mount your .ssh credentials (RSA public keys) at `/root/.ssh/` in order to
access the container via root ssh or mount each user's key in
`/etc/authorized_keys/<username>` and set `SSH_USERS` config to create user accounts (see below).

- Optionally mount [sshd_config.in](./sshd_config.in) as a custom sshd config at `/etc/ssh/sshd_config.in`.<br/>
  You can override in the compose setup the template location via the `SSHD_CONFIG` env var.

- By default the image is in SFTP only mode.
- User mounted sshkeys are synced every minute (default, you can change `SYNC_SSHKEYS_TIMER` (seconds))

## Environment Options

- `SSH_USERS` list of user accounts and uids/gids to create. eg `SSH_USERS=www:48:48:SUPERPASSWORDPASSWORD,admin:1000:1000:SUPERSECRET:/home/newhome:/bin/bash`
- `MOTD` change the login message
- `SFTP_MODE` if set to `true` sshd will only accept sftp connections
- `SFTP_CHROOT` if set to `true` in sftp only mode sftp will be chrooted to this directory `SFTP_CHROOT_PATH`. Default `/home`
- `MAX_RETRY` max retries before fail2ban cut the line
- `SYNC_SSHKEYS_TIMER` timer to sync keys inside the container
- `TZ` user timezone
- `UIDS_START` uids start (1000): default uid if you dont explicitly tell them
- `LOGIN_SHELL` default bash

### The SSH_USERS variable
- Format is `username:uid:gid:password:home:loginshell`, `comma: ,` separated.
- those opts are optional:
    - `uid` (default: `1000` and increment for each user in list)
    - `gid` (default: `uid`)
    - `home` (default `/home/$name`)
    - `password`
    - `loginshell` (default: `$LOGIN_SHELL` > `/bin/bash`)
- exemples:
    - `SSHD_USERS=toto,tata`: create a user `toto` with uid `1000`, and tata `1001`.
    - `SSHD_USERS=toto:1001::x`: create a user `toto` with uid `1001`, uid `1001` and password `x`.

## SSH Keys
You can set allowed keys for a particular user by creating authorized_keys files under ``./keys``, eg ``./keys/myuser``.

## SSH Host Keys

SSH uses host keys to identity the server you are connecting to. To avoid receiving security warning the containers host keys should be mounted on an external volume.

By default this image will create new host keys in `/etc/ssh/keys` which should be mounted
on an external volume. If you are using existing keys and they are mounted
in `/etc/ssh` this image will use the default host key location making this image compatible with existing setups.

If you wish to configure SSH entirely with environment variables*
it is suggested that you externally mount `/etc/ssh/keys` instead of `/etc/ssh`.

## SFTP mode

When in sftp only mode (activated by setting `SFTP_MODE=true` the container will only accept sftp connections. All sftp actions will be chrooted to the `SFTP_CHROOT` directory which defaults to "/data".

Please note that all components of the pathname in the ChrootDirectory directive must be root-owned directories that are not writable by any other user or group (see man 5 sshd_config).

## Usage Example

```
docker-compose run -v /secrets/id_rsa.pub:/root/.ssh/authorized_keys -v /mnt/data/:/data/ sshd
```

or

```
docker-compose run -v $(pwd)/id_rsa.pub:/etc/authorized_keys/www -e SSH_USERS="www:48:48" sshd
```


## Media server usage
```sh
cp .env.mediaserver .env
cp -f docker-compose.mediaserver.yml docker-compose.override.yml
$EDITOR .env
$EDITOR docker-compose.override.yml
docker-compose -f docker-compose.yml -f docker-compose.override.yml up -d --force-recreate
```


## VPN usage (configure outgoing ip)
```sh
cp .env.vpn .env
cp -f docker-compose.vpn.yml docker-compose.override.yml
$EDITOR .env
$EDITOR docker-compose.override.yml
docker-compose -f docker-compose.yml -f docker-compose.override.yml up -d --force-recreate
```


## Ad Hoc ssh client

```sh
docker run -it corpusops/sshd ssh   google.com
docker run -it corpusops/sshd rsync google.com
```

## entrypoint hooks
- The image support hooks to be executed thorough the entry point execution
- Everything inside the scripts dirs will be executed
- Read the [entry.sh](./entry.sh) script to know where you want to hook in
    - `/hooks/pre/*`
    - `/hooks/pre_keys/*`
    - `/hooks/pre_users/*`
    - `/hooks/pre_users_keys/*`
    - `/hooks/pre_users_chmod_keys/*`
    - `/hooks/post_users_keys/*`
    - `/hooks/post/*`
    - `/hooks/post_acls/*`
    - `/hooks/pre_run/*`

### Full example of rsync transfer with ssh-agent

```sh
eval `ssh-agent`
ssh-add ~/.ssh/id_rsa
docker run -it \
    -v /path/to/transfer:/transfer \
    -v $HOME/.ssh/:/issh:ro \
    -v $(readlink -f $SSH_AUTH_SOCK):/ssh-agent \
    -e SSH_AUTH_SOCK=/ssh-agent \
    --entrypoint bash corpusops/sshd  \
    -ec  'rsync -azv /issh/ /root/.ssh/ && chown -Rf root:root /root/.ssh && \
    rsync -azv myhost:/totransfer/ /transfer/'
```


