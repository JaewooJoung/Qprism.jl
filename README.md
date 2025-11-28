# Qprism.jl

# QPrism

**Volvo Supplier Quality Notification System**

QPrism is a Julia-based tool for monitoring Volvo supplier quality metrics, generating dashboards, and sending email notifications.

## Features

- 📡 **Web Scraping**: Automatically scrapes supplier scorecards from VSIB
- 📊 **Dashboard Generation**: Creates beautiful HTML dashboards with supplier metrics
- 📧 **Email Notifications**: Sends alerts for QPM increases, SW Index expirations, certification expiries
- 🔄 **Automated Workflows**: Simple menu-driven interface

## Installation

### Prerequisites

- Julia 1.6 or higher
- ChromeDriver (for web scraping)
- SMTP credentials (for email notifications)

### Install ChromeDriver

**Windows:**
1. Download from https://chromedriver.chromium.org/downloads
2. Add to PATH or place in project directory

**macOS:**
```bash
brew install chromedriver
```

**Linux:**
```bash
sudo apt install chromium-chromedriver
```

### Install Julia Dependencies

```bash
cd QPrism
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Configuration

### 1. Edit `conf/suppliers.toml`

Add your PARMA codes and email:

```toml
[[suppliers]]
parma_codes = [32731, 33568, 12345]

[myemail]
myemail = "your.name@consultant.volvo.com"
```

### 2. Edit `conf/config.toml` (for email)

Configure SMTP settings:

```toml
[smtp]
server = "smtp.gmail.com"
port = 587
username = "your.email@gmail.com"
password = "your-app-password"
```

> **Note**: For Gmail, use an [App Password](https://myaccount.google.com/apppasswords), not your regular password.

## Usage

### Interactive Mode

```bash
julia qprism.jl
```

This shows a menu with options:
1. **Generate Dashboard** - Scrape suppliers and create HTML dashboard
2. **Send Email Notifications** - Analyze data and send alerts
3. **Quit**

### Standalone Scripts

```bash
# Dashboard only
julia dashboard.jl

# Email notifications only
julia emailme.jl
```

### As a Module

```julia
using QPrism
qprismrun()
```

## Project Structure

```
QPrism/
├── qprism.jl           # Main entry point
├── dashboard.jl        # Dashboard-only script
├── emailme.jl          # Email-only script
├── Project.toml        # Julia package manifest
├── src/
│   └── QPrism.jl       # Main module
├── conf/
│   ├── suppliers.toml  # PARMA codes & email config
│   └── config.toml     # SMTP configuration
├── temp/
│   ├── index.html      # Dashboard template
│   └── supplier.html   # Supplier page template
├── data/               # Scraped HTML files (auto-created)
└── dashboard/          # Generated dashboard (auto-created)
    ├── index.html
    ├── supplier_*.html
    └── suppliers/
        └── *.json
```

## Notification Types

| Alert | Trigger | Priority |
|-------|---------|----------|
| QPM 10% Increase | QPM increases >10% from last period | 🔵 Low |
| QPM Warning | QPM between 30-50 | 🟡 Medium |
| QPM Critical | QPM over 50 | 🔴 High |
| SW Index Expired | SW Index >5 years old | 🔴 High |
| Certification Expiring | Cert expires within 6 months | 🟡 Medium |
| Certification Expired | Cert already expired | 🔴 High |

## License

JSD: Just Simple Distribution (Jaewoo's Simple Distribution)

## Author

Jaewoo Joung / 정재우 / 郑在祐

---

*"Quality is not an act, it is a habit."* - Aristotle
