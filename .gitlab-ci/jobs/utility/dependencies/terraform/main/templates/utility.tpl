#!/bin/bash
sudo apt install -y apache2-utils
mkdir -p data/registry data/repository/git/umbrella.git data/proxy auth

#Hash registry credentials
htpasswd -Bbn ${utility_username} ${utility_password} > $(pwd)/auth/htpasswd 
chmod 644 $(pwd)/auth/htpasswd

# Run docker registry

docker run -d \
    -p 5000:5000 \
    --restart=always \
    --name registry \
    -v "$(pwd)"/auth:/auth \
    -v "$(pwd)"/data/registry:/data \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data \
    registry:2

cat << 'EOF' > "$(pwd)"/data/repository/default.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /data;

    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ (/.*) {
        client_max_body_size 0;
        auth_basic "Git Login";
        auth_basic_user_file "/auth/htpasswd";
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /usr/libexec/git-core/git-http-backend;
        fastcgi_param GIT_HTTP_EXPORT_ALL "";
        fastcgi_param GIT_PROJECT_ROOT /data;
        fastcgi_param REMOTE_USER $remote_user;
        fastcgi_param PATH_INFO $1;
        fastcgi_pass  unix:/var/run/fcgiwrap.socket;
    }
}
EOF

cat << EOF > "$(pwd)"/data/repository/start.sh
#!/bin/sh
spawn-fcgi -M 666 -s /var/run/fcgiwrap.socket /usr/bin/fcgiwrap &
/usr/sbin/nginx -c /etc/nginx/nginx.conf -g "daemon off;"
EOF

cat << EOF > "$(pwd)"/data/repository/Dockerfile
FROM nginx:alpine
EXPOSE 80
RUN apk add --no-cache git git-daemon spawn-fcgi fcgiwrap
COPY default.conf /etc/nginx/conf.d/default.conf
COPY start.sh /usr/bin/start
RUN chmod +x /usr/bin/start
CMD ["/usr/bin/start"]
EOF

docker build -t simplegit:latest "$(pwd)"/data/repository

docker run \
    -v "$(pwd)"/data/repository/git:/data \
    simplegit:latest \
    -- sh -c "cd /data/umbrella.git && chown -R nginx:nginx . && chmod -R 755 . && git init . && git update-server-info"

docker run -d \
    -p 5005:80 \
    --restart always \
    --name repository \
    -v "$(pwd)"/auth:/auth \
    -v "$(pwd)"/data/repository/git:/data \
    simplegit:latest

cat << 'EOF' > "$(pwd)"/data/proxy/tinyproxy.conf
User root
Group root

Port 8888
Listen 0.0.0.0
BindSame yes

Timeout 600

DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogLevel Info
PidFile "/var/run/tinyproxy/tinyproxy.pid"

MaxClients 100
MinSpareServers 2
MaxSpareServers 5
StartServers 2
MaxRequestsPerChild 0

ConnectPort 8888
ConnectPort 80
ConnectPort 443
ConnectPort 563
EOF

cat << 'EOF' > "$(pwd)"/data/proxy/Dockerfile
FROM alpine:latest
RUN apk add --no-cache tinyproxy
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
EXPOSE 8888
CMD ["/usr/bin/tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
EOF

docker build -t simpleproxy:latest "$(pwd)"/data/proxy

docker run -d \
    -p 8888:8888 \
    --restart always \
    --name simpleproxy \
    simpleproxy:latest