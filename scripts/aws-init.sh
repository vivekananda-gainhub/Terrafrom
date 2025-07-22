#!/bin/bash
set -eux

# Log everything to /var/log/user-data.log
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Preconfigure Postfix
echo "postfix postfix/mailname string example.com" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections

# Update & install packages
apt-get update
apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
libreadline-dev libsqlite3-dev wget curl llvm libncurses-dev \
xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git \
libpq-dev libsasl2-dev libldap2-dev ccze node-less bash-completion nginx certbot gnupg2 lsb-release

# Install PostgreSQL 13
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-13
systemctl enable postgresql
systemctl start postgresql

# Create ghuser
useradd -m -U -r -s /bin/bash ghuser

# Install pyenv for ghuser
sudo -i -u ghuser bash <<'EOF'
curl https://pyenv.run | bash

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init --path)"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"

pyenv install 3.9.2
pyenv virtualenv 3.9.2 ghuser-env
EOF

# Create log directory
mkdir -p /var/log/ghuser
chown ghuser:ghuser /var/log/ghuser

# Generate strong DH param for SSL
openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# Let's Encrypt dir for ACME challenges
mkdir -p /var/lib/letsencrypt/.well-known
chgrp www-data /var/lib/letsencrypt
chmod g+s /var/lib/letsencrypt

# NGINX snippet: Let's Encrypt challenge
mkdir -p /etc/nginx/snippets
cat <<EOF > /etc/nginx/snippets/letsencrypt.conf
location ^~ /.well-known/acme-challenge/ {
    allow all;
    root /var/lib/letsencrypt/;
    default_type "text/plain";
    try_files \$uri =404;
}
EOF

# NGINX snippet: SSL settings
cat <<EOF > /etc/nginx/snippets/ssl.conf
ssl_dhparam /etc/ssl/certs/dhparam.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 30s;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;
EOF
