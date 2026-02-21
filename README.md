# Automated VPS Deployment with Git Hooks

A fully automated, zero-downtime deployment script designed for Monorepos containing a React/Vite Frontend (served via Nginx) and a Python/FastAPI/Uvicorn Backend (managed by PM2).

This system uses a **Blue-Green/Symlink** deployment strategy. Your application is built in a hidden temporary directory, and only when the build is 100% successful does the live "production" symlink switch over.

## Features
- **Zero Downtime:** Live traffic is served from the old folder until the exact millisecond the new one is ready.
- **Automated Rollbacks:** If a build fails, the deploy stops, the broken folder is deleted, and the live site is untouched.
- **One-Command Rollback:** Easily revert to any of the last 5 successful deployments with `./rollback.sh`.
- **Discord Notifications:** Get automatic success/failure alerts in your Discord channel.
- **Secure Secrets Management:** `.env` files are kept safely out of the Git repository.

---

## 🚀 1. Prerequisites

Before running this script, ensure your VPS has the necessary build tools installed:
- Git
- Node.js & npm (for building the React frontend)
- Python 3 & pip (for building the backend)
- PM2 (for managing the Uvicorn process)
- Nginx (for serving the React static files)

---

## 🛠️ 2. Installation & Setup

You only need to run this script **once**.

```bash
# Provide it executable permissions
chmod +x setup.sh

# Run the setup script
./setup.sh
```

You will be asked a series of prompts (your project name, VPS user, directories, Discord webhook).
Choose **Option 1 (Locally)** if you are already SSH'd into your server. Choose **Option 2 (Remotely)** if you are running this from your home computer.

---

## 🤐 3. Managing Secrets

The script does not store secrets. It expects you to create `.env` files directly on the server. After running `setup.sh`, SSH into your server and create them:

```bash
# Edit frontend secrets
nano ~/myproject/secrets/frontend/.env

# Edit backend secrets
nano ~/myproject/secrets/backend/.env
```
*(Replace `myproject` with the name you provided during setup).* These files will be automatically copied into every new deployment.

---

## ⚙️ 4. First-Time Server Configuration

**Nginx Configuration:**
Point your Nginx server block's `root` directive to the symlinked `production` directory.
Assuming your project is named `myproject` and frontend is `frontend`:
```nginx
server {
    listen 80;
    server_name yourdomain.com;
    
    # Point to the production symlink!
    root /home/deployer/myproject/production/frontend/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**PM2 Backend Configuration:**
You must start the PM2 process manually the very first time so it exists when the deploy script tries to restart it:
```bash
cd ~/myproject/production/backend
pm2 start "uvicorn main:app --host 0.0.0.0 --port 8000" --name "myproject-backend"
pm2 save
```

---

## 🚢 5. How to Deploy

On your local development machine, inside your project folder:

**1. Add the Git Remote:**
*(The `setup.sh` script will output the exact command for you)*
```bash
git remote add production ssh://deployer@192.168.1.100:22/home/deployer/myproject/repo.git
```

**2. Push to Deploy:**
```bash
git push production main
```
That's it! Watch the terminal output as the server clones, builds, and swaps the symlinks.

---

## ⏪ 6. Rollbacks

If a bad deployment makes it through the build process but crashes at runtime, you can instantly rollback.

SSH into your VPS and run:
```bash
cd ~/myproject
./rollback.sh
```
It will display the last 5 successful releases and let you choose which one to instantly switch back to.
