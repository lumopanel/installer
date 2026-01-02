# Lumo Server Management Panel - Installer

Automated installation script for the Lumo Server Management Panel and Daemon on Ubuntu 22.04/24.04 systems.

## Requirements

- Ubuntu 22.04 or 24.04 LTS
- Root access (sudo)
- A domain name pointing to your server
- Ports 80 and 443 open for HTTP/HTTPS
- curl or wget (for the bootstrap installer)

## Quick Start

Run this single command to download and start the installer:

```bash
curl -sSL https://raw.githubusercontent.com/lumopanel/installer/main/bootstrap.sh | sudo bash
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/lumopanel/installer/main/bootstrap.sh | sudo bash
```

### Alternative: Clone Repository

If you prefer to clone the repository (requires git):

```bash
git clone https://github.com/lumopanel/installer.git
cd installer
sudo bash install.sh
```

## What Gets Installed

- **Lumo Daemon** - Privileged system daemon for server management
- **Lumo Panel** - Laravel-based web interface
- **PHP 8.3** with required extensions
- **Nginx** web server
- **Redis** for caching and queues
- **Database** (MySQL, PostgreSQL, or SQLite)
- **Let's Encrypt SSL** certificate (optional)
- **Laravel Horizon** for queue management

## Project Structure

```
installer/
├── bootstrap.sh                  # One-liner installer (no git required)
├── install.sh                    # Main entry point
├── config/
│   ├── defaults.conf             # Configuration defaults
│   └── templates/                # Configuration templates
│       ├── nginx-site.conf
│       ├── php-fpm-pool.conf
│       ├── daemon.toml
│       ├── lumo-daemon.service
│       └── lumo-horizon.service
└── lib/
    ├── common.sh                 # Logging and helpers
    ├── validation.sh             # Pre-flight checks
    ├── user.sh                   # User management
    ├── templates.sh              # Template rendering
    ├── daemon.sh                 # Daemon client functions
    ├── daemon-setup.sh           # Daemon installation
    ├── packages.sh               # Package installation
    ├── nginx.sh                  # Nginx configuration
    ├── ssl.sh                    # SSL/TLS setup
    ├── panel.sh                  # Panel installation
    └── services.sh               # Systemd services
```

## Configuration

The installer will prompt for:

- **Domain name** - Your panel's FQDN (e.g., `panel.example.com`)
- **SSL email** - Email for Let's Encrypt certificate notifications
- **Database type** - MySQL (recommended), PostgreSQL, or SQLite

### Environment Variables

You can pre-configure the installer with environment variables:

```bash
export LUMO_USER=lumo           # System user (default: lumo)
export INSTALL_DIR=/home/lumo/panel  # Installation directory
export PHP_VERSION=8.3          # PHP version
export LUMO_VERSION=main        # Panel version/branch
export DAEMON_VERSION=main      # Daemon version/branch
```

## Installation Phases

1. **Bootstrap** - Install essential packages (curl, git, etc.)
2. **Daemon** - Download/build and configure the Lumo daemon
3. **Core Services** - Install Redis, Nginx, PHP, Node.js, database
4. **Panel** - Clone repository, install dependencies, configure Laravel
5. **Web Server** - Configure Nginx, SSL, Horizon, and scheduler

## Post-Installation

After installation completes:

1. Visit `https://your-domain.com` to access the panel
2. Create your admin account
3. Configure your servers

### Useful Commands

```bash
# Check service status
systemctl status lumo-daemon
systemctl status lumo-horizon

# View logs
tail -f /home/lumo/panel/storage/logs/laravel.log
journalctl -u lumo-daemon -f

# Laravel REPL
sudo -u lumo php /home/lumo/panel/artisan tinker

# Clear caches
sudo -u lumo php /home/lumo/panel/artisan optimize:clear
```

## Security

- The panel runs under a dedicated `lumo` user with restricted permissions
- Daemon authenticates requests via HMAC-SHA256 signatures
- PHP-FPM runs in a dedicated pool with `open_basedir` restrictions
- Credentials are saved to `INSTALL_CREDENTIALS.txt` (delete after noting)

## Troubleshooting

### SSL Certificate Failed

If Let's Encrypt fails, ensure:
- Your domain's DNS is correctly pointing to the server
- Ports 80 and 443 are open
- Retry manually: `certbot --nginx -d your-domain.com`

### Daemon Not Starting

Check logs: `journalctl -u lumo-daemon -e`

Common issues:
- Socket directory permissions
- HMAC secret file missing or incorrect permissions

### Panel 502 Error

Check PHP-FPM is running:
```bash
systemctl status php8.3-fpm
```

Check the pool socket exists:
```bash
ls -la /run/php/php8.3-fpm-lumo.sock
```

## License

MIT License - See [LICENSE](LICENSE) for details.
