FROM debian:buster AS builder

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT

RUN printf "I'm building for PLATFORM=${TARGETPLATFORM}, ARCH=${TARGETARCH}, VARIANT=${TARGETVARIANT} \n"

### Set defaults
ENV ASTERISK_VERSION=17.9.3 \
    BCG729_VERSION=1.0.4 \
    DONGLE_VERSION=20200610 \
    G72X_CPUHOST=penryn \
    G72X_VERSION=0.1 \
    PHP_VERSION=5.6 \
    SPANDSP_VERSION=20180108 \
    RTP_START=18000 \
    RTP_FINISH=20000

### Dependencies addon
RUN set -x && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
            apt-transport-https \
            aptitude \
            bash \
            ca-certificates \
            curl \
            dirmngr \
            dos2unix \
            gnupg \
            less \
            logrotate \
            msmtp \
            nano \
            net-tools \
            netcat-openbsd \
            procps \
            sudo \
            tzdata \
            vim-tiny \
            wget

### Pin libxml2 packages to Debian repositories
RUN c_rehash && \
    echo "Package: libxml2*" > /etc/apt/preferences.d/libxml2 && \
    echo "Pin: release o=Debian,n=buster" >> /etc/apt/preferences.d/libxml2 && \
    echo "Pin-Priority: 501" >> /etc/apt/preferences.d/libxml2 && \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=TRUE && \
    \
### Install dependencies
    set -x && \
    curl https://packages.sury.org/php/apt.gpg | apt-key add - && \
    echo "deb https://packages.sury.org/php/ buster main" > /etc/apt/sources.list.d/deb.sury.org.list && \
    echo "deb http://ftp.us.debian.org/debian/ buster main" > /etc/apt/sources.list.d/backports.list && \
    echo "deb-src http://ftp.us.debian.org/debian/ buster main" >> /etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    apt-get -o Dpkg::Options::="--force-confold" upgrade -y

ADD asterisk_build_deps /usr/src/

ADD asterisk_runtime_deps /usr/src/

RUN cat /usr/src/asterisk_runtime_deps | sed 's/\${PHP_VERSION}/${PHP_VERSION}/g'

### Install development dependencies
RUN apt-get install --no-install-recommends -y `cat /usr/src/asterisk_build_deps`

### Install runtime dependencies
RUN apt-get install --no-install-recommends -y `cat /usr/src/asterisk_runtime_deps | sed 's/${PHP_VERSION}/'"$PHP_VERSION"'/g'`


### Usbutils addon
RUN apt-get install -y usbutils unzip autoconf automake cmake gcc

### Build MardiaDB connector
RUN cd /usr/src && \
    git clone https://github.com/MariaDB/mariadb-connector-odbc.git && \
    cd mariadb-connector-odbc && \
    git checkout tags/3.1.1-ga && \
    mkdir build && \
    cd build && \
    cmake ../ -LH -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DWITH_SSL=OPENSSL -DDM_DIR="/usr/lib/$(uname -m)-linux-gnu" -DCMAKE_C_FLAGS_RELEASE:STRING="-w" && \
    cmake --build . --config Release && \
    mkdir -p /usr/src/mariadb-connector-odbc-compiled && \
    cp -R /usr/src/mariadb-connector-odbc/ /usr/src/mariadb-connector-odbc-compiled/ && \
    make install

### Build SpanDSP
RUN mkdir -p /usr/src/spandsp && \
    curl -kL http://sources.buildroot.net/spandsp/spandsp-${SPANDSP_VERSION}.tar.gz | tar xvfz - --strip 1 -C /usr/src/spandsp && \
    cd /usr/src/spandsp && \
    ./configure --prefix=/usr && \
    make && \
    mkdir -p /usr/src/spandsp-compiled && \
    cp -R /usr/src/spandsp/ /usr/src/spandsp-compiled/ && \
    make install

### Build Asterisk
RUN cd /usr/src && \
    mkdir -p asterisk && \
    curl -sSL http://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz | tar xvfz - --strip 1 -C /usr/src/asterisk && \
    cd /usr/src/asterisk/ && \
    make distclean && \
    contrib/scripts/get_mp3_source.sh && \
    cd /usr/src/asterisk && \
    ./configure \
        --with-jansson-bundled \
        --with-pjproject-bundled \
        --with-bluetooth \
        --with-codec2 \
        --with-crypto \
        --with-gmime \
        --with-iconv \
        --with-iksemel \
        --with-inotify \
        --with-ldap \
        --with-libxml2 \
        --with-libxslt \
        --with-lua \
        --with-ogg \
        --with-opus \
        --with-resample \
        --with-spandsp \
        --with-speex \
        --with-sqlite3 \
        --with-srtp \
        --with-unixodbc \
        --with-uriparser \
        --with-vorbis

RUN cd /usr/src/asterisk && \
    make menuselect/menuselect menuselect-tree menuselect.makeopts && \
    menuselect/menuselect --disable BUILD_NATIVE \
                          --enable-category MENUSELECT_ADDONS \
                          --enable-category MENUSELECT_APPS \
                          --enable-category MENUSELECT_CHANNELS \
                          --enable-category MENUSELECT_CODECS \
                          --enable-category MENUSELECT_FORMATS \
                          --enable-category MENUSELECT_FUNCS \
                          --enable-category MENUSELECT_RES \
                          --enable BETTER_BACKTRACES \
                          --disable MOH-OPSOUND-WAV \
                          --enable MOH-OPSOUND-GSM \
                          --disable app_voicemail_imap \
                          --disable app_voicemail_odbc \
                          --disable res_digium_phone \
                          --disable codec_g729a && \
    make && \
    mkdir -p /usr/src/asterisk-compiled && \
    cp -R /usr/src/asterisk/ /usr/src/asterisk-compiled/ && \
    make install && \
    make install-headers && \
    make config

#### Add G729 codecs
RUN git clone https://github.com/BelledonneCommunications/bcg729 /usr/src/bcg729 && \
    cd /usr/src/bcg729 && \
    git checkout tags/$BCG729_VERSION && \
    ./autogen.sh && \
    ./configure --prefix=/usr --libdir=/lib && \
    make && \
    mkdir -p /usr/src/bcg729-compiled && \
    cp -R /usr/src/bcg729/ /usr/src/bcg729-compiled/ && \
    make install

RUN mkdir -p /usr/src/asterisk-g72x && \
    curl https://bitbucket.org/arkadi/asterisk-g72x/get/master.tar.gz | tar xvfz - --strip 1 -C /usr/src/asterisk-g72x && \
    cd /usr/src/asterisk-g72x && \
    ./autogen.sh && \
    ./configure --prefix=/usr --with-bcg729 && \
#    ./configure CFLAGS='-march=armv7' --prefix=/usr --with-bcg729 --enable-$G72X_CPUHOST && \
    make && \
    mkdir -p /usr/src/asterisk-g72x-compiled && \
    cp -R /usr/src/asterisk-g72x/ /usr/src/asterisk-g72x-compiled/ && \
    make install

#### Add USB Dongle support
RUN git clone https://github.com/rusxakep/asterisk-chan-dongle /usr/src/asterisk-chan-dongle && \
    cd /usr/src/asterisk-chan-dongle && \
    git checkout tags/$DONGLE_VERSION && \
    ./bootstrap && \
    ./configure --with-astversion=$ASTERISK_VERSION && \
    make && \
    mkdir -p /usr/src/asterisk-chan-dongle-compiled && \
    cp -R /usr/src/asterisk-chan-dongle/ /usr/src/asterisk-chan-dongle-compiled\ && \
    make install && ldconfig










FROM debian:buster AS runtime

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT
    
### Set defaults
ENV ZABBIX_VERSION=5.2 \
    S6_OVERLAY_VERSION=v2.1.0.2 \
    DEBUG_MODE=FALSE \
    TIMEZONE=Etc/GMT \
    DEBIAN_FRONTEND=noninteractive \
    ENABLE_CRON=TRUE \
    ENABLE_SMTP=TRUE \
    ENABLE_ZABBIX=TRUE \
    ZABBIX_HOSTNAME=debian.buster \
    ENABLE_CRON=FALSE \
    ENABLE_SMTP=FALSE \
    ASTERISK_VERSION=17.9.3 \
    BCG729_VERSION=1.0.4 \
    DONGLE_VERSION=20200610 \
    G72X_CPUHOST=penryn \
    G72X_VERSION=0.1 \
    PHP_VERSION=5.6 \
    SPANDSP_VERSION=20180108 \
    RTP_START=18000 \
    RTP_FINISH=20000

RUN printf "I'm building for PLATFORM=${TARGETPLATFORM}, ARCH=${TARGETARCH}, VARIANT=${TARGETVARIANT} \n"

### Dependencies addon
RUN set -x && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
            apt-transport-https \
            aptitude \
            bash \
            ca-certificates \
            curl \
            dirmngr \
            dos2unix \
            gnupg \
            less \
            logrotate \
            msmtp \
            nano \
            net-tools \
            netcat-openbsd \
            procps \
            sudo \
            tzdata \
            vim-tiny \
            wget
    
RUN if [ "$TARGETARCH" = "amd64" ] ; then \
        curl https://repo.zabbix.com/zabbix-official-repo.key | apt-key add - \
        && echo "deb http://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian buster main" >>/etc/apt/sources.list \
        && echo "deb-src http://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian buster main" >>/etc/apt/sources.list \
        && apt-get update -y \
        && apt-get install -y --no-install-recommends zabbix-release \
    ; else \
        curl https://repo.zabbix.com/zabbix-official-repo.key | apt-key add - \
        && echo "deb https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/raspbian buster main" >>/etc/apt/sources.list \
        && echo "deb-src https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/raspbian buster main" >>/etc/apt/sources.list \
        && apt-get update -y \
        && wget https://repo.zabbix.com/zabbix/5.2/raspbian/pool/main/z/zabbix-release/zabbix-release_5.2-1+debian$(cut -d"." -f1 /etc/debian_version)_all.deb \
        && dpkg -i zabbix-release_5.2-1+debian$(cut -d"." -f1 /etc/debian_version)_all.deb \
    ; fi
      
RUN apt-get install -y --no-install-recommends zabbix-agent && \
    rm -rf /etc/zabbix/zabbix-agentd.conf.d/*
      
RUN curl -ksSLo /usr/local/bin/MailHog https://github.com/mailhog/MailHog/releases/download/v1.0.0/MailHog_linux_${TARGETARCH} && \
    curl -ksSLo /usr/local/bin/mhsendmail https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_${TARGETARCH} && \
    chmod +x /usr/local/bin/MailHog && \
    chmod +x /usr/local/bin/mhsendmail && \
    useradd -r -s /bin/false -d /nonexistent mailhog && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/* /root/.gnupg /var/log/* /etc/logrotate.d && \
    mkdir -p /assets/cron && \
    rm -rf /etc/timezone && \
    ln -snf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    echo '%zabbix ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

### S6 installation
RUN if [ "$TARGETARCH" = "amd64" ] ; then \
        curl -ksSL https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-${TARGETARCH}.tar.gz | tar xfz - --strip 0 -C / \
    ; else \
        curl -ksSL https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-arm.tar.gz | tar xfz - --strip 0 -C / \
    ; fi

### Add users
RUN adduser --home /app --gecos "Node User" --disabled-password nodejs && \
\
### Install NodeJS
    wget --no-check-certificate -qO - https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo 'deb https://deb.nodesource.com/node_10.x buster main' > /etc/apt/sources.list.d/nodesource.list && \
    echo 'deb-src https://deb.nodesource.com/node_10.x buster main' >> /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y \
            nodejs \
            yarn \
            && \
    \
    apt-get clean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

### Add folders
ADD debian-buster/install /

### Pin libxml2 packages to Debian repositories
RUN c_rehash && \
    echo "Package: libxml2*" > /etc/apt/preferences.d/libxml2 && \
    echo "Pin: release o=Debian,n=buster" >> /etc/apt/preferences.d/libxml2 && \
    echo "Pin-Priority: 501" >> /etc/apt/preferences.d/libxml2 && \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=TRUE && \
    \
### Install dependencies
    set -x && \
    curl https://packages.sury.org/php/apt.gpg | apt-key add - && \
    echo "deb https://packages.sury.org/php/ buster main" > /etc/apt/sources.list.d/deb.sury.org.list && \
    echo "deb http://ftp.us.debian.org/debian/ buster main" > /etc/apt/sources.list.d/backports.list && \
    echo "deb-src http://ftp.us.debian.org/debian/ buster main" >> /etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    apt-get -o Dpkg::Options::="--force-confold" upgrade -y

COPY --from=builder /usr/local/lib/libmaodbc.so /usr/local/lib/libmaodbc.so
COPY --from=builder /usr/local/share/doc/mariadb_connector_odbc/COPYING /usr/local/share/doc/mariadb_connector_odbc/COPYING
COPY --from=builder /usr/local/share/doc/mariadb_connector_odbc/README /usr/local/share/doc/mariadb_connector_odbc/README
COPY --from=builder /usr/local/lib/mariadb/plugin/dialog.so /usr/local/lib/mariadb/plugin/dialog.so
COPY --from=builder /usr/local/lib/mariadb/plugin/caching_sha2_password.so /usr/local/lib/mariadb/plugin/caching_sha2_password.so
COPY --from=builder /usr/local/lib/mariadb/plugin/sha256_password.so /usr/local/lib/mariadb/plugin/sha256_password.so
COPY --from=builder /usr/local/lib/mariadb/plugin/mysql_clear_password.so /usr/local/lib/mariadb/plugin/mysql_clear_password.so
COPY --from=builder /usr/local/include/mariadb/mariadb_com.h /usr/local/include/mariadb/mariadb_com.h
COPY --from=builder /usr/local/include/mariadb/mysql.h /usr/local/include/mariadb/mysql.h
COPY --from=builder /usr/local/include/mariadb/mariadb_stmt.h /usr/local/include/mariadb/mariadb_stmt.h
COPY --from=builder /usr/local/include/mariadb/ma_pvio.h /usr/local/include/mariadb/ma_pvio.h
COPY --from=builder /usr/local/include/mariadb/ma_tls.h /usr/local/include/mariadb/ma_tls.h
COPY --from=builder /usr/local/include/mariadb/mariadb_version.h /usr/local/include/mariadb/mariadb_version.h
COPY --from=builder /usr/local/include/mariadb/ma_list.h /usr/local/include/mariadb/ma_list.h
COPY --from=builder /usr/local/include/mariadb/errmsg.h /usr/local/include/mariadb/errmsg.h
COPY --from=builder /usr/local/include/mariadb/mariadb_dyncol.h /usr/local/include/mariadb/mariadb_dyncol.h
COPY --from=builder /usr/local/include/mariadb/mariadb_ctype.h /usr/local/include/mariadb/mariadb_ctype.h
COPY --from=builder /usr/local/include/mariadb/mysql/client_plugin.h /usr/local/include/mariadb/mysql/client_plugin.h
COPY --from=builder /usr/local/include/mariadb/mysql/plugin_auth_common.h /usr/local/include/mariadb/mysql/plugin_auth_common.h
COPY --from=builder /usr/local/include/mariadb/mysql/plugin_auth.h /usr/local/include/mariadb/mysql/plugin_auth.h
COPY --from=builder /usr/local/include/mariadb/mariadb/ma_io.h /usr/local/include/mariadb/mariadb/ma_io.h
COPY --from=builder /usr/local/lib/mariadb/libmysqlclient.so /usr/local/lib/mariadb/libmysqlclient.so
COPY --from=builder /usr/local/lib/mariadb/libmysqlclient_r.so /usr/local/lib/mariadb/libmysqlclient_r.so
COPY --from=builder /usr/local/lib/mariadb/libmysqlclient.a /usr/local/lib/mariadb/libmysqlclient.a
COPY --from=builder /usr/local/lib/mariadb/libmysqlclient_r.a /usr/local/lib/mariadb/libmysqlclient_r.a
COPY --from=builder /usr/local/lib/mariadb/libmariadbclient.a /usr/local/lib/mariadb/libmariadbclient.a
COPY --from=builder /usr/local/lib/mariadb/libmariadb.so.3 /usr/local/lib/mariadb/libmariadb.so.3
COPY --from=builder /usr/local/lib/mariadb/libmariadb.so /usr/local/lib/mariadb/libmariadb.so
COPY --from=builder /usr/local/bin/mariadb_config /usr/local/bin/mariadb_config
COPY --from=builder /usr/local/lib/pkgconfig/libmariadb.pc /usr/local/lib/pkgconfig/libmariadb.pc

COPY --from=builder /usr/include/spandsp /usr/include/spandsp
COPY --from=builder /usr/include/spandsp.h /usr/include/spandsp.h
COPY --from=builder /usr/lib/pkgconfig/spandsp.pc /usr/lib/pkgconfig/spandsp.pc
COPY --from=builder /usr/lib/libspandsp.a /usr/lib/libspandsp.a
COPY --from=builder /usr/lib/libspandsp.la /usr/lib/libspandsp.la
COPY --from=builder /usr/lib/libspandsp.so /usr/lib/libspandsp.so
COPY --from=builder /usr/lib/libspandsp.so.2 /usr/lib/libspandsp.so.2
COPY --from=builder /usr/lib/libspandsp.so.2.0.0 /usr/lib/libspandsp.so.2.0.0

COPY --from=builder /usr/include/asterisk /usr/include/asterisk
COPY --from=builder /usr/share/locale/ast /usr/share/locale/ast
COPY --from=builder /usr/share/man/man8/asterisk.8 /usr/share/man/man8/asterisk.8
COPY --from=builder /usr/share/man/man8/astdb2bdb.8 /usr/share/man/man8/astdb2bdb.8
COPY --from=builder /usr/share/man/man8/astgenkey.8 /usr/share/man/man8/astgenkey.8
COPY --from=builder /usr/share/man/man8/astdb2sqlite3.8 /usr/share/man/man8/astdb2sqlite3.8
COPY --from=builder /usr/share/i18n/locales/ast_ES /usr/share/i18n/locales/ast_ES
COPY --from=builder /usr/share/man/man8/asterisk.8 /usr/share/man/man8/asterisk.8
COPY --from=builder /usr/share/man/man8/safe_asterisk.8 /usr/share/man/man8/safe_asterisk.8
COPY --from=builder /usr/sbin/safe_asterisk /usr/sbin/safe_asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/sbin/rasterisk /usr/sbin/rasterisk
COPY --from=builder /usr/sbin/astcanary /usr/sbin/astcanary
COPY --from=builder /usr/sbin/astdb2bdb /usr/sbin/astdb2bdb
COPY --from=builder /usr/sbin/astdb2sqlite3 /usr/sbin/astdb2sqlite3
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/sbin/astgenkey /usr/sbin/astgenkey
COPY --from=builder /usr/sbin/astversion /usr/sbin/astversion
COPY --from=builder /usr/lib/libasteriskpj.so /usr/lib/libasteriskpj.so
COPY --from=builder /usr/lib/libasteriskpj.so.2 /usr/lib/libasteriskpj.so.2
COPY --from=builder /usr/lib/libasteriskssl.so /usr/lib/libasteriskssl.so
COPY --from=builder /usr/lib/libasteriskssl.so.1 /usr/lib/libasteriskssl.so.1
COPY --from=builder /usr/lib/pkgconfig/asterisk.pc /usr/lib/pkgconfig/asterisk.pc
COPY --from=builder /usr/lib/asterisk /usr/lib/asterisk
COPY --from=builder /usr/lib/python3/dist-packages/fail2ban/tests/files/logs/asterisk /usr/lib/python3/dist-packages/fail2ban/tests/files/logs/asterisk
COPY --from=builder /etc/rc6.d/K01asterisk /etc/rc6.d/K01asterisk
COPY --from=builder /etc/default/asterisk /etc/default/asterisk
COPY --from=builder /etc/rc5.d/S01asterisk /etc/rc5.d/S01asterisk
COPY --from=builder /etc/rc4.d/S01asterisk /etc/rc4.d/S01asterisk
COPY --from=builder /etc/rc0.d/K01asterisk /etc/rc0.d/K01asterisk
COPY --from=builder /etc/rc3.d/S01asterisk /etc/rc3.d/S01asterisk
COPY --from=builder /etc/init.d/asterisk /etc/init.d/asterisk
COPY --from=builder /etc/rc1.d/K01asterisk /etc/rc1.d/K01asterisk
COPY --from=builder /etc/rc2.d/S01asterisk /etc/rc2.d/S01asterisk
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /etc/fail2ban/filter.d/asterisk.conf /etc/fail2ban/filter.d/asterisk.conf
COPY --from=builder /run/asterisk /run/asterisk
COPY --from=builder /var/spool/asterisk /var/spool/asterisk
COPY --from=builder /var/log/asterisk /var/log/asterisk
COPY --from=builder /var/lib/asterisk /var/lib/asterisk

COPY --from=builder /usr/include/bcg729 /usr/include/bcg729
COPY --from=builder /lib/libbcg729.a /lib/libbcg729.a
COPY --from=builder /lib/libbcg729.la /lib/libbcg729.la
COPY --from=builder /lib/libbcg729.so /lib/libbcg729.so
COPY --from=builder /lib/libbcg729.so.0 /lib/libbcg729.so.0 
COPY --from=builder /lib/libbcg729.so.0.0.0 /lib/libbcg729.so.0.0.0
COPY --from=builder /lib/pkgconfig/libbcg729.pc /lib/pkgconfig/libbcg729.pc

ADD asterisk_runtime_deps /usr/src/

### Install runtime dependencies
RUN apt-get install --no-install-recommends -y `cat /usr/src/asterisk_runtime_deps | sed 's/${PHP_VERSION}/'"$PHP_VERSION"'/g'`

RUN apt-get install -y usbutils

### Add users
RUN addgroup --gid 2600 asterisk && \
    adduser --uid 2600 --gid 2600 --gecos "Asterisk User" --disabled-password asterisk

### Cleanup
RUN mkdir -p /var/run/fail2ban && \
    cd / && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /usr/src/* /tmp/* /etc/cron* && \
    rm -rf /var/lib/apt/lists/*

### FreePBX hacks
RUN sed -i -e "s/memory_limit = 128M/memory_limit = 256M/g" /etc/php/${PHP_VERSION}/apache2/php.ini && \
    sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/${PHP_VERSION}/apache2/php.ini && \
    a2disconf other-vhosts-access-log.conf && \
    a2enmod rewrite && \
    a2enmod headers && \
    rm -rf /var/log/* && \
    mkdir -p /var/log/asterisk && \
    mkdir -p /var/log/apache2 && \
    mkdir -p /var/log/httpd && \
    \
### Zabbix setup
    echo '%zabbix ALL=(asterisk) NOPASSWD:/usr/sbin/asterisk' >> /etc/sudoers && \
    \
### Setup for data persistence
    mkdir -p /assets/config/var/lib/ /assets/config/home/ && \
    mv /home/asterisk /assets/config/home/ && \
    ln -s /data/home/asterisk /home/asterisk && \
    mv /var/lib/asterisk /assets/config/var/lib/ && \
    ln -s /data/var/lib/asterisk /var/lib/asterisk && \
    ln -s /data/usr/local/fop2 /usr/local/fop2 && \
    mkdir -p /assets/config/var/run/ && \
    mv /var/run/asterisk /assets/config/var/run/ && \
    mv /var/lib/mysql /assets/config/var/lib/ && \
    mkdir -p /assets/config/var/spool && \
    mv /var/spool/cron /assets/config/var/spool/ && \
    ln -s /data/var/spool/cron /var/spool/cron && \
    ln -s /data/var/run/asterisk /var/run/asterisk && \
    rm -rf /var/spool/asterisk && \
    ln -s /data/var/spool/asterisk /var/spool/asterisk && \
    rm -rf /etc/asterisk && \
    ln -s /data/etc/asterisk /etc/asterisk

ADD freepbx-15/install /

### Networking configuration
EXPOSE 80 443 4445 4569 5060/udp 5160/udp 5061 5161 8001 8003 8008 8009 8025 ${RTP_START}-${RTP_FINISH}/udp 1025 8025 10050/TCP

### Entrypoint configuration
ENTRYPOINT ["/init"]
