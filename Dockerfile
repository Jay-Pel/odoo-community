# Dockerfile for Odoo v18.0 Community Edition
# Optimized for Google Cloud Run deployment
FROM python:3.11-slim-bookworm

LABEL maintainer="Jay-Pel <jay@pelletier.ca>"
LABEL version="18.0"
LABEL description="Odoo v18.0 Community Edition for Cloud Run"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ODOO_RC=/etc/odoo/odoo.conf \
    ODOO_DATA_DIR=/var/lib/odoo \
    ODOO_LOG_DIR=/var/log/odoo

# Install system dependencies
RUN set -x; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-magic \
        python3-num2words \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        xz-utils \
        git \
        build-essential \
        libffi-dev \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg62-turbo-dev \
        zlib1g-dev \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && echo 'f681f3cfea0018b9e47bbbf2b6f3de23bde8b81ab47a5633eda157ba9fb29c09 wkhtmltox.deb' | sha256sum -c - \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf wkhtmltox.deb \
    && apt-get purge -y --auto-remove build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create odoo user
RUN adduser --system --quiet --shell=/bin/bash --home=/var/lib/odoo --gecos 'ODOO' --group odoo \
    && mkdir -p /etc/odoo \
    && mkdir -p /var/lib/odoo \
    && mkdir -p /var/log/odoo \
    && mkdir -p /mnt/extra-addons \
    && chown odoo:odoo /etc/odoo \
    && chown odoo:odoo /var/lib/odoo \
    && chown odoo:odoo /var/log/odoo \
    && chown odoo:odoo /mnt/extra-addons

# Copy Odoo source code and scripts
COPY --chown=odoo:odoo . /opt/odoo
COPY --chown=odoo:odoo scripts/startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Set working directory
WORKDIR /opt/odoo

# Install Python dependencies
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir -r requirements.txt \
    && pip3 install --no-cache-dir psycopg2-binary

# Create Odoo configuration file
RUN echo "[options]\n\
; Database configuration\n\
db_host = \n\
db_port = 5432\n\
db_user = odoo\n\
db_password = \n\
; Path configuration\n\
addons_path = /opt/odoo/addons,/mnt/extra-addons\n\
data_dir = /var/lib/odoo\n\
logfile = /var/log/odoo/odoo.log\n\
; Server configuration\n\
http_port = 8080\n\
workers = 0\n\
max_cron_threads = 1\n\
; Security\n\
list_db = False\n\
admin_passwd = \n\
; Performance\n\
limit_memory_hard = 2684354560\n\
limit_memory_soft = 2147483648\n\
limit_request = 8192\n\
limit_time_cpu = 600\n\
limit_time_real = 1200\n\
; Logging\n\
log_level = info\n\
log_handler = :INFO\n\
; Proxy mode (required for Cloud Run)\n\
proxy_mode = True\n\
" > /etc/odoo/odoo.conf \
    && chown odoo:odoo /etc/odoo/odoo.conf \
    && chmod 640 /etc/odoo/odoo.conf

# Set proper permissions
RUN chown -R odoo:odoo /opt/odoo

# Expose port 8080 (Cloud Run standard)
EXPOSE 8080

# Switch to odoo user
USER odoo

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
    CMD curl -f http://localhost:8080/web/health || exit 1

# Default command
CMD ["/usr/local/bin/startup.sh"]
