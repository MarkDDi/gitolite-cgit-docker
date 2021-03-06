FROM alpine:latest
LABEL MAINTAINER="heckyel@riseup.net"

# Install needed packages
RUN set -xe \
  && apk add --no-cache --purge -uU \
    # Install gitolite
    gitolite git openssh \
    # install git-daemon
    git-daemon \
    # add nginx and cgit
    cgit nginx fcgiwrap spawn-fcgi \
    # python 3 pkg for highlight, about page
    py3-markdown py3-pygments \
    # tarballs support
    lzip xz zstd gzip bzip2 \
  # Create nginx folder
  && mkdir -p /run/nginx \
  # Clean up
  && rm -rf /var/cache/apk/* \
  && rm -rf /tmp/*

# Volume to store all ssh host key
VOLUME [ "/etc/ssh" ]

# Volume to store Gitolite data, used for Gitolite setup
VOLUME [ "/var/lib/git" ]

EXPOSE 22 80 9418
WORKDIR /var/lib/git

COPY cgit.css /usr/share/webapps/cgit/cgit.css
COPY md2html /usr/lib/cgit/filters/html-converters/md2html
COPY syntax-highlighting.py /usr/lib/cgit/filters/syntax-highlighting.py
COPY gitolite.rc /var/lib/git/.gitolite.rc
COPY entrypoint.sh /

RUN chmod u+x /usr/lib/cgit/filters/html-converters/md2html
RUN chmod u+x /usr/lib/cgit/filters/syntax-highlighting.py
RUN chmod u+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
