#!/usr/bin/env sh

# Validate environment variables

# Create ssh host key if not present
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -A
fi

# Setup gitolite at volume /var/lib/git
if [ ! -f "/var/lib/git/.ssh/authorized_keys" ]; then
  # Configure gitolite
  echo "$SSH_KEY" > "/tmp/$SSH_KEY_NAME.pub"
  su git -c "gitolite setup -pk \"/tmp/$SSH_KEY_NAME.pub\""
  rm "/tmp/$SSH_KEY_NAME.pub"
fi

if [ ! -d /etc/nginx/http.d ]; then
    install -d -m755 /etc/nginx/http.d || true
fi

# Init container
if [ ! -f /etc/nginx/http.d/cgit.conf ]; then
  # enable random git password
  GIT_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32)
  echo "git:$GIT_PASSWORD" | chpasswd

  # add web user (nginx) to gitolite group (git)
  adduser nginx git

  ## Config cgit interface
  cat > /etc/cgitrc <<- EOF
#
# cgit config
#

virtual-root=/

# Use a custom logo
logo=/cgit.png

# Specify the css url
css=/cgit.css

# Enable configuration from external management, for example: gitolite
enable-git-config=1

# Show extra links for each repository on the index page
enable-index-links=1

# Show owner
enable-index-owner=1

# Enable ASCII art commit history graph on the log pages
enable-commit-graph=1

# Allow http transport git clone
enable-http-clone=1

# Show number of affected files per commit on the log pages
enable-log-filecount=1

# Show number of added/removed lines per commit on the log pages
enable-log-linecount=1

# Enable statistics per week, month and quarter
max-stats=quarter

# Cache
cache-about-ttl=15
cache-dynamic-ttl=5
cache-repo-ttl=5
cache-root=/var/cache/cgit
cache-root-ttl=5
cache-scanrc-ttl=15
cache-size=0
cache-snapshot-ttl=5
cache-static-ttl=-1

# Sort items in the repo list case sensitively. Default value: "1"
case-sensitive-sort=1

# Specifies the maximum size of a blob to display HTML for in KBytes. Default value: "0" (limit disabled)
max-blob-size=2048

# Specifies the number of entries to list per page on the repository index page. Default value: "50".
max-repo-count=250


# Specifies the maximum number of repo description characters to display on the repository index page.
# Default value: "80"
max-repodesc-length=80

# Set the default maximum statistics period. Valid values are "week", "month", "quarter" and "year".
# If unspecified, statistics are disabled. Default value: none
max-stats=year

#
# List of common mimetypes
#

mimetype.gif=image/gif
mimetype.htm=text/html
mimetype.html=text/html
mimetype.ico=image/x-icon
mimetype.jpg=image/jpeg
mimetype.jpeg=image/jpeg
mimetype.md=text/markdown
mimetype.mng=video/x-mng
mimetype.ora=image/openraster
mimetype.pam=image/x-portable-arbitrarymap
mimetype.pbm=image/x-portable-bitmap
mimetype.pdf=application/pdf
mimetype.pgm=image/x-portable-graymap
mimetype.png=image/png
mimetype.pnm=image/x-portable-anymap
mimetype.ppm=image/x-portable-pixmap
mimetype.svg=image/svg+xml
mimetype.svgz=image/svg+xml
mimetype.tga=image/x-tga
mimetype.tif=image/tiff
mimetype.tiff=image/tiff
mimetype.webp=image/webp
mimetype.xbm=image/x-xbitmap
mimetype.xcf=image/x-xcf
mimetype.xpm=image/x-xpixmap

# Enable syntax highlighting and about formatting
source-filter=/usr/lib/cgit/filters/syntax-highlighting.py
about-filter=/usr/lib/cgit/filters/about-formatting.sh

#
# List of common readmes
#
readme=:README.md
readme=:readme.md
readme=:README.mkd
readme=:readme.mkd
readme=:README.rst
readme=:readme.rst
readme=:README.html
readme=:readme.html
readme=:README.htm
readme=:readme.htm
readme=:README.txt
readme=:readme.txt
readme=:README
readme=:readme
readme=:INSTALL.md
readme=:install.md
readme=:INSTALL.mkd
readme=:install.mkd
readme=:INSTALL.rst
readme=:install.rst
readme=:INSTALL.html
readme=:install.html
readme=:INSTALL.htm
readme=:install.htm
readme=:INSTALL.txt
readme=:install.txt
readme=:INSTALL
readme=:install

snapshots=$CGIT_SNAPSHOT

# Direct cgit to repository location managed by gitolite
remove-suffix=0
project-list=/var/lib/git/projects.list
section-from-path=1
scan-path=/var/lib/git/repositories
EOF

  # Append clone-prefix
  if [ ! -z "$CGIT_CLONE_PREFIX" ]; then
      echo "# Specify some default clone prefixes" >> /etc/cgitrc
      echo "clone-prefix=$CGIT_CLONE_PREFIX" >> /etc/cgitrc
  fi

  if [ ! -z "$CGIT_ROOT_TITLE" ]; then
      echo "# Set the title and heading of the repository index page" >> /etc/cgitrc
      echo "root-title=$CGIT_ROOT_TITLE" >> /etc/cgitrc
  fi

  if [ ! -z "$CGIT_DESC" ]; then
      echo "# Set description repository" >> /etc/cgitrc
      echo "root-desc=$CGIT_DESC" >> /etc/cgitrc
  fi

  # Using highlight syntax
  #sed -i.bak \
  #  -e "s#exec highlight --force -f -I -X -S #\#&#g" \
  #  -e "s#\#exec highlight --force -f -I -O xhtml#exec highlight --force --inline-css -f -I -O xhtml#g" \
  #  /usr/lib/cgit/filters/syntax-highlighting.sh

  # Nginx configuration
  rm -v /etc/nginx/http.d/default.conf || true
  cat > /etc/nginx/http.d/cgit.conf <<- EOF
  server {
    listen 80 default_server;
    server_name localhost;

    root /usr/share/webapps/cgit;
    try_files \$uri @cgit;

    location @cgit {
      include             fastcgi_params;

      # Path to the CGI script that comes with cgit
      fastcgi_param        SCRIPT_FILENAME \$document_root/cgit.cgi;

      fastcgi_param       PATH_INFO       \$uri;
      fastcgi_param       QUERY_STRING    \$args;
      fastcgi_param       QUERY_INFO      \$uri;
      fastcgi_param       HTTP_HOST       \$server_name;

      # Path to the socket file that is created/used by fcgiwrap
      fastcgi_pass        unix:/run/fcgiwrap/fcgiwrap.socket;
    }

    # Enable compression for JS/CSS/HTML, for improved client load times.
    # It might be nice to compress JSON/XML as returned by the API, but
    # leaving that out to protect against potential BREACH attack.
    gzip              on;
    gzip_vary         on;

    gzip_types        # text/html is always compressed by HttpGzipModule
                      text/css
                      application/javascript
                      font/truetype
                      font/opentype
                      application/vnd.ms-fontobject
                      image/svg+xml;
  }
EOF

fi

# Start sshd as detach, log to stderr (-e)
/usr/sbin/sshd -e

# launch fcgiwrap via spawn-fcgi, port 1234
spawn-fcgi -s /run/fcgiwrap/fcgiwrap.socket -f /usr/bin/fcgiwrap
chmod 660 /run/fcgiwrap/fcgiwrap.socket

# fix permissions gitolite
chown git:git /var/lib/git/.gitolite.rc
chmod 640 /var/lib/git/.gitolite.rc

# Start git-daemon
git daemon --detach --reuseaddr --base-path=/var/lib/git/repositories /var/lib/git/repositories

# Start nginx
exec nginx -g "daemon off;"
