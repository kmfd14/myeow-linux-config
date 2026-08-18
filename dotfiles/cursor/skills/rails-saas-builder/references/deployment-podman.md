# Podman Deployment Patterns

## Container Configuration

### Dockerfile for Rails 8.1.2
```dockerfile
# Use official Ruby image
FROM ruby:3.3.7-slim

# Install dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    libvips \
    node-gyp \
    pkg-config \
    postgresql-client \
    python-is-python3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Node.js and Yarn
ARG NODE_VERSION=20.18.1
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    npm install -g yarn@1 && \
    rm -rf /tmp/node-build-master

# Set working directory
WORKDIR /rails

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Install JavaScript dependencies
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY . .

# Precompile assets
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Create non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Set ownership
RUN chown -R rails:rails /rails

# Switch to non-root user
USER rails:rails

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start server
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
```

### .dockerignore
```
.git
.gitignore
.github
.dockerignore
.env*
node_modules/
log/*
tmp/*
*.log
*.pid
storage/*
public/assets
public/packs
coverage/
.bundle
vendor/bundle
```

## Podman Commands

### Build Image
```bash
# Build image
podman build -t myapp:latest .

# Build with specific platform (for production)
podman build --platform linux/amd64 -t myapp:latest .
```

### Run Development Container
```bash
# Run with volume mounts for development
podman run -d \
  --name myapp_dev \
  -p 3000:3000 \
  -v $(pwd):/rails \
  -e RAILS_ENV=development \
  -e DATABASE_URL="postgresql://user:password@host.containers.internal:5432/myapp_dev" \
  myapp:latest
```

### Run Production Container
```bash
# Run production container
podman run -d \
  --name myapp_prod \
  -p 3000:3000 \
  --restart=unless-stopped \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  -e DATABASE_URL="${DATABASE_URL}" \
  -e RAILS_MASTER_KEY="${RAILS_MASTER_KEY}" \
  myapp:latest

# Or use systemd service (recommended)
```

## Systemd Service (Production)

### /etc/systemd/system/myapp.service
```ini
[Unit]
Description=MyApp Rails Application
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/myapp
EnvironmentFile=/home/deploy/myapp/.env.production
ExecStartPre=-/usr/bin/podman stop myapp
ExecStartPre=-/usr/bin/podman rm myapp
ExecStart=/usr/bin/podman run --name myapp \
  -p 127.0.0.1:3000:3000 \
  --env-file /home/deploy/myapp/.env.production \
  myapp:latest
ExecStop=/usr/bin/podman stop -t 10 myapp
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start
```bash
sudo systemctl daemon-reload
sudo systemctl enable myapp
sudo systemctl start myapp
sudo systemctl status myapp
```

## Sidekiq Container

### Separate Sidekiq Container
```bash
# Run Sidekiq in separate container
podman run -d \
  --name myapp_sidekiq \
  --restart=unless-stopped \
  -e RAILS_ENV=production \
  -e DATABASE_URL="${DATABASE_URL}" \
  -e REDIS_URL="${REDIS_URL}" \
  -e RAILS_MASTER_KEY="${RAILS_MASTER_KEY}" \
  myapp:latest \
  bundle exec sidekiq
```

### Systemd Service for Sidekiq
```ini
[Unit]
Description=MyApp Sidekiq Worker
After=network.target postgresql.service redis.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/myapp
EnvironmentFile=/home/deploy/myapp/.env.production
ExecStartPre=-/usr/bin/podman stop myapp_sidekiq
ExecStartPre=-/usr/bin/podman rm myapp_sidekiq
ExecStart=/usr/bin/podman run --name myapp_sidekiq \
  --env-file /home/deploy/myapp/.env.production \
  myapp:latest \
  bundle exec sidekiq
ExecStop=/usr/bin/podman stop -t 10 myapp_sidekiq
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Nginx Reverse Proxy

### /etc/nginx/sites-available/myapp
```nginx
upstream myapp {
    server 127.0.0.1:3000 fail_timeout=0;
}

server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root /home/deploy/myapp/public;

    client_max_body_size 10M;

    location / {
        try_files $uri @app;
    }

    location @app {
        proxy_pass http://myapp;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $http_host;
        proxy_redirect off;
        proxy_buffering off;
    }

    # Cable for Action Cable
    location /cable {
        proxy_pass http://myapp;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
    }

    location ~ ^/(assets|packs)/ {
        gzip_static on;
        expires max;
        add_header Cache-Control public;
    }

    error_page 500 502 503 504 /500.html;
    error_page 404 /404.html;
    error_page 422 /422.html;
}
```

## Database (Non-Containerized)

### PostgreSQL Setup
```bash
# Install PostgreSQL (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# Create database user
sudo -u postgres createuser -s myapp

# Set password
sudo -u postgres psql
\password myapp

# Create database
sudo -u postgres createdb -O myapp myapp_production
```

### Database Configuration
```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  url: <%= ENV['DATABASE_URL'] %>
```

## Environment Variables

### .env.production (example)
```bash
RAILS_ENV=production
SECRET_KEY_BASE=your_secret_key_here
RAILS_MASTER_KEY=your_master_key_here

# Database
DATABASE_URL=postgresql://myapp:password@localhost:5432/myapp_production

# Redis
REDIS_URL=redis://localhost:6379/0

# Payment Providers
PAYMONGO_PUBLIC_KEY=pk_test_...
PAYMONGO_SECRET_KEY=sk_test_...
MAYA_PUBLIC_KEY=pk-...
MAYA_SECRET_KEY=sk-...
PAYPAL_CLIENT_ID=...
PAYPAL_SECRET=...

# Email
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

## Deployment Workflow

### Zero-Downtime Deployment Script
```bash
#!/bin/bash
# deploy.sh

set -e

echo "Building new image..."
podman build -t myapp:latest .

echo "Tagging with timestamp..."
TIMESTAMP=$(date +%Y%m%d%H%M%S)
podman tag myapp:latest myapp:$TIMESTAMP

echo "Running database migrations..."
podman run --rm \
  --env-file .env.production \
  myapp:latest \
  bundle exec rails db:migrate

echo "Restarting application..."
sudo systemctl restart myapp
sudo systemctl restart myapp_sidekiq

echo "Waiting for health check..."
sleep 10

if curl -f http://localhost:3000/up; then
  echo "Deployment successful!"
else
  echo "Health check failed, rolling back..."
  podman tag myapp:previous myapp:latest
  sudo systemctl restart myapp
  exit 1
fi

echo "Cleaning up old images..."
podman image prune -f
```

## Monitoring

### Health Check Endpoint
```ruby
# config/routes.rb
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
end
```

### Log Management
```bash
# View logs
podman logs -f myapp
podman logs -f myapp_sidekiq

# Log rotation with journald
sudo journalctl -u myapp.service -f
```

## Backup Strategy

### Database Backup Script
```bash
#!/bin/bash
# backup_db.sh

BACKUP_DIR="/home/deploy/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/myapp_$DATE.sql.gz"

mkdir -p $BACKUP_DIR

pg_dump -h localhost -U myapp myapp_production | gzip > $BACKUP_FILE

# Keep only last 7 days
find $BACKUP_DIR -name "myapp_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
```

### Automated Backups (Cron)
```bash
# Add to crontab
0 2 * * * /home/deploy/scripts/backup_db.sh
```
