FROM corpusops/alpine-bare:latest
RUN apk update && \
    apk add acl bash shadow git openssh rsync fail2ban autossh && \
    deluser $(getent passwd 33 | cut -d: -f1) && \
    delgroup $(getent group 33 | cut -d: -f1) 2>/dev/null || true && \
    mkdir -p ~root/.ssh /etc/authorized_keys && chmod 700 ~root/.ssh/ && \
    echo -e "Port 22\n" >> /etc/ssh/sshd_config && \
    cp -a /etc/ssh /etc/ssh.cache && \
    rm -rf /var/cache/apk/*
COPY fail2ban-supervisor.sh entry.sh /
ADD supervisor.d/* /etc/supervisor.d/
ADD sshd_config.in /etc/ssh/
ADD ./fail2ban/ /fail2ban/
RUN mkdir -p /etc/ssh/keys /etc/ssh/keys.in /etc/authorized_keys.in /etc/authorized_keys
ENV SUPERVISOR_CONFIGS="rsyslog sshd cron fail2ban"
CMD ["/entry.sh"]
