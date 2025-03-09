# Anonymity Setup Script for Kali Linux

![License](https://img.shields.io/badge/license-MIT-green)  
![Kali Linux](https://img.shields.io/badge/OS-Kali%20Linux-blue)  
![Tor](https://img.shields.io/badge/Tool-Tor-orange)  
![macchanger](https://img.shields.io/badge/Tool-macchanger-yellow)  

## Overview

This Bash script, `anonymity_setup.sh`, automates the configuration of free, open-source tools in **Kali Linux** to maximize your online anonymity at **zero cost**. By leveraging **Tor** and **macchanger**, it hides your IP address, DNS queries, and MAC address—key identifiers that could otherwise compromise your privacy. The script also includes robust error handling and a fail-safe mechanism to revert changes if needed.

### Key Features
- **IP Address Anonymity**: Routes all traffic through the Tor network to mask your real IP.
- **DNS Query Anonymity**: Ensures DNS requests go through Tor, preventing leaks.
- **MAC Address Spoofing**: Randomizes your MAC address to avoid local network tracking.
- **Zero Cost**: Relies entirely on free tools with a zero-logs policy.
- **Fail-Safe Mechanism**: Restores original settings if the script fails or is interrupted.
- **Error Handling**: Logs every step and validates the setup for reliability.

---

## Prerequisites

Before running the script, ensure you have:
- **Operating System**: Kali Linux (latest version recommended).
- **Permissions**: Root access (run with `sudo`).
- **Internet Connection**: Needed to install tools and verify anonymity.

---

## Installation and Usage

Follow these steps to set up and use the script:

### Step 1: Clone the Repository;
### Step 2: Make the Script Executable;
### Step 3: Run the Script

Download the script by cloning this repository:

```bash
git clone https://github.com/coco975/anonymity_setup.git

cd anonymity_setup

chmod +x anonymity_setup.sh

sudo ./anonymity_setup.sh
```
# The script will:

Back up your current network and iptables configurations.
Install required tools (tor and macchanger).
Spoof your MAC address.
Configure Tor as a transparent proxy.
Set up iptables rules to route all traffic through Tor.
Verify that the setup is complete.





