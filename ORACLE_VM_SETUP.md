# Deploying Personal IPO Tracker Side-by-Side on Oracle Cloud VM

Your Oracle Cloud VM (`132.226.186.196`) currently runs:
- **NithConnect**: Port `3000` (Postgres on `5432`)
- **MoneyGame**: Port `4000` (Postgres on `5433`)

This deployment places **Personal IPO Allotment Tracker** alongside them cleanly with **zero port or database conflicts**:
- **IPO Backend**: Host Port `5000` (bound to `127.0.0.1:5000`)
- **IPO Postgres**: Isolated `ipo_network` (dedicated volume `ipo_pgdata`)
- **PEEK Microservice**: Isolated `ipo_network` (Port `8000`, internal only)

```bash
ubuntu@oracle-vm:~$ ls
MoneyGame    NithConnect    IPO    bin    lib
```

---

## Step 1: Copy IPO Project to Your Oracle VM

From your local development machine:

```bash
# Using rsync to transfer the project cleanly
rsync -avz --exclude 'node_modules' --exclude '.dart_tool' --exclude 'build' --exclude 'dist' /home/gulshan/Projects/IPO/ ubuntu@132.226.186.196:~/IPO/
```

Or push to GitHub and clone:

```bash
ssh ubuntu@132.226.186.196
git clone <YOUR_IPO_REPO_URL> IPO
```

---

## Step 2: Configure Production `.env`

On your Oracle VM:

```bash
cd ~/IPO
cp .env.oracle.example .env
nano .env
```

Generate secure 32+ character secrets for production:

```bash
# Generate keys:
openssl rand -base64 32 # Copy for PAN_ENCRYPTION_KEY
openssl rand -base64 32 # Copy for PAN_HMAC_KEY
openssl rand -base64 32 # Copy for JWT_SECRET
openssl rand -hex 16    # Copy for POSTGRES_PASSWORD
```

Ensure your `.env` contains:
```env
PORT=5000
HOST_BIND=127.0.0.1
NODE_ENV=production
POSTGRES_DB=ipo_db
POSTGRES_USER=ipo_user
POSTGRES_PASSWORD=<YOUR_HEX_PASSWORD>
PAN_ENCRYPTION_KEY=<YOUR_32_CHAR_BASE64_KEY>
PAN_HMAC_KEY=<YOUR_32_CHAR_BASE64_KEY>
JWT_SECRET=<YOUR_32_CHAR_BASE64_KEY>
PEEK_SERVICE_URL=http://ipo_peek:8000
```

---

## Step 3: Run One-Click Deployment

```bash
cd ~/IPO
./deploy.sh
```

This will automatically:
1. Build the PEEK Python 3.11 container with all registrar adapters.
2. Build the NestJS container with multi-stage production optimization.
3. Start isolated PostgreSQL 16 on `ipo_network`.
4. Wait for PostgreSQL readiness.
5. Push the Prisma relational schema and foreign keys.
6. Seed recent Mainboard & SME IPOs and initialize dynamic discovery.

Verify containers:
```bash
docker compose ps
```

You should see:
- `ipo_db`: `Up (healthy)`
- `ipo_peek`: `Up (healthy)`
- `ipo_app`: `Up (healthy)` - mapped to `127.0.0.1:5000`

---

## Step 4: Configure Nginx Reverse Proxy (SSL / HTTPS)

To expose the IPO Tracker API securely via your existing Nginx server on Oracle VM:

Edit `/etc/nginx/sites-available/default` (or create `/etc/nginx/sites-available/ipo.conf`):

```nginx
server {
    listen 80;
    server_name ipo.yourdomain.com; # Or 132-226-186-196.sslip.io/ipo/

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for async refresh scans
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Enable SSL using Certbot:
```bash
sudo certbot --nginx -d ipo.yourdomain.com
```

---

## Step 5: Connecting the Flutter App

When building the Flutter application for mobile or web:

```bash
cd ~/Projects/IPO/frontend

# For Web:
flutter build web --dart-define=API_BASE_URL=https://ipo.yourdomain.com

# For Android APK:
flutter build apk --release --dart-define=API_BASE_URL=https://ipo.yourdomain.com
```

---

## Step 6: Security and Backup Maintenance

1. **Database Backups**:
   ```bash
   docker compose exec -T ipo_db pg_dump -U ipo_user ipo_db > ~/backups/ipo_db_$(date +%F).sql
   ```
2. **Encrypted Keys Protection**:
   `PAN_ENCRYPTION_KEY` and `PAN_HMAC_KEY` should be securely backed up in a password manager. If lost, previously encrypted PANs cannot be decrypted.
3. **Logs**:
   Raw PAN values and sensitive external provider response payloads are strictly scrubbed by application logic and never printed to Docker logs.
