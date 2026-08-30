#!/usr/bin/env bash
set -euo pipefail

readonly APP_DIR="${1:-$(pwd)}"
readonly PRIMARY_DOMAIN="image-d.shuangdeng.space"
readonly APP_PORT="${CHATGPT2API_PORT:-3010}"
readonly OPENRESTY_CONTAINER="${OPENRESTY_CONTAINER:-1Panel-openresty-NhRG}"
readonly OPENRESTY_CONF_DIR="/opt/1panel/www/conf.d"
readonly OPENRESTY_SSL_DIR="/opt/1panel/apps/openresty/openresty/conf/ssl/${PRIMARY_DOMAIN}"
readonly CERT_LIVE_DIR="/etc/letsencrypt/live/${PRIMARY_DOMAIN}"
readonly ACME_WEBROOT="/opt/1panel/www/sites/acme"

cd "$APP_DIR"

write_environment() {
    local auth_key_file="$APP_DIR/.deploy-auth-key"
    if [[ ! -f "$auth_key_file" ]]; then
        if [[ ! -f .env ]]; then
            echo "Missing .deploy-auth-key and .env; configure CHATGPT2API_AUTH_KEY before deploying." >&2
            exit 1
        fi
        return
    fi

    local auth_key
    auth_key="$(<"$auth_key_file")"
    rm -f "$auth_key_file"
    if [[ -z "$auth_key" || "$auth_key" == *$'\n'* || "$auth_key" == *$'\r'* ]]; then
        echo "CHATGPT2API_AUTH_KEY must be a single non-empty line." >&2
        exit 1
    fi

    umask 077
    cat >.env <<EOF
CHATGPT2API_AUTH_KEY=${auth_key}
CHATGPT2API_BASE_URL=https://${PRIMARY_DOMAIN}
CHATGPT2API_PORT=${APP_PORT}
STORAGE_BACKEND=json
EOF
}

reload_openresty() {
    docker exec "$OPENRESTY_CONTAINER" nginx -t
    docker kill --signal=HUP "$OPENRESTY_CONTAINER" >/dev/null
}

install_certificate() {
    sudo install -d -m 755 "$OPENRESTY_SSL_DIR"
    sudo install -m 644 "$CERT_LIVE_DIR/fullchain.pem" "$OPENRESTY_SSL_DIR/fullchain.pem"
    sudo install -m 600 "$CERT_LIVE_DIR/privkey.pem" "$OPENRESTY_SSL_DIR/privkey.pem"
}

install_renewal_hook() {
    local hook_path="/etc/letsencrypt/renewal-hooks/deploy/image-openresty.sh"
    sudo tee "$hook_path" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PRIMARY_DOMAIN="image-d.shuangdeng.space"
SSL_DIR="/opt/1panel/apps/openresty/openresty/conf/ssl/${PRIMARY_DOMAIN}"

if [[ "${RENEWED_LINEAGE:-}" == "/etc/letsencrypt/live/${PRIMARY_DOMAIN}" ]]; then
    install -d -m 755 "$SSL_DIR"
    install -m 644 "$RENEWED_LINEAGE/fullchain.pem" "$SSL_DIR/fullchain.pem"
    install -m 600 "$RENEWED_LINEAGE/privkey.pem" "$SSL_DIR/privkey.pem"
    docker kill --signal=HUP 1Panel-openresty-NhRG >/dev/null
fi
EOF
    sudo chmod 755 "$hook_path"
}

write_environment
mkdir -p data
if [[ ! -f config.json ]]; then
    printf '{}\n' >config.json
    chmod 600 config.json
fi

docker compose -f docker-compose.production.yml up -d --build --remove-orphans

# An HTTP virtual host keeps the app reachable while DNS and TLS are being set up.
if [[ ! -f "$CERT_LIVE_DIR/fullchain.pem" ]]; then
    sudo install -m 644 "deploy/openresty/${PRIMARY_DOMAIN}.http.conf" "$OPENRESTY_CONF_DIR/${PRIMARY_DOMAIN}.conf"
    reload_openresty
    if getent ahostsv4 "$PRIMARY_DOMAIN" >/dev/null; then
        sudo mkdir -p "$ACME_WEBROOT"
        sudo certbot certonly --webroot -w "$ACME_WEBROOT" --cert-name "$PRIMARY_DOMAIN" -d "$PRIMARY_DOMAIN" --non-interactive --agree-tos
    else
        echo "TLS pending: point ${PRIMARY_DOMAIN} to this server, then rerun the workflow." >&2
    fi
fi

if [[ -f "$CERT_LIVE_DIR/fullchain.pem" ]]; then
    install_certificate
    install_renewal_hook
    sudo install -m 644 "deploy/openresty/${PRIMARY_DOMAIN}.conf" "$OPENRESTY_CONF_DIR/${PRIMARY_DOMAIN}.conf"
    reload_openresty
fi

for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT}/" >/dev/null; then
        if [[ -f "$CERT_LIVE_DIR/fullchain.pem" ]]; then
            echo "Deployment completed: https://${PRIMARY_DOMAIN}"
        else
            echo "Deployment completed locally; HTTPS is pending DNS setup."
        fi
        exit 0
    fi
    sleep 2
done

docker compose -f docker-compose.production.yml logs --tail=100 app >&2
exit 1
