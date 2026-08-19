# 🐳 Containerization DevEnv Odoo

[![Docker](https://img.shields.io/badge/Docker-2496ED? style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Odoo](https://img.shields.io/badge/Odoo-15-714B67?style=for-the-badge&logo=odoo&logoColor=white)](https://www.odoo.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)

Fully containerized **Odoo 15** development environment with Docker and Docker Compose. This solution enables quick and portable deployment of an Odoo ERP environment with its PostgreSQL database.

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Project Structure](#-project-structure)
- [Installation](#-installation)
- [Configuration](#️-configuration)
- [Usage](#-usage)
- [Volumes](#-volumes)
- [Networks](#-networks)
- [Custom Addons](#-custom-addons)
- [Troubleshooting](#-troubleshooting)

## ✨ Features

- 🚀 **Quick Deployment**: Complete environment with a single command
- 🐳 **100% Dockerized**: Full isolation and maximum portability
- 💾 **Data Persistence**: Docker volumes for Odoo and PostgreSQL
- 🔧 **Flexible Configuration**: Externalized environment variables
- 📦 **Addon Support**: Dedicated folder for custom modules
- 🔄 **Auto-restart**: Automatic container restart
- 🌐 **Isolated Network**:  Secure communication between services

## 📦 Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (version 20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (version 1.29+)
- Minimum 4 GB RAM
- 10 GB available disk space

## 📂 Project Structure

```
containerization-devenv-odoo/
├── docker-compose.yml       # Docker services configuration
├── . env                     # Environment variables (to create)
├── config/                  # Odoo configuration files
├── costum_addons/          # Custom Odoo addons
├── data/                   # Odoo data (Docker volume)
└── db/                     # PostgreSQL data (Docker volume)
```

## 🚀 Installation

### 1. Clone the repository

```bash
git clone https://github.com/AnselmeG300/containerization-devenv-odoo. git
cd containerization-devenv-odoo
```

### 2. Create the `.env` file

Create a `.env` file at the project root with the following variables:

```env
# PostgreSQL Configuration
POSTGRES_DB=postgres
POSTGRES_USER=odoo
POSTGRES_PASSWORD=odoo_password

# Odoo Configuration
HOST=postgres
USER=odoo
PASSWORD=odoo_password
```

> ⚠️ **Important**:  Change passwords for production use!

### 3. Create necessary directories

```bash
mkdir -p config costum_addons
```

### 4. Start the services

```bash
docker-compose up -d
```

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `POSTGRES_DB` | Database name | `postgres` |
| `POSTGRES_USER` | PostgreSQL user | `odoo` |
| `POSTGRES_PASSWORD` | PostgreSQL password | To define |
| `HOST` | Database host | `postgres` |
| `USER` | Odoo user | `odoo` |
| `PASSWORD` | Odoo password | To define |

### Odoo Configuration File (optional)

You can place an `odoo.conf` file in the `config/` folder: 

```ini
[options]
admin_passwd = master_password
db_host = postgres
db_port = 5432
db_user = odoo
db_password = odoo_password
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
```

## 🎯 Usage

### Start the environment

```bash
docker-compose up -d
```

### Access Odoo

Open your browser at:  **http://localhost:8069**

- **Email**: admin
- **Password**: admin (on first login)

### Check logs

```bash
# Logs for all services
docker-compose logs -f

# Odoo logs only
docker-compose logs -f odoo

# PostgreSQL logs only
docker-compose logs -f postgres
```

### Stop the environment

```bash
docker-compose down
```

### Stop and remove volumes

```bash
docker-compose down -v
```

## 💾 Volumes

| Volume | Container | Path | Description |
|--------|-----------|------|-------------|
| `data` | odoo | `/var/lib/odoo` | Odoo data (sessions, files) |
| `db` | postgres | `/var/lib/postgresql/data` | PostgreSQL data |
| `./config` | odoo | `/etc/odoo` | Odoo configuration |
| `./costum_addons` | odoo | `/mnt/extra-addons` | Custom modules |

## 🌐 Networks

The project uses a dedicated Docker network named `eazycnet` which provides: 

- Service isolation
- Communication between Odoo and PostgreSQL
- Automatic DNS resolution (odoo ↔ postgres)

## 📦 Custom Addons

To add custom modules: 

1. Place your addons in the `costum_addons/` folder
2.  Restart the Odoo container:

```bash
docker-compose restart odoo
```

3. Enable developer mode in Odoo
4. Update the application list
5. Install your modules

## 🐛 Troubleshooting

### Odoo container won't start

```bash
# Check logs
docker-compose logs odoo

# Check if PostgreSQL is ready
docker-compose logs postgres
```

### Database connection issue

Verify that environment variables match in the `.env` file:
- `POSTGRES_USER` = `USER`
- `POSTGRES_PASSWORD` = `PASSWORD`

### Port already in use

If port 8069 or 5432 is already in use:

```yaml
# Modify in docker-compose.yml
ports:
  - "8070:8069"  # For Odoo
  - "5433:5432"  # For PostgreSQL
```

### Completely reset the environment

```bash
docker-compose down -v
docker-compose up -d
```

## 📝 Useful Commands

```bash
# Access Odoo container shell
docker exec -it eazy-odoo-15 bash

# Access PostgreSQL shell
docker exec -it eazy-db-15 psql -U odoo -d postgres

# Backup database
docker exec eazy-db-15 pg_dump -U odoo postgres > backup.sql

# Restore database
docker exec -i eazy-db-15 psql -U odoo postgres < backup.sql
```

## 🤝 Contributing

Contributions are welcome! Feel free to: 

1. Fork the project
2. Create a branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -m 'Add improvement'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

## 📄 License

This project is free to use for educational and commercial purposes. 

## 👤 Author

**AnselmeG300**

- GitHub:  [@AnselmeG300](https://github.com/AnselmeG300)

---

⭐ If this project was helpful to you, don't hesitate to give it a star! 
