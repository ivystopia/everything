# WireGuard VPN Setup

#### You

I'd like to set up a VPN on my Raspberry Pi, which is currently connected to my router and accessible within my LAN on an IP of 192.168.1.102

The goal is to be able to VPN into my home network on Android and:

1. Be able to access and browse the SMB shares from my home PC, while not connected to my home wifi
2. Tunnel all my traffic so it appears as if all traffic is originating from my home Internet connection

I'm looking into Wireguard. Is this the best approach? How do I set up the Pi, and how do I set up the Android phone? The Pi is running Debian 12

#### ChatGPT

WireGuard is a solid choice—fast, secure, and relatively simple to configure. Below is a high-level setup outline, assuming:

- You have a public IP or a dynamic DNS name pointing to your home network.
- Router is configured to forward UDP port 51820 to your Raspberry Pi (192.168.1.102).
- WireGuard is installed on the Pi (Debian 12) and the WireGuard app is on your Android phone.

**1. Generate keys on the Raspberry Pi**\
Generate a new key pair in any directory (e.g., `/etc/wireguard/`):

```
wg genkey | tee privatekey | wg pubkey > publickey
```

- `privatekey` will contain the server’s private key.
- `publickey` will contain the server’s public key.

**2. Create the WireGuard interface configuration on the Pi**\
Create or edit `/etc/wireguard/wg0.conf` (example below). Adjust IP addresses and port numbers to suit:

```
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = SERVER_PRIVATE_KEY
# Enable packet forwarding + NAT
PostUp   = iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT; iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o eth0 -j ACCEPT; iptables -D FORWARD -i eth0 -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# Example for your phone (fill in phone's public key later)
PublicKey = PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

Replace `SERVER_PRIVATE_KEY` with the content of your `privatekey` file (no quotes or newlines).

**3. Enable IP forwarding**\
Make sure IP forwarding is on (in `/etc/sysctl.conf` or a drop-in conf):

```
net.ipv4.ip_forward=1
```

Then apply with `sysctl -p`.

**4. Bring up the interface**

```
sudo wg-quick up wg0
```

(Use `wg-quick down wg0` to stop it.)

**5. Configure the Android phone**\
In the WireGuard app:

- Create a new tunnel and generate keys locally, or use an existing key pair.
- Set the interface’s private key to the phone’s private key.
- Add the Raspberry Pi as a peer:

```
[Interface]
Address = 10.8.0.2/32
PrivateKey = PHONE_PRIVATE_KEY
DNS = 1.1.1.1  # or your preferred DNS

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = YOUR_HOME_IP_OR_DDNS:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

- `AllowedIPs = 0.0.0.0/0` routes all traffic over the tunnel (so your Internet traffic appears to originate from home).
- `PersistentKeepalive = 25` helps keep NAT mappings open.

**6. Update the server’s `[Peer]` entry**\
Back on the Pi in `wg0.conf`, fill in the phone’s `PublicKey`:

```
[Peer]
PublicKey = PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

Then reload on the Pi:

```
sudo wg-quick down wg0 && sudo wg-quick up wg0
```

---

Once connected, your phone will be assigned `10.8.0.2`, and all traffic (including SMB browsing) will tunnel through your home IP. From outside your LAN, you can access your home PC’s SMB shares via the home PC’s 192.168.1.x address.

#### You

I want to be able to connect from anywhere. Give me commands to run on my Pi and I will show you the output.

So far, I ran this:

```zsh
ivy@pi4 ~ ❯ wg
zsh: command not found: wg
ivy@pi4 ~ ❯ sudo apt install wireguard wireguard-tools
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Suggested packages:
  openresolv | resolvconf
The following NEW packages will be installed:
  wireguard wireguard-tools
0 upgraded, 2 newly installed, 0 to remove and 0 not upgraded.
Need to get 97.5 kB of archives.
After this operation, 383 kB of additional disk space will be used.
Get:1 http://deb.debian.org/debian bookworm/main arm64 wireguard-tools arm64 1.0.20210914-1+b1 [89.3 kB]
Get:2 http://deb.debian.org/debian bookworm/main arm64 wireguard all 1.0.20210914-1 [8,216 B]
Fetched 97.5 kB in 1s (161 kB/s)
Selecting previously unselected package wireguard-tools.
(Reading database ... 82201 files and directories currently installed.)
Preparing to unpack .../wireguard-tools_1.0.20210914-1+b1_arm64.deb ...
Unpacking wireguard-tools (1.0.20210914-1+b1) ...
Selecting previously unselected package wireguard.
Preparing to unpack .../wireguard_1.0.20210914-1_all.deb ...
Unpacking wireguard (1.0.20210914-1) ...
Setting up wireguard-tools (1.0.20210914-1+b1) ...
wg-quick.target is a disabled or a static unit, not starting it.
Setting up wireguard (1.0.20210914-1) ...
Processing triggers for man-db (2.11.2-2) ...
ivy@pi4 ~ 7s ❯ wg genkey | tee privatekey | wg pubkey > publickey
ivy@pi4 ~ ❯ ls
privatekey  publickey
```

#### ChatGPT

First, let’s create a minimal server configuration on the Pi, enable IP forwarding, then bring up the WireGuard interface. After that, we’ll handle your phone side. Here are the step-by-step commands to run.

---

## 1. Copy your private key for reference

```
cat privatekey
```

You’ll need that text (a long base64 string). Copy it somewhere safe for a moment.

---

## 2. Create the WireGuard config file

Open `/etc/wireguard/wg0.conf` in a text editor:

```
sudo nano /etc/wireguard/wg0.conf
```

Paste the following (adjusting if needed):

```
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = REPLACE_WITH_CONTENTS_OF_privatekey
# NAT and forwarding rules on startup
PostUp   = iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT; iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o eth0 -j ACCEPT; iptables -D FORWARD -i eth0 -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Important**:

- Replace `REPLACE_WITH_CONTENTS_OF_privatekey` with the actual key you got from `cat privatekey` (no quotes, no extra lines).
- If `eth0` is not your Pi’s network interface, adjust accordingly (e.g., `enp0s3` or something else). You can confirm by running `ip addr`.

Save and exit (`Ctrl+O`, then `Enter`, then `Ctrl+X`).

---

## 3. Enable IP forwarding

Check if IP forwarding is already enabled:

```
sysctl net.ipv4.ip_forward
```

If it returns `net.ipv4.ip_forward = 0`, then do:

```
sudo sysctl -w net.ipv4.ip_forward=1
```

Also make it permanent by editing `/etc/sysctl.conf` or creating a small override file:

```
sudo nano /etc/sysctl.conf
```

Uncomment (or add):

```
net.ipv4.ip_forward=1
```

Save and exit.

---

## 4. Start the WireGuard interface

```
sudo wg-quick up wg0
```

Check its status:

```
sudo wg show
```

You should see something like:

```
interface: wg0
  public key: ...
  private key: (hidden)
  listening port: 51820
```

If you see that, the server side is running.

---

## 5. Confirm port forwarding on your router

Now (or soon), you’ll want to forward UDP port 51820 from your router to the Pi’s LAN IP (`192.168.1.102`) so you can connect from outside. This step is specific to your router’s admin interface. Without it, the phone won’t connect from outside.

---

**Next step**: We’ll define a `[Peer]` section for your phone, but first let’s get the phone’s public key. Once you install the WireGuard app on Android and generate a tunnel there, you’ll have a public key to copy back into `wg0.conf`. Let me know once you’re at that point, or feel free to share the output of the commands above and we’ll proceed from there.

#### You

What do you mean by "adjusting if needed"? What information can I give you, in order for you to give me precise and full instructions?

#### ChatGPT

Certainly! When I mentioned "adjusting if needed," I was referring to tailoring the configuration to match your specific network setup. This ensures that WireGuard interacts correctly with your Raspberry Pi’s network interfaces and settings. To provide precise and complete instructions, I need some additional information from your Raspberry Pi. Here’s what you can do:

### **1. Identify Your Network Interface**

Different systems may use different names for network interfaces (e.g., `eth0`, `enp0s3`, `wlan0`). Knowing the correct interface name is crucial for setting up NAT (Network Address Translation) rules.

**Run the following command on your Pi:**

```bash
ip addr
```

**Example Output:**

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    inet 192.168.1.102/24 brd 192.168.1.255 scope global eth0
       valid_lft forever preferred_lft forever
```

**From this output:**

- `eth0` is your primary network interface connected to your router.
- If your interface is named differently (e.g., `enp0s3`), note that name for later use.

### **2. Confirm Your Raspberry Pi’s Internal IP Address**

Ensure that your Pi’s LAN IP is indeed `192.168.1.102`. If it's different, you'll need to adjust the configurations accordingly.

**Run:**

```bash
ip addr show eth0 | grep inet
```

**Expected Output:**

```
inet 192.168.1.102/24 brd 192.168.1.255 scope global eth0
```

_If your interface name is different, replace `eth0` with your actual interface name in the command._

### **3. Determine Your Public IP or Set Up Dynamic DNS**

To access your VPN from anywhere, you'll need to know your home network’s public IP address or set up a Dynamic DNS (DDNS) service if your ISP provides a dynamic IP.

**To find your current public IP:**

From your Pi, run:

```bash
curl ifconfig.me
```

**Example Output:**

```
203.0.113.45
```

_Note: Replace `203.0.113.45` with your actual public IP._

**Alternatively, set up a DDNS service** like [DuckDNS](https://www.duckdns.org/) or [No-IP](https://www.noip.com/) and obtain a domain name that maps to your dynamic IP. This is recommended if your ISP doesn’t provide a static IP.

### **4. Provide the Following Information**

To tailor the instructions precisely, please provide:

1. **Network Interface Name:** Output of `ip addr` showing your primary network interface (e.g., `eth0`, `enp0s3`).
2. **Internal IP Address:** Confirm that your Pi’s LAN IP is `192.168.1.102`. If different, provide the correct IP.
3. **Public IP or DDNS:** Confirm whether you have a static public IP, dynamic public IP, or have set up a DDNS. If using DDNS, provide the domain name.
4. **Router Model (Optional):** If you need assistance with port forwarding, knowing your router model can help provide specific instructions.

### **Example Based on Assumptions**

Assuming:

- **Network Interface:** `eth0`
- **Pi’s Internal IP:** `192.168.1.102`
- **Public IP:** `203.0.113.45` (replace with your actual IP)
- **Router:** Generic (instructions may vary slightly based on model)

Here’s how to proceed with these assumptions:

---

### **Step-by-Step WireGuard Configuration**

#### **1. Create the WireGuard Configuration File**

**Open the WireGuard configuration file:**

```bash
sudo nano /etc/wireguard/wg0.conf
```

**Paste the following configuration:**

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = YOUR_SERVER_PRIVATE_KEY
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Replace `YOUR_SERVER_PRIVATE_KEY` with the content of your `privatekey` file:**

```bash
cat privatekey
```

**Example:**

```
ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

**Final `wg0.conf` Example:**

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Save and exit:**

- Press `Ctrl + O`, then `Enter` to save.
- Press `Ctrl + X` to exit.

#### **2. Enable IP Forwarding**

**Temporarily enable IP forwarding:**

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

**Permanently enable IP forwarding:**

```bash
sudo nano /etc/sysctl.conf
```

**Uncomment or add the following line:**

```
net.ipv4.ip_forward=1
```

**Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).**

**Apply the changes:**

```bash
sudo sysctl -p
```

#### **3. Start the WireGuard Interface**

**Bring up the WireGuard interface:**

```bash
sudo wg-quick up wg0
```

**Enable WireGuard to start on boot:**

```bash
sudo systemctl enable wg-quick@wg0
```

**Check WireGuard status:**

```bash
sudo wg
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820

```

#### **4. Configure Port Forwarding on Your Router**

To allow external connections to your WireGuard server, forward UDP port `51820` to your Pi’s internal IP (`192.168.1.102`).

**General Steps:**

1. **Access Your Router’s Admin Interface:** Typically via `http://192.168.1.1` or similar.
2. **Navigate to Port Forwarding Section:** Often under "Advanced" or "NAT/QoS."
3. **Create a New Port Forwarding Rule:**
   - **Service Name:** WireGuard or any descriptive name.
   - **Protocol:** UDP
   - **External Port:** 51820
   - **Internal IP Address:** 192.168.1.102
   - **Internal Port:** 51820
4. **Save/Apply the Settings.**

_Note: Router interfaces vary. Refer to your router’s manual for specific instructions._

#### **5. Set Up WireGuard on Your Android Phone**

Now, configure your Android device to connect to the WireGuard server.

**On Your Raspberry Pi:**

**Generate a key pair for your phone:**

```bash
wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
```

**Retrieve the keys:**

```bash
cat phone_privatekey
cat phone_publickey
```

**Update the WireGuard server configuration with your phone as a peer:**

```bash
sudo nano /etc/wireguard/wg0.conf
```

**Add the following at the end:**

```ini
[Peer]
# Android Phone
PublicKey = YOUR_PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

**Replace `YOUR_PHONE_PUBLIC_KEY` with the content of `phone_publickey`.**

**Save and exit.**

**Reload WireGuard Configuration:**

```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

**On Your Android Phone:**

1. **Install the WireGuard App:**

   - Available on the [Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android).

2. **Create a New Tunnel:**

   - Open the WireGuard app.
   - Tap the "+" button and select "Create from scratch."

3. **Configure the Interface:**

   - **Name:** Home VPN (or any name you prefer).
   - **Private Key:** Paste the content of `phone_privatekey`.

4. **Set the Address:**

   - **IP Address:** `10.8.0.2/32`

5. **Set DNS (Optional but recommended):**

   - **DNS Server:** `1.1.1.1` or `8.8.8.8`

6. **Add a Peer:**
   - **Public Key:** Paste `YOUR_SERVER_PUBLIC_KEY` (from `cat publickey` on Pi).
   - **Endpoint:** `YOUR_PUBLIC_IP:51820` or `YOUR_DDNS_DOMAIN:51820`
   - **Allowed IPs:** `0.0.0.0/0` (routes all traffic through VPN)
   - **Persistent Keepalive:** `25` (helps maintain NAT mappings)

**Example Peer Configuration:**

```
[Peer]
PublicKey = YOUR_SERVER_PUBLIC_KEY
Endpoint = 203.0.113.45:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

**Save the Tunnel.**

7. **Activate the Tunnel:**
   - Toggle the switch next to your newly created tunnel to connect.

#### **6. Verify the Connection**

**On Your Android Phone:**

- Once connected, your phone’s public IP should match your home’s public IP.
- You can verify by visiting [whatismyip.com](https://www.whatismyip.com/) in your phone’s browser.

**On Your Raspberry Pi:**

- Check the WireGuard status to see the connected peer:

```bash
sudo wg
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820

peer: YOUR_PHONE_PUBLIC_KEY
  endpoint: YOUR_PHONE_PUBLIC_IP:PORT
  allowed ips: 10.8.0.2/32
  latest handshake: [timestamp]
  transfer: [data sent/received]
```

#### **7. Accessing SMB Shares**

With the VPN connected:

- **From your Android phone:**

  - Use a file explorer app that supports SMB (e.g., [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2)).

- **Connect to the SMB Share:**
  - **Server Address:** `192.168.1.x` (your home PC’s LAN IP)
  - **Username and Password:** Your home PC’s SMB credentials.

_Ensure that your home PC’s firewall allows SMB traffic from the VPN subnet (`10.8.0.0/24`)._

### **Summary**

By providing the following information, I can ensure that the instructions are perfectly tailored to your setup:

1. **Output of `ip addr`** (to confirm network interface and IP).
2. **Confirmation of Pi’s internal IP** (`192.168.1.102` or different).
3. **Public IP or DDNS details**.
4. **Router model** (if you need specific port forwarding instructions).

Feel free to share any of the above details, and I can provide more precise commands and configurations as needed!

#### You

```
ivy@pi4 ~ ❯ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether d8:3a:dd:d3:25:d6 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.102/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
    inet6 2a01:4b00:d014:ff00::102/64 scope global noprefixroute
       valid_lft forever preferred_lft forever
    inet6 fe80::bc75:7efd:797e:cc79/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
3: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc pfifo_fast state DOWN group default qlen 1000
    link/ether d8:3a:dd:d3:25:d7 brd ff:ff:ff:ff:ff:ff
```

```
ivy@pi4 ~ ❯ ip addr show eth0 | grep inet
    inet 192.168.1.102/24 brd 192.168.1.255 scope global noprefixroute eth0
    inet6 2a01:4b00:d014:ff00::102/64 scope global noprefixroute
    inet6 fe80::bc75:7efd:797e:cc79/64 scope link noprefixroute
```

```
ivy@pi4 ~ ❯ curl ifconfig.me
REDACTED%
```

REDACTED is a static IP.

#### ChatGPT

Great! With the information you've provided, we can proceed to set up WireGuard on your Raspberry Pi and configure your Android phone to connect to your home network securely. Below are the precise, step-by-step commands and instructions to achieve your goals.

---

## **1. Create the WireGuard Server Configuration on the Raspberry Pi**

### **a. Retrieve Your Server's Private Key**

First, let's view your server's private key, which you generated earlier:

```bash
cat privatekey
```

**Example Output:**

```
ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

**Note:** Keep this key secure. Do **not** share it publicly.

### **b. Retrieve Your Server's Public Key**

Next, view your server's public key:

```bash
cat publickey
```

**Example Output:**

```
1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

### **c. Create and Edit the WireGuard Configuration File**

Open the WireGuard configuration file using `nano`:

```bash
sudo nano /etc/wireguard/wg0.conf
```

Paste the following configuration into the file:

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = YOUR_SERVER_PRIVATE_KEY
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Replace `YOUR_SERVER_PRIVATE_KEY`** with the actual private key you obtained earlier. It should look something like this:

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Important:** Ensure that:

- The `Address` field (`10.8.0.1/24`) defines the VPN subnet.
- The `ListenPort` is set to `51820` (default for WireGuard).
- The `PostUp` and `PostDown` rules handle NAT and forwarding.

### **d. Save and Exit**

- Press `Ctrl + O`, then `Enter` to save the file.
- Press `Ctrl + X` to exit the editor.

### **e. Secure the Configuration File**

Set appropriate permissions to protect your private key:

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

---

## **2. Enable IP Forwarding (If Not Already Enabled)**

You've already checked and enabled IP forwarding, but let's ensure it's correctly set.

### **a. Verify IP Forwarding**

```bash
sysctl net.ipv4.ip_forward
```

**Expected Output:**

```
net.ipv4.ip_forward = 1
```

If it returns `0`, enable it temporarily:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### **b. Make IP Forwarding Permanent**

Ensure that IP forwarding persists across reboots:

```bash
sudo nano /etc/sysctl.conf
```

Uncomment or add the following line:

```
net.ipv4.ip_forward=1
```

**Save and Exit:**

- Press `Ctrl + O`, then `Enter` to save.
- Press `Ctrl + X` to exit.

Apply the changes immediately:

```bash
sudo sysctl -p
```

---

## **3. Start and Enable the WireGuard Service**

### **a. Bring Up the WireGuard Interface**

```bash
sudo wg-quick up wg0
```

### **b. Verify WireGuard is Running**

```bash
sudo wg show
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820
```

### **c. Enable WireGuard to Start on Boot**

```bash
sudo systemctl enable wg-quick@wg0
```

---

## **4. Configure Your Router for Port Forwarding**

Since you have a static public IP (`REDACTED`), you can set up port forwarding to allow external connections to your WireGuard server.

**Steps:**

1. **Access Your Router’s Admin Interface:**

   - Open a web browser and navigate to `http://192.168.1.1` or your router's specific admin address.
   - Log in with your credentials.

2. **Navigate to Port Forwarding Settings:**

   - This is often found under sections like "Advanced," "NAT," "Firewall," or "Virtual Servers."

3. **Create a New Port Forwarding Rule:**

   - **Service Name:** `WireGuard` (or any descriptive name).
   - **Protocol:** `UDP`
   - **External Port:** `51820`
   - **Internal IP Address:** `192.168.1.102` (your Pi’s IP)
   - **Internal Port:** `51820`
   - **Enable the Rule:** Ensure the rule is active.

4. **Save/Apply the Settings:**
   - Confirm and apply the new port forwarding rule.

**Note:** Router interfaces vary. If you need specific instructions, please provide your router model.

---

## **5. Generate a Key Pair for Your Android Phone**

To securely connect your phone to the VPN, generate a unique key pair for it.

### **a. Generate the Phone’s Private Key**

```bash
wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
```

### **b. View the Phone’s Private Key**

```bash
cat phone_privatekey
```

**Example Output:**

```
abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

**Note:** **Keep this key secure.** You will input it into your Android device.

### **c. View the Phone’s Public Key**

```bash
cat phone_publickey
```

**Example Output:**

```
1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

---

## **6. Add Your Android Phone as a Peer on the Server**

### **a. Edit the WireGuard Configuration File**

```bash
sudo nano /etc/wireguard/wg0.conf
```

### **b. Add the Following Peer Configuration at the End of the File**

```ini
[Peer]
# Android Phone
PublicKey = YOUR_PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

**Replace `YOUR_PHONE_PUBLIC_KEY`** with the actual public key you obtained earlier (`cat phone_publickey`).

**Example:**

```ini
[Peer]
# Android Phone
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
AllowedIPs = 10.8.0.2/32
```

### **c. Save and Exit**

- Press `Ctrl + O`, then `Enter` to save.
- Press `Ctrl + X` to exit.

### **d. Reload the WireGuard Configuration**

```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

### **e. Verify the Peer is Added**

```bash
sudo wg
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820

peer: YOUR_PHONE_PUBLIC_KEY
  endpoint: <not connected>
  allowed ips: 10.8.0.2/32
  latest handshake: <never>
  transfer: 0 B received, 0 B sent
```

---

## **7. Configure WireGuard on Your Android Phone**

### **a. Install the WireGuard App**

- **Download:** [WireGuard on Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)
- **Install:** Follow the on-screen instructions to install the app.

### **b. Create a New Tunnel**

1. **Open the WireGuard App.**
2. **Tap the "+" Button** at the bottom right.
3. **Select "Create from scratch."**

### **c. Configure the Interface**

- **Name:** `Home VPN` (or any name you prefer).

- **Private Key:** Paste the content of `phone_privatekey` (`cat phone_privatekey`).

  **To Copy the Private Key:**

  - On the Pi, run:

    ```bash
    cat phone_privatekey
    ```

  - **Copy** the output.
  - **Paste** it into the WireGuard app under "Private Key."

- **Address:** `10.8.0.2/32`

- **DNS:** `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google DNS)

**Example Configuration:**

```
[Interface]
PrivateKey = abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address = 10.8.0.2/32
DNS = 1.1.1.1
```

### **d. Add a Peer**

1. **Tap "Add Peer."**
2. **Configure the Peer:**

   - **Public Key:** Paste `YOUR_SERVER_PUBLIC_KEY` (`cat publickey`).

     **To Copy the Server’s Public Key:**

     - On the Pi, run:

       ```bash
       cat publickey
       ```

     - **Copy** the output.
     - **Paste** it into the WireGuard app under "Public Key."

   - **Endpoint:** `REDACTED:51820`

   - **Allowed IPs:** `0.0.0.0/0` (This routes all traffic through the VPN)

   - **Persistent Keepalive:** `25` (Optional but recommended to maintain the connection)

**Example Peer Configuration:**

```
[Peer]
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### **e. Save the Tunnel**

- **Tap the Save Icon** (usually a checkmark) to save the configuration.

### **f. Activate the Tunnel**

- **Toggle the Switch** next to your newly created tunnel (`Home VPN`) to connect.

---

## **8. Verify the VPN Connection**

### **a. On Your Android Phone**

1. **Check IP Address:**

   - Open a web browser and navigate to [whatismyip.com](https://www.whatismyip.com/).
   - Ensure that the displayed IP address matches your home’s public IP (`REDACTED`).

2. **Check Connectivity to SMB Shares:**
   - Use a file explorer app that supports SMB (e.g., [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2)).
   - Add a new SMB connection using your home PC’s LAN IP (e.g., `192.168.1.x`).

### **b. On Your Raspberry Pi**

1. **Check WireGuard Status:**

   ```bash
   sudo wg
   ```

   **Expected Output:**

   ```
   interface: wg0
     public key: YOUR_SERVER_PUBLIC_KEY
     private key: (hidden)
     listening port: 51820

   peer: YOUR_PHONE_PUBLIC_KEY
     endpoint: REDACTED:PORT
     allowed ips: 10.8.0.2/32
     latest handshake: [timestamp]
     transfer: [data sent/received]
   ```

2. **Monitor Logs for Any Issues:**

   ```bash
   sudo journalctl -u wg-quick@wg0
   ```

   Look for any error messages that might indicate issues with the connection.

---

## **9. Accessing SMB Shares from Your Android Phone**

With the VPN connected, you can access SMB shares on your home network.

### **a. Ensure SMB is Accessible**

1. **On Your Home PC:**

   - Ensure that SMB sharing is enabled.
   - Verify that the shared folders are accessible within the LAN (`192.168.1.x`).

2. **Firewall Settings:**
   - Ensure that your home PC’s firewall allows SMB traffic from the VPN subnet (`10.8.0.0/24`).
   - You might need to create firewall rules to allow incoming SMB connections from `10.8.0.0/24`.

### **b. Use a File Explorer App on Android**

1. **Download and Install Solid Explorer:**

   - [Solid Explorer on Google Play](https://play.google.com/store/apps/details?id=pl.solidexplorer2)

2. **Add a New SMB Connection:**

   - Open Solid Explorer.
   - Tap the **"+"** button.
   - Select **"New cloud connection"** > **"SMB/CIFS"**.

3. **Configure the SMB Connection:**

   - **Name:** Descriptive name (e.g., `Home PC Share`).
   - **Host:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP).
   - **Username:** Your SMB username.
   - **Password:** Your SMB password.
   - **Workgroup:** (Optional) Your network's workgroup name.

4. **Save and Connect:**
   - Save the configuration.
   - Tap on the newly created connection to access your SMB shares.

**Note:** If you encounter issues, ensure that your home PC allows SMB connections from the `10.8.0.0/24` subnet and that no firewall is blocking the traffic.

---

## **10. Additional Recommendations**

### **a. Secure Your WireGuard Configuration**

- **Protect Private Keys:**

  - Ensure that both `privatekey` and `phone_privatekey` files are secured.
  - Avoid sharing private keys publicly.

- **Regularly Update Your System:**

  - Keep your Raspberry Pi and WireGuard packages up to date to ensure security patches are applied.

    ```bash
    sudo apt update
    sudo apt upgrade -y
    ```

### **b. Backup Configuration Files**

- **Backup `/etc/wireguard/wg0.conf`:**

  - Consider backing up your configuration file in a secure location.

    ```bash
    sudo cp /etc/wireguard/wg0.conf ~/wg0.conf.backup
    ```

### **c. Manage Multiple Peers**

- If you wish to add more devices in the future, generate new key pairs for each device and add them as separate `[Peer]` sections in `wg0.conf` with unique `AllowedIPs`.

---

## **Summary**

You've successfully set up WireGuard on your Raspberry Pi with the following capabilities:

1. **Secure VPN Access:** Connect to your home network securely from anywhere.
2. **Access SMB Shares:** Browse and access SMB shares on your home PC via the VPN.
3. **Route All Traffic Through Home Internet:** All your phone's internet traffic appears to originate from your home IP (`REDACTED`).

**Key Points to Remember:**

- **Security:** Always keep your private keys secure. Never share them.
- **Firewall:** Ensure that necessary ports are open and firewall rules are correctly configured.
- **Testing:** Regularly test your VPN connection to ensure it's functioning as expected.

If you encounter any issues or need further assistance, feel free to ask!

#### You

```
ivy@pi4 ~ ❯ sysctl net.ipv4.ip_forward
zsh: command not found: sysctl
```

#### ChatGPT

It appears that the `sysctl` command is not available on your Raspberry Pi. The `sysctl` utility is essential for configuring kernel parameters, including enabling IP forwarding, which is crucial for your WireGuard VPN setup. Let's troubleshoot and resolve this issue step by step.

## **1. Verify the Absence of `sysctl`**

First, let's confirm that the `sysctl` command is indeed missing or not accessible in your current PATH.

### **a. Check if `sysctl` Exists**

Run the following command to see if `sysctl` is installed and locate its path:

```bash
which sysctl
```

**Possible Outcomes:**

- **If you receive a path like `/sbin/sysctl` or `/usr/sbin/sysctl`:**

  The `sysctl` binary exists but might not be in your current PATH. In this case, you can execute it using the full path or adjust your PATH variable.

- **If you receive no output or an error like `command not found`:**

  The `sysctl` command is not installed on your system.

### **b. Attempt to Locate `sysctl` Manually**

If `which sysctl` doesn't return a path, try locating it manually:

```bash
sudo find / -type f -name sysctl 2>/dev/null
```

**Interpretation:**

- If the command finds `sysctl`, note its location (e.g., `/sbin/sysctl`) and proceed to use it via its full path.
- If it doesn't find `sysctl`, proceed to install the necessary package.

## **2. Install the `procps` Package**

The `sysctl` command is part of the `procps` package in Debian-based systems. If it's missing, installing this package should resolve the issue.

### **a. Update Package Lists**

Ensure your package lists are up-to-date:

```bash
sudo apt update
```

### **b. Install `procps`**

Install the `procps` package, which includes `sysctl`:

```bash
sudo apt install procps
```

**Expected Output:**

You should see output indicating that `procps` is being installed along with its dependencies.

### **c. Verify Installation**

After installation, confirm that `sysctl` is now available:

```bash
which sysctl
```

**Expected Output:**

A path to `sysctl`, such as `/sbin/sysctl`.

**Example:**

```
/sbin/sysctl
```

## **3. Enable IP Forwarding**

With `sysctl` now available, you can proceed to enable IP forwarding, which is essential for routing traffic through your VPN.

### **a. Check Current IP Forwarding Status**

```bash
sudo sysctl net.ipv4.ip_forward
```

**Expected Output:**

```
net.ipv4.ip_forward = 1
```

- **If it returns `1`:** IP forwarding is already enabled.
- **If it returns `0`:** IP forwarding is disabled and needs to be enabled.

### **b. Enable IP Forwarding Temporarily**

To enable IP forwarding immediately (effective until the next reboot):

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### **c. Enable IP Forwarding Permanently**

To ensure IP forwarding remains enabled after reboot, modify the `/etc/sysctl.conf` file.

1. **Open the Configuration File:**

   ```bash
   sudo nano /etc/sysctl.conf
   ```

2. **Uncomment or Add the Following Line:**

   Locate the line:

   ```
   #net.ipv4.ip_forward=1
   ```

   Remove the `#` to uncomment it:

   ```
   net.ipv4.ip_forward=1
   ```

   - **If the line doesn't exist:** Add it at the end of the file.

3. **Save and Exit:**

   - Press `Ctrl + O` and then `Enter` to save.
   - Press `Ctrl + X` to exit the editor.

4. **Apply the Changes Immediately:**

   ```bash
   sudo sysctl -p
   ```

   **Expected Output:**

   ```
   net.ipv4.ip_forward = 1
   ```

## **4. Proceed with WireGuard Configuration**

Now that IP forwarding is enabled, you can continue with configuring WireGuard on your Raspberry Pi and setting up your Android device.

### **Recap of Previous Steps Completed:**

1. **Installed WireGuard:**

   - `sudo apt install wireguard wireguard-tools`

2. **Generated Server Keys:**

   - `wg genkey | tee privatekey | wg pubkey > publickey`

3. **Identified Network Interface:**

   - `eth0` with IP `192.168.1.102`

4. **Confirmed Static Public IP:**
   - `REDACTED`

### **Next Steps:**

We'll create and configure the WireGuard server configuration file, set up firewall rules, generate keys for your Android device, and configure the WireGuard app on your phone.

---

## **5. Create the WireGuard Server Configuration File**

### **a. Retrieve Server Private and Public Keys**

Ensure you have your server's private and public keys ready.

```bash
cat privatekey
```

```bash
cat publickey
```

**Note:** Keep your private key secure. Do **not** share it publicly.

### **b. Create and Edit `/etc/wireguard/wg0.conf`**

Open the WireGuard configuration file in a text editor:

```bash
sudo nano /etc/wireguard/wg0.conf
```

### **c. Add the Following Configuration:**

Replace `YOUR_SERVER_PRIVATE_KEY` with the content of your `privatekey` file.

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = YOUR_SERVER_PRIVATE_KEY
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Example:**

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

### **d. Save and Exit**

- Press `Ctrl + O` and then `Enter` to save.
- Press `Ctrl + X` to exit the editor.

### **e. Secure the Configuration File**

Set appropriate permissions to protect your private key:

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

---

## **6. Start and Enable the WireGuard Service**

### **a. Bring Up the WireGuard Interface**

Activate the WireGuard interface:

```bash
sudo wg-quick up wg0
```

### **b. Verify WireGuard is Running**

Check the status of WireGuard:

```bash
sudo wg show
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820
```

### **c. Enable WireGuard to Start on Boot**

Ensure WireGuard starts automatically on system boot:

```bash
sudo systemctl enable wg-quick@wg0
```

---

## **7. Configure Port Forwarding on Your Router**

Since your Raspberry Pi has a static public IP (`REDACTED`), you need to forward UDP port `51820` to your Pi's internal IP (`192.168.1.102`) to allow external connections.

### **a. Access Your Router’s Admin Interface**

1. Open a web browser on a device connected to your home network.
2. Navigate to your router's admin page, typically at `http://192.168.1.1` or `http://192.168.0.1`.
3. Log in with your router's admin credentials.

### **b. Navigate to Port Forwarding Settings**

The exact location varies by router model, but commonly found under sections like:

- **Advanced**
- **NAT**
- **Firewall**
- **Virtual Servers**

### **c. Create a New Port Forwarding Rule**

Fill in the details as follows:

- **Service Name:** `WireGuard` (or any descriptive name)
- **Protocol:** `UDP`
- **External Port:** `51820`
- **Internal IP Address:** `192.168.1.102`
- **Internal Port:** `51820`
- **Enable the Rule:** Ensure it's active

**Example Configuration:**

| Field         | Value         |
| ------------- | ------------- |
| Service Name  | WireGuard     |
| Protocol      | UDP           |
| External Port | 51820         |
| Internal IP   | 192.168.1.102 |
| Internal Port | 51820         |
| Status        | Enabled       |

### **d. Save/Apply the Settings**

After entering the details, save or apply the new port forwarding rule. Your router might reboot or require confirmation.

**Note:** Router interfaces vary. If you need specific instructions for your router model, please provide the model details.

---

## **8. Generate a Key Pair for Your Android Phone**

To securely connect your Android device to the VPN, generate a unique key pair for it.

### **a. Generate the Phone’s Private and Public Keys**

Run the following commands on your Raspberry Pi:

```bash
wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
```

### **b. View the Phone’s Private Key**

```bash
cat phone_privatekey
```

**Example Output:**

```
abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

**Note:** **Keep this key secure.** You'll input it into your Android device.

### **c. View the Phone’s Public Key**

```bash
cat phone_publickey
```

**Example Output:**

```
1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

---

## **9. Add Your Android Phone as a Peer on the Server**

### **a. Edit the WireGuard Configuration File**

Open the WireGuard configuration file:

```bash
sudo nano /etc/wireguard/wg0.conf
```

### **b. Add the Following Peer Configuration at the End of the File**

Replace `YOUR_PHONE_PUBLIC_KEY` with the actual public key you obtained earlier.

```ini
[Peer]
# Android Phone
PublicKey = YOUR_PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

**Example:**

```ini
[Peer]
# Android Phone
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
AllowedIPs = 10.8.0.2/32
```

### **c. Save and Exit**

- Press `Ctrl + O` and then `Enter` to save.
- Press `Ctrl + X` to exit the editor.

### **d. Reload the WireGuard Configuration**

Apply the changes by restarting the WireGuard interface:

```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

### **e. Verify the Peer is Added**

Check the WireGuard status to ensure the peer is recognized:

```bash
sudo wg
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820

peer: YOUR_PHONE_PUBLIC_KEY
  endpoint: <not connected>
  allowed ips: 10.8.0.2/32
  latest handshake: <never>
  transfer: 0 B received, 0 B sent
```

---

## **10. Configure WireGuard on Your Android Phone**

### **a. Install the WireGuard App**

1. **Download:** [WireGuard on Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)
2. **Install:** Follow the on-screen instructions to install the app.

### **b. Create a New Tunnel**

1. **Open the WireGuard App.**
2. **Tap the "+" Button** at the bottom right.
3. **Select "Create from scratch."**

### **c. Configure the Interface**

- **Name:** `Home VPN` (or any name you prefer)

- **Private Key:** Paste the content of `phone_privatekey`

  **To Copy the Private Key:**

  - On the Pi, run:

    ```bash
    cat phone_privatekey
    ```

  - **Copy** the output.

  - **Paste** it into the WireGuard app under "Private Key."

- **Address:** `10.8.0.2/32`

- **DNS:** `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google DNS)

**Example Configuration:**

```
[Interface]
PrivateKey = abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address = 10.8.0.2/32
DNS = 1.1.1.1
```

### **d. Add a Peer**

1. **Tap "Add Peer."**
2. **Configure the Peer:**

   - **Public Key:** Paste `YOUR_SERVER_PUBLIC_KEY` (`cat publickey`).

     **To Copy the Server’s Public Key:**

     - On the Pi, run:

       ```bash
       cat publickey
       ```

     - **Copy** the output.

     - **Paste** it into the WireGuard app under "Public Key."

   - **Endpoint:** `REDACTED:51820`

   - **Allowed IPs:** `0.0.0.0/0` (routes all traffic through the VPN)

   - **Persistent Keepalive:** `25` (optional but recommended to maintain the connection)

**Example Peer Configuration:**

```
[Peer]
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### **e. Save the Tunnel**

- **Tap the Save Icon** (usually a checkmark) to save the configuration.

### **f. Activate the Tunnel**

- **Toggle the Switch** next to your newly created tunnel (`Home VPN`) to connect.

---

## **11. Verify the VPN Connection**

### **a. On Your Android Phone**

1. **Check IP Address:**

   - Open a web browser and navigate to [whatismyip.com](https://www.whatismyip.com/).
   - Ensure that the displayed IP address matches your home’s public IP (`REDACTED`).

2. **Check Connectivity to SMB Shares:**

   - Use a file explorer app that supports SMB (e.g., [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2)).
   - Add a new SMB connection using your home PC’s LAN IP (e.g., `192.168.1.x`).

### **b. On Your Raspberry Pi**

1. **Check WireGuard Status:**

   ```bash
   sudo wg
   ```

   **Expected Output:**

   ```
   interface: wg0
     public key: YOUR_SERVER_PUBLIC_KEY
     private key: (hidden)
     listening port: 51820

   peer: YOUR_PHONE_PUBLIC_KEY
     endpoint: REDACTED:PORT
     allowed ips: 10.8.0.2/32
     latest handshake: [timestamp]
     transfer: [data sent/received]
   ```

2. **Monitor Logs for Any Issues:**

   ```bash
   sudo journalctl -u wg-quick@wg0
   ```

   Look for any error messages that might indicate issues with the connection.

---

## **12. Accessing SMB Shares from Your Android Phone**

With the VPN connected, you can access SMB shares on your home network.

### **a. Ensure SMB is Accessible**

1. **On Your Home PC:**

   - Ensure that SMB sharing is enabled.
   - Verify that the shared folders are accessible within the LAN (`192.168.1.x`).

2. **Firewall Settings:**

   - Ensure that your home PC’s firewall allows SMB traffic from the VPN subnet (`10.8.0.0/24`).
   - You might need to create firewall rules to allow incoming SMB connections from `10.8.0.0/24`.

### **b. Use a File Explorer App on Android**

1. **Download and Install Solid Explorer:**

   - [Solid Explorer on Google Play](https://play.google.com/store/apps/details?id=pl.solidexplorer2)

2. **Add a New SMB Connection:**

   - Open Solid Explorer.
   - Tap the **"+"** button.
   - Select **"New cloud connection"** > **"SMB/CIFS"**.

3. **Configure the SMB Connection:**

   - **Name:** Descriptive name (e.g., `Home PC Share`)
   - **Host:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP)
   - **Username:** Your SMB username
   - **Password:** Your SMB password
   - **Workgroup:** (Optional) Your network's workgroup name

4. **Save and Connect:**

   - Save the configuration.
   - Tap on the newly created connection to access your SMB shares.

**Note:** If you encounter issues, ensure that your home PC allows SMB connections from the `10.8.0.0/24` subnet and that no firewall is blocking the traffic.

---

## **13. Additional Recommendations**

### **a. Secure Your WireGuard Configuration**

- **Protect Private Keys:**

  - Ensure that both `privatekey` and `phone_privatekey` files are secured.
  - Avoid sharing private keys publicly.

- **Regularly Update Your System:**

  - Keep your Raspberry Pi and WireGuard packages up to date to ensure security patches are applied.

    ```bash
    sudo apt update
    sudo apt upgrade -y
    ```

### **b. Backup Configuration Files**

- **Backup `/etc/wireguard/wg0.conf`:**

  Consider backing up your configuration file in a secure location.

  ```bash
  sudo cp /etc/wireguard/wg0.conf ~/wg0.conf.backup
  ```

### **c. Manage Multiple Peers**

- If you wish to add more devices in the future, generate new key pairs for each device and add them as separate `[Peer]` sections in `wg0.conf` with unique `AllowedIPs`.

---

## **Summary**

You've successfully addressed the issue with the missing `sysctl` command by installing the `procps` package and enabling IP forwarding. You can now continue with configuring WireGuard on your Raspberry Pi and setting up your Android device to connect securely to your home network. This setup will allow you to access SMB shares and route all your phone's internet traffic through your home connection.

**Key Points to Remember:**

- **Security:** Always keep your private keys secure. Never share them.
- **Firewall:** Ensure that necessary ports are open and firewall rules are correctly configured.
- **Testing:** Regularly test your VPN connection to ensure it's functioning as expected.
- **Updates:** Keep your system and WireGuard installation up to date to benefit from the latest security patches and features.

If you encounter any further issues or need additional assistance, feel free to ask!

#### You

```zsh
ivy@pi4 ~ ❯ sudo find / -type f -name sysctl 2>/dev/null
/usr/share/bash-completion/completions/sysctl
/usr/sbin/sysctl
```

The correct path is `/usr/sbin/sysctl`

I have added `/usr/sbin` to my $PATH

Now I can run the command:

```
ivy@pi4 ~ ❯ sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 0
```

Pick up where we left off.

#### ChatGPT

Excellent! You've successfully located the `sysctl` command and verified that IP forwarding is currently disabled (`net.ipv4.ip_forward = 0`). Let's proceed to enable IP forwarding and continue setting up your WireGuard VPN on the Raspberry Pi. Here's a comprehensive guide to help you through the remaining steps.

---

## **1. Enable IP Forwarding**

IP forwarding is essential for routing traffic between your VPN and local network. We'll enable it both temporarily (for the current session) and permanently (to persist across reboots).

### **a. Enable IP Forwarding Temporarily**

This change will take effect immediately but will be reset after a reboot.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

**Verification:**

```bash
sysctl net.ipv4.ip_forward
```

**Expected Output:**

```
net.ipv4.ip_forward = 1
```

### **b. Enable IP Forwarding Permanently**

To ensure IP forwarding remains enabled after a reboot, modify the `/etc/sysctl.conf` file.

1. **Open the Configuration File:**

   ```bash
   sudo nano /etc/sysctl.conf
   ```

2. **Uncomment or Add the Following Line:**

   Locate the line:

   ```
   #net.ipv4.ip_forward=1
   ```

   Remove the `#` to uncomment it:

   ```
   net.ipv4.ip_forward=1
   ```

   - **If the line doesn't exist:** Add it at the end of the file.

3. **Save and Exit:**

   - Press `Ctrl + O`, then `Enter` to save.
   - Press `Ctrl + X` to exit.

4. **Apply the Changes Immediately:**

   ```bash
   sudo sysctl -p
   ```

   **Expected Output:**

   ```
   net.ipv4.ip_forward = 1
   ```

---

## **2. Create the WireGuard Server Configuration File**

Now, let's set up the WireGuard server configuration on your Raspberry Pi.

### **a. Retrieve Your Server's Private and Public Keys**

Ensure you have your server's private and public keys ready.

- **View the Private Key:**

  ```bash
  cat privatekey
  ```

  **Example Output:**

  ```
  ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
  ```

- **View the Public Key:**

  ```bash
  cat publickey
  ```

  **Example Output:**

  ```
  1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  ```

**Note:** Keep your **private key** secure. Do **not** share it publicly.

### **b. Create and Edit `/etc/wireguard/wg0.conf`**

1. **Open the Configuration File:**

   ```bash
   sudo nano /etc/wireguard/wg0.conf
   ```

2. **Add the Following Configuration:**

   Replace `YOUR_SERVER_PRIVATE_KEY` with the content of your `privatekey` file.

   ```ini
   [Interface]
   Address = 10.8.0.1/24
   ListenPort = 51820
   PrivateKey = YOUR_SERVER_PRIVATE_KEY
   # NAT and forwarding rules on startup
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
   ```

   **Example:**

   ```ini
   [Interface]
   Address = 10.8.0.1/24
   ListenPort = 51820
   PrivateKey = ABCDEF1234567890abcdef1234567890abcdef1234567890abcdef1234567890
   # NAT and forwarding rules on startup
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
   ```

   **Explanation of Configuration:**

   - **\[Interface]:**
     - `Address`: Assigns the VPN subnet.
     - `ListenPort`: The port WireGuard listens on (default `51820`).
     - `PrivateKey`: Your server's private key.
   - **PostUp & PostDown:**
     - These commands handle NAT (Network Address Translation) and forwarding rules using `iptables` when the VPN interface is brought up or down.

3. **Save and Exit:**
   - Press `Ctrl + O`, then `Enter` to save.
   - Press `Ctrl + X` to exit.

### **c. Secure the Configuration File**

Set appropriate permissions to protect your private key.

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

---

## **3. Start and Enable the WireGuard Service**

With the configuration in place, let's start the WireGuard service and ensure it runs on boot.

### **a. Bring Up the WireGuard Interface**

Activate the WireGuard interface using `wg-quick`.

```bash
sudo wg-quick up wg0
```

**Note:** If you encounter any errors, ensure that the configuration file is correctly set up and that no other service is using port `51820`.

### **b. Verify WireGuard is Running**

Check the status of WireGuard to ensure it's active.

```bash
sudo wg show
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820
```

### **c. Enable WireGuard to Start on Boot**

Ensure that WireGuard starts automatically when your Raspberry Pi boots up.

```bash
sudo systemctl enable wg-quick@wg0
```

**Verification:**

```bash
sudo systemctl status wg-quick@wg0
```

**Expected Output:**

```
● wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0
     Loaded: loaded (/lib/systemd/system/wg-quick@.service; enabled; vendor preset: enabled)
     Active: active (exited) since ...
```

---

## **4. Configure Port Forwarding on Your Router**

To allow external devices (like your Android phone) to connect to your WireGuard server, you need to forward UDP port `51820` from your router to your Raspberry Pi's internal IP (`192.168.1.102`).

### **a. Access Your Router’s Admin Interface**

1. **Open a Web Browser:**

   - Navigate to `http://192.168.1.1` or the specific IP address for your router's admin panel.

2. **Log In:**

   - Enter your router's admin username and password.

   **Note:** If you're unsure of your router's admin credentials or IP address, refer to the router's manual or the manufacturer's website.

### **b. Navigate to Port Forwarding Settings**

The exact location varies by router model, but commonly found under sections like:

- **Advanced**
- **NAT**
- **Firewall**
- **Virtual Servers**

### **c. Create a New Port Forwarding Rule**

Fill in the details as follows:

| **Field**               | **Value**     |
| ----------------------- | ------------- |
| **Service Name**        | WireGuard     |
| **Protocol**            | UDP           |
| **External Port**       | 51820         |
| **Internal IP Address** | 192.168.1.102 |
| **Internal Port**       | 51820         |
| **Enable the Rule**     | Yes/Active    |

**Example Configuration:**

- **Service Name:** WireGuard
- **Protocol:** UDP
- **External Port:** 51820
- **Internal IP Address:** 192.168.1.102
- **Internal Port:** 51820
- **Status:** Enabled

### **d. Save/Apply the Settings**

After entering the details, save or apply the new port forwarding rule. Your router might reboot or require confirmation.

**Note:** Router interfaces vary. If you need specific instructions for your router model, please provide the model details.

---

## **5. Generate a Key Pair for Your Android Phone**

To securely connect your Android device to the VPN, generate a unique key pair for it.

### **a. Generate the Phone’s Private and Public Keys**

Run the following commands on your Raspberry Pi:

```bash
wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
```

### **b. View the Phone’s Private Key**

```bash
cat phone_privatekey
```

**Example Output:**

```
abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

**Note:** **Keep this key secure.** You'll input it into your Android device.

### **c. View the Phone’s Public Key**

```bash
cat phone_publickey
```

**Example Output:**

```
1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

---

## **6. Add Your Android Phone as a Peer on the Server**

Now, integrate your Android phone into the WireGuard server configuration.

### **a. Edit the WireGuard Configuration File**

Open the WireGuard configuration file:

```bash
sudo nano /etc/wireguard/wg0.conf
```

### **b. Add the Peer Configuration**

Add the following at the end of the file, replacing `YOUR_PHONE_PUBLIC_KEY` with the actual public key you obtained earlier.

```ini
[Peer]
# Android Phone
PublicKey = YOUR_PHONE_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
```

**Example:**

```ini
[Peer]
# Android Phone
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
AllowedIPs = 10.8.0.2/32
```

**Explanation:**

- **PublicKey:** The public key of your Android phone.
- **AllowedIPs:** Assigns a unique IP to your phone within the VPN (`10.8.0.2/32`).

### **c. Save and Exit**

- Press `Ctrl + O`, then `Enter` to save.
- Press `Ctrl + X` to exit.

### **d. Reload the WireGuard Configuration**

Apply the changes by restarting the WireGuard interface:

```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

### **e. Verify the Peer is Added**

Check the WireGuard status to ensure the peer is recognized:

```bash
sudo wg
```

**Expected Output:**

```
interface: wg0
  public key: YOUR_SERVER_PUBLIC_KEY
  private key: (hidden)
  listening port: 51820

peer: YOUR_PHONE_PUBLIC_KEY
  endpoint: <not connected>
  allowed ips: 10.8.0.2/32
  latest handshake: <never>
  transfer: 0 B received, 0 B sent
```

---

## **7. Configure WireGuard on Your Android Phone**

With the server configured, set up your Android device to connect to the VPN.

### **a. Install the WireGuard App**

1. **Download WireGuard:**

   - [WireGuard on Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)

2. **Install the App:**
   - Follow the on-screen instructions to install WireGuard on your Android device.

### **b. Create a New Tunnel**

1. **Open the WireGuard App.**

2. **Tap the "+" Button** at the bottom right.

3. **Select "Create from scratch."**

### **c. Configure the Interface**

- **Name:** `Home VPN` (or any name you prefer)

- **Private Key:** Paste the content of `phone_privatekey`

  **To Copy the Private Key:**

  - On the Pi, run:

    ```bash
    cat phone_privatekey
    ```

  - **Copy** the output.

  - **Paste** it into the WireGuard app under "Private Key."

- **Address:** `10.8.0.2/32`

- **DNS:** `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google DNS)

**Example Configuration:**

```
[Interface]
PrivateKey = abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address = 10.8.0.2/32
DNS = 1.1.1.1
```

### **d. Add a Peer**

1. **Tap "Add Peer."**

2. **Configure the Peer:**

   - **Public Key:** Paste `YOUR_SERVER_PUBLIC_KEY`

     **To Copy the Server’s Public Key:**

     - On the Pi, run:

       ```bash
       cat publickey
       ```

     - **Copy** the output.

     - **Paste** it into the WireGuard app under "Public Key."

   - **Endpoint:** `REDACTED:51820`

     **Note:** Since you have a static public IP, you don't need a Dynamic DNS service.

   - **Allowed IPs:** `0.0.0.0/0` (This routes all traffic through the VPN)

   - **Persistent Keepalive:** `25` (Optional but recommended to maintain the connection, especially behind NAT)

**Example Peer Configuration:**

```
[Peer]
PublicKey = 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### **e. Save the Tunnel**

- **Tap the Save Icon** (usually a checkmark) to save the configuration.

### **f. Activate the Tunnel**

- **Toggle the Switch** next to your newly created tunnel (`Home VPN`) to connect.

---

## **8. Verify the VPN Connection**

Ensure that your VPN is functioning correctly.

### **a. On Your Android Phone**

1. **Check IP Address:**

   - Open a web browser and navigate to [whatismyip.com](https://www.whatismyip.com/).
   - Ensure that the displayed IP address matches your home’s public IP (`REDACTED`).

2. **Check Connectivity to SMB Shares:**

   - Use a file explorer app that supports SMB (e.g., [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2)).

   - **Add a New SMB Connection:**
     - **Server Address:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP)
     - **Username and Password:** Your home PC’s SMB credentials.

### **b. On Your Raspberry Pi**

1. **Check WireGuard Status:**

   ```bash
   sudo wg
   ```

   **Expected Output:**

   ```
   interface: wg0
     public key: YOUR_SERVER_PUBLIC_KEY
     private key: (hidden)
     listening port: 51820

   peer: YOUR_PHONE_PUBLIC_KEY
     endpoint: YOUR_PHONE_PUBLIC_IP:PORT
     allowed ips: 10.8.0.2/32
     latest handshake: [timestamp]
     transfer: [data sent/received]
   ```

2. **Monitor Logs for Any Issues:**

   ```bash
   sudo journalctl -u wg-quick@wg0
   ```

   Look for any error messages that might indicate issues with the connection.

---

## **9. Accessing SMB Shares from Your Android Phone**

With the VPN connected, you can access SMB shares on your home network.

### **a. Ensure SMB is Accessible**

1. **On Your Home PC:**

   - **Enable SMB Sharing:**

     - Ensure that SMB sharing is enabled on your home PC.
     - **Windows:** Go to `Control Panel` > `Network and Sharing Center` > `Advanced sharing settings` and enable `File and printer sharing`.
     - **Linux:** Ensure Samba is installed and configured correctly.

   - **Verify Shared Folders:**
     - Ensure that the shared folders are accessible within the LAN (`192.168.1.x`).

2. **Firewall Settings:**

   - **On Your Home PC:**
     - Ensure that your firewall allows SMB traffic from the VPN subnet (`10.8.0.0/24`).
     - **Windows Firewall:**
       - Go to `Control Panel` > `Windows Defender Firewall` > `Advanced settings`.
       - Create a new inbound rule allowing SMB traffic from `10.8.0.0/24`.
     - **Linux Firewall:**
       - Adjust `ufw` or `iptables` rules to allow Samba from the VPN subnet.

### **b. Use a File Explorer App on Android**

1. **Download and Install Solid Explorer:**

   - [Solid Explorer on Google Play](https://play.google.com/store/apps/details?id=pl.solidexplorer2)

2. **Add a New SMB Connection:**

   - Open **Solid Explorer**.
   - Tap the **"+"** button.
   - Select **"New cloud connection"** > **"SMB/CIFS"**.

3. **Configure the SMB Connection:**

   - **Name:** Descriptive name (e.g., `Home PC Share`)
   - **Host:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP)
   - **Username:** Your SMB username
   - **Password:** Your SMB password
   - **Workgroup:** (Optional) Your network's workgroup name

4. **Save and Connect:**

   - Save the configuration.
   - Tap on the newly created connection to access your SMB shares.

**Note:** If you encounter issues:

- Ensure that your home PC allows SMB connections from the `10.8.0.0/24` subnet.
- Verify that no firewall is blocking the traffic.
- Confirm that the SMB service is running on your home PC.

---

## **10. Additional Recommendations**

### **a. Secure Your WireGuard Configuration**

- **Protect Private Keys:**

  - Ensure that both `privatekey` and `phone_privatekey` files are secured.
  - Avoid sharing private keys publicly.

- **Regularly Update Your System:**

  - Keep your Raspberry Pi and WireGuard packages up to date to ensure security patches are applied.

    ```bash
    sudo apt update
    sudo apt upgrade -y
    ```

### **b. Backup Configuration Files**

- **Backup `/etc/wireguard/wg0.conf`:**

  - Consider backing up your configuration file in a secure location.

    ```bash
    sudo cp /etc/wireguard/wg0.conf ~/wg0.conf.backup
    ```

### **c. Manage Multiple Peers**

- If you wish to add more devices in the future:
  - Generate new key pairs for each device.
  - Add them as separate `[Peer]` sections in `wg0.conf` with unique `AllowedIPs`.

---

## **Summary**

You've successfully:

1. **Enabled IP Forwarding:**

   - Both temporarily and permanently, allowing traffic routing through your VPN.

2. **Configured the WireGuard Server:**

   - Set up `/etc/wireguard/wg0.conf` with necessary interface and NAT settings.

3. **Started and Enabled WireGuard:**

   - Ensured the VPN service is active and will start on boot.

4. **Configured Router Port Forwarding:**

   - Forwarded UDP port `51820` to your Raspberry Pi's internal IP, allowing external VPN connections.

5. **Generated and Configured Client Keys:**

   - Created a unique key pair for your Android phone and added it as a peer in the server configuration.

6. **Set Up the Android WireGuard App:**

   - Configured the app to connect to your WireGuard server, routing all traffic through your home network.

7. **Verified VPN Functionality:**
   - Confirmed that your phone's IP matches your home IP and that you can access SMB shares on your home PC.

### **Key Points to Remember:**

- **Security:**

  - Always keep your private keys secure. Never share them.
  - Regularly update your system and WireGuard to benefit from security patches.

- **Firewall Configuration:**

  - Ensure that your home PC's firewall allows SMB traffic from the VPN subnet (`10.8.0.0/24`).

- **Testing:**

  - Regularly test your VPN connection to ensure it's functioning as expected.

- **Backup:**
  - Keep backups of your WireGuard configuration files in secure locations.

If you encounter any issues or need further assistance with any of the steps, feel free to ask!

#### You

Thanks.

```zsh
ivy@pi4 ~ 12s ❯ sudo sysctl -p
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
```

Moving onto Step 2

`/etc/wireguard/wg0.conf` is created exactly as you described, with the private key included.

its permissions are 600.

Moving onto step 3...

```zsh
ivy@pi4 ~ ❯ sudo wg-quick up wg0
[#] ip link add wg0 type wireguard
[#] wg setconf wg0 /dev/fd/63
[#] ip -4 address add 10.8.0.1/24 dev wg0
[#] ip link set mtu 1420 up dev wg0
[#] iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

```zsh
ivy@pi4 ~ ❯ sudo wg show
interface: wg0
  public key: REDACTED
  private key: (hidden)
  listening port: 51820
```

```zsh
ivy@pi4 ~ ❯ sudo systemctl enable wg-quick@wg0
Created symlink /etc/systemd/system/multi-user.target.wants/wg-quick@wg0.service → /lib/systemd/system/wg-quick@.service.
ivy@pi4 ~ ❯ sudo systemctl status wg-quick@wg0
○ wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0
     Loaded: loaded (/lib/systemd/system/wg-quick@.service; enabled; preset: enabled)
     Active: inactive (dead)
       Docs: man:wg-quick(8)
             man:wg(8)
             https://www.wireguard.com/
             https://www.wireguard.com/quickstart/
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8
```

Moving onto step 4...

Port forwarding is now set up.

Moving onto step 5...

```zsh
ivy@pi4 ~ ❯ wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
ivy@pi4 ~ ❯ ls
phone_privatekey  phone_publickey
```

The private and public keys for the phone have been stored safely.

Please understand all the above carefully before I move onto step 6, then await further instruction.

#### ChatGPT

Everything looks good so far—your WireGuard interface is up and running, and you’ve generated a key pair for your phone. The systemd output (`inactive (dead)`) is normal if you started WireGuard manually with `wg-quick up wg0` rather than through `systemctl start wg-quick@wg0`.

If you want WireGuard to be managed purely by systemd (so that a reboot automatically brings up `wg0` without you running `wg-quick up wg0`), you can use:

```bash
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

This should show the service as “active (exited)” or similar. Either way, since you already have the interface up, you’re good to continue.

---

### Next Steps (Step 6)

You’ll now add the phone’s public key to your server’s WireGuard config, then set up the WireGuard tunnel on your Android device.

1. **Add Phone’s Public Key to `wg0.conf`**

   - Open `/etc/wireguard/wg0.conf`:

     ```bash
     sudo nano /etc/wireguard/wg0.conf
     ```

   - At the end of the file, add a `[Peer]` section:

     ```ini
     [Peer]
     # Android Phone
     PublicKey = REPLACE_WITH_CONTENTS_OF_phone_publickey
     AllowedIPs = 10.8.0.2/32
     ```

   - Save and exit (`Ctrl + O`, then `Ctrl + X`).

2. **Reload WireGuard**

   - If you brought WireGuard up manually:

     ```bash
     sudo wg-quick down wg0
     sudo wg-quick up wg0
     ```

   - Or, if you want systemd to handle it:

     ```bash
     sudo systemctl restart wg-quick@wg0
     ```

   - Afterwards, confirm the peer was added:

     ```bash
     sudo wg
     ```

     You should see your phone’s public key under a “peer:” entry.

3. **Set Up the WireGuard App on Android**

   - Install the WireGuard app from the Play Store if you haven’t already.
   - Create a new tunnel:
     1. **Private Key**: your `phone_privatekey` (from the Pi).
     2. **Address**: `10.8.0.2/32`
     3. **DNS**: `1.1.1.1` or similar
     4. **Peer**:
        - **Public Key**: your Pi’s public key (the one in `publickey`, not the phone’s).
        - **Endpoint**: `YOUR_HOME_STATIC_IP:51820`
        - **Allowed IPs**: `0.0.0.0/0` (to route all traffic through your home)
        - **Persistent Keepalive**: `25`

4. **Test the Connection**
   - Enable the tunnel on your phone and go to [whatismyip.com](https://www.whatismyip.com/) to confirm you’re using your home’s public IP.
   - If you have SMB shares at home, try accessing them by their LAN IP (e.g., `192.168.1.x`) from a file explorer on your phone while on mobile data (i.e., not on your home Wi-Fi).

---

When you’re ready, proceed with Step 6 (adding the peer) and setting up your phone’s WireGuard tunnel. If you run into anything unexpected, just share the outputs and we’ll troubleshoot further!

#### You

Thanks, I'm now managing wireguard server via systemctl:

```zsh
ivy@pi4 ~ ❯ wg-quick down wg0
[#] ip link delete dev wg0
[#] iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ivy@pi4 ~ ❯ sudo systemctl start wg-quick@wg0
ivy@pi4 ~ ❯ sudo systemctl status wg-quick@wg0
● wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0
     Loaded: loaded (/lib/systemd/system/wg-quick@.service; enabled; preset: enabled)
     Active: active (exited) since Thu 2025-01-30 12:00:27 GMT; 5s ago
       Docs: man:wg-quick(8)
             man:wg(8)
             https://www.wireguard.com/
             https://www.wireguard.com/quickstart/
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8
             https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8
    Process: 31668 ExecStart=/usr/bin/wg-quick up wg0 (code=exited, status=0/SUCCESS)
   Main PID: 31668 (code=exited, status=0/SUCCESS)
        CPU: 133ms

Jan 30 12:00:27 pi4 systemd[1]: Starting wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0...
Jan 30 12:00:27 pi4 wg-quick[31668]: [#] ip link add wg0 type wireguard
Jan 30 12:00:27 pi4 wg-quick[31668]: [#] wg setconf wg0 /dev/fd/63
Jan 30 12:00:27 pi4 wg-quick[31668]: [#] ip -4 address add 10.8.0.1/24 dev wg0
Jan 30 12:00:27 pi4 wg-quick[31668]: [#] ip link set mtu 1420 up dev wg0
Jan 30 12:00:27 pi4 wg-quick[31668]: [#] iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; ip>
Jan 30 12:00:27 pi4 systemd[1]: Finished wg-quick@wg0.service - WireGuard via wg-quick(8) for wg0.
```

Moving onto step 5:

```zsh
ivy@pi4 ~ ❯ sudo nano /etc/wireguard/wg0.conf
ivy@pi4 ~ 28s ❯ sudo cat /etc/wireguard/wg0.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = REDACTED
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
[Peer]
# Pixel 8
PublicKey = REDACTED
AllowedIPs = 10.8.0.2/32
```

```zsh
ivy@pi4 ~ ❯ sudo systemctl restart wg-quick@wg0
ivy@pi4 ~ ❯ echo $?
0
ivy@pi4 ~ ❯ sudo wg
interface: wg0
  public key: REDACTED
  private key: (hidden)
  listening port: 51820

peer: REDACTED
  allowed ips: 10.8.0.2/32
```

What is the meaning of `allowed ips: 10.8.0.2/32`? I need to be able to access my home network from anywhere. e.g. other people's wifi, and my carrier's 5g network.

#### ChatGPT

In WireGuard, **AllowedIPs** has two major roles:

1. **On the **server** side**: It determines which IP addresses belong to that peer. Traffic destined for any IP listed under AllowedIPs for a peer will be routed _to_ that peer.

   - In your **server** config, `AllowedIPs = 10.8.0.2/32` simply says, “If traffic comes in for `10.8.0.2`, send it to this peer.”
   - It doesn’t control _from where_ a peer can connect—only what IPs belong _behind_ that peer on the VPN tunnel.

2. **On the **client** side** (your phone): It tells the phone which destinations should be routed **over** the tunnel to the WireGuard server.
   - If you set `AllowedIPs = 0.0.0.0/0` on the phone side, then **all** traffic (including requests to your home network and the wider internet) goes via the VPN.
   - If you set something narrower like `AllowedIPs = 10.8.0.0/24` and `192.168.1.0/24`, then _only_ traffic for those subnets will go through the VPN, and other internet traffic will bypass it.

---

## Why `10.8.0.2/32` Is Enough on the Server Side

- The server just needs to know that “**10.8.0.2** belongs to the phone,” so it can return traffic there.
- When your phone connects, it will be assigned `10.8.0.2` on the VPN interface. The server sees that IP and knows to send responses back via that peer.

## How to Access Your Home Network from Anywhere

1. **Server-Side**: `AllowedIPs = 10.8.0.2/32` for the phone peer is correct (which you already have).

2. **Phone-Side**: In your Android tunnel config, you should include either:
   - **`AllowedIPs = 0.0.0.0/0`** if you want **all** traffic to route via home.
   - **`AllowedIPs = 10.8.0.0/24, 192.168.1.0/24`** (or similar) if you only want to access home devices on `192.168.1.x` and `10.8.0.x` while still using the phone’s normal internet connection for everything else.

In other words, to get “connect from anywhere” and see your entire LAN, the phone’s config is the key. You’ll typically put something like:

```
[Peer]
PublicKey = <server’s public key>
Endpoint = YOUR_HOME_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

That ensures your phone tunnels all IP traffic back home (and thus it can see your SMB shares, local LAN devices, etc.). Because your server is set to do IP forwarding + NAT, your phone’s traffic can then get out to the internet as if it’s on your home connection, or access 192.168.1.x devices on your LAN.

---

### TL;DR

- **`AllowedIPs = 10.8.0.2/32` on the server** → “This peer _is_ 10.8.0.2.”
- **`AllowedIPs = 0.0.0.0/0` on the phone** → “Send everything over the tunnel to the server.”

That combination gives you full remote access, from any external Wi-Fi or cellular network, to your home LAN resources.

#### You

In the "DNS" section can I put the IP of my Pi hole? 192.168.1.102

#### ChatGPT

Yes, you can absolutely set the DNS in your WireGuard client (on your Android phone) to the IP address of your Pi-hole (`192.168.1.102`). This setup allows your phone to use Pi-hole for DNS resolution, ensuring that DNS queries are filtered through your Pi-hole while you're connected to the VPN from anywhere.

However, to ensure everything works smoothly, let's go through the necessary steps and considerations:

---

## **1. Understanding the Configuration**

### **a. AllowedIPs Explanation**

- **Server Side (`wg0.conf`):**

  ```ini
  [Peer]
  # Pixel 8
  PublicKey = REDACTED
  AllowedIPs = 10.8.0.2/32
  ```

  - **`AllowedIPs = 10.8.0.2/32`**: This tells the WireGuard server that the peer (your phone) is assigned the IP `10.8.0.2` within the VPN. Any traffic destined for `10.8.0.2` will be routed to this peer.

- **Client Side (Android Phone Configuration):**

  ```ini
  [Peer]
  PublicKey = REDACTED
  Endpoint = REDACTED:51820
  AllowedIPs = 0.0.0.0/0
  PersistentKeepalive = 25
  ```

  - **`AllowedIPs = 0.0.0.0/0`**: This routes **all** of your phone's internet traffic through the VPN, making it appear as if all traffic originates from your home network (`REDACTED`).

### **b. DNS Configuration**

- **Setting DNS to Pi-hole (`192.168.1.102`)**: This ensures that all DNS queries from your phone are handled by Pi-hole, enabling ad-blocking and enhanced privacy.

---

## **2. Configuring the Android WireGuard Client**

### **a. Open the WireGuard App**

1. **Install the App** (if you haven't already):

   - **Download:** [WireGuard on Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)
   - **Install:** Follow the on-screen instructions.

2. **Create a New Tunnel:**
   - Open the WireGuard app.
   - Tap the **"+"** button to create a new tunnel.
   - Select **"Create from scratch."**

### **b. Configure the Interface**

Fill in the `[Interface]` section with the following details:

```ini
[Interface]
PrivateKey = <phone_privatekey>
Address = 10.8.0.2/32
DNS = 192.168.1.102
```

- **`PrivateKey`**: Paste the content of your `phone_privatekey` file.
- **`Address`**: Assigns the VPN IP to your phone (`10.8.0.2/32`).
- **`DNS`**: Set to your Pi-hole's IP (`192.168.1.102`).

**Example:**

```ini
[Interface]
PrivateKey = abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address = 10.8.0.2/32
DNS = 192.168.1.102
```

### **c. Add a Peer**

Fill in the `[Peer]` section with the following details:

```ini
[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

- **`PublicKey`**: Your Raspberry Pi's WireGuard public key (from `wg0.conf`).
- **`Endpoint`**: Your home network's static IP followed by the WireGuard port (`REDACTED:51820`).
- **`AllowedIPs`**: `0.0.0.0/0` routes all traffic through the VPN.
- **`PersistentKeepalive`**: `25` seconds to maintain the NAT mapping, especially useful if your phone is behind a NAT.

**Example:**

```ini
[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### **d. Save the Configuration**

- Tap the **Save Icon** (usually a checkmark) to save the tunnel configuration.

### **e. Activate the Tunnel**

- Toggle the switch next to your newly created tunnel (`Home VPN`) to connect.

---

## **3. Verifying the Setup**

### **a. Check VPN Connection**

1. **IP Address Verification:**

   - Open a web browser on your Android phone.
   - Navigate to [whatismyip.com](https://www.whatismyip.com/) or [ipinfo.io](https://ipinfo.io/).
   - Confirm that the displayed IP address matches your home’s public IP (`REDACTED`).

2. **Pi-hole Query Verification:**

   - On your Raspberry Pi, monitor Pi-hole’s query logs:

     ```bash
     pihole -t
     ```

   - While the monitor is active, perform DNS queries from your phone (e.g., open a website).
   - Ensure that Pi-hole logs show these DNS requests coming from `10.8.0.2` or the corresponding IP.

### **b. Accessing SMB Shares**

1. **Ensure SMB is Accessible:**

   - On your home PC, verify that SMB sharing is enabled.
   - Ensure that the shared folders are accessible via `192.168.1.x`.

2. **Use a File Explorer App on Android:**

   - **Recommended App:** [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2) or [ES File Explorer](https://www.estrongs.com/) (note: ES File Explorer has privacy concerns; Solid Explorer is preferred).
   - **Configure SMB Connection:**
     - Open the file explorer app.
     - Add a new SMB connection.
     - **Host:** `192.168.1.x` (replace `x` with your home PC’s LAN IP).
     - **Username and Password:** Your SMB credentials.

3. **Connect and Browse:**
   - Access the SMB share through the app, confirming connectivity via the VPN.

---

## **4. Additional Considerations**

### **a. Pi-hole Configuration**

- **Ensure Pi-hole Accepts Queries from VPN:**
  - Pi-hole should automatically accept DNS queries from any IP if it's configured to listen on all interfaces. However, verify this in Pi-hole’s settings:
    - **Web Interface:** Navigate to Pi-hole’s admin panel (`http://192.168.1.102/admin`).
    - **Settings > DNS:** Ensure that Pi-hole is set to listen on all interfaces or at least on the interface connected to the VPN.

### **b. Firewall Rules**

- **On Raspberry Pi:**

  - Ensure that your firewall (iptables) allows DNS traffic from the VPN subnet (`10.8.0.0/24`):

    ```bash
    sudo iptables -I INPUT -p udp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    sudo iptables -I INPUT -p tcp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    ```

  - To make these rules persistent across reboots, consider using a firewall management tool like `iptables-persistent`:

    ```bash
    sudo apt install iptables-persistent
    sudo netfilter-persistent save
    ```

### **c. Security Best Practices**

- **Protect Private Keys:**

  - Ensure that both `privatekey` and `phone_privatekey` files are securely stored on your Raspberry Pi.
  - Avoid sharing private keys publicly or storing them in unsecured locations.

- **Regular Updates:**

  - Keep your Raspberry Pi and all installed packages up to date to benefit from the latest security patches:

    ```bash
    sudo apt update && sudo apt upgrade -y
    ```

- **Backup Configuration Files:**

  - Regularly backup your WireGuard configuration:

    ```bash
    sudo cp /etc/wireguard/wg0.conf ~/wg0.conf.backup
    ```

### **d. Managing Multiple Peers**

- If you plan to add more devices in the future:

  1. **Generate New Key Pairs for Each Device:**

     ```bash
     wg genkey | tee device_privatekey | wg pubkey > device_publickey
     ```

  2. **Add Each Device as a New Peer in `wg0.conf`:**

     ```ini
     [Peer]
     # Device Name
     PublicKey = DEVICE_PUBLIC_KEY
     AllowedIPs = 10.8.0.X/32
     ```

  3. **Reload WireGuard:**

     ```bash
     sudo wg-quick down wg0
     sudo wg-quick up wg0
     ```

---

## **5. Troubleshooting Tips**

### **a. DNS Not Resolving via Pi-hole**

- **Verify Pi-hole is Listening on All Interfaces:**

  - Check Pi-hole’s DNS settings to ensure it listens on the VPN interface.

- **Check Firewall Rules:**
  - Ensure that UDP and TCP traffic on port 53 is allowed from the VPN subnet.

### **b. Unable to Connect to SMB Shares**

- **Ping Test:**

  - From your Android phone, use a network utility app to ping `192.168.1.x` to ensure connectivity.

- **SMB Configuration:**

  - Ensure that your home PC’s SMB service is running and accessible from the VPN subnet.

- **Firewall on Home PC:**
  - Ensure that the firewall on your home PC allows SMB traffic from the VPN subnet (`10.8.0.0/24`).

### **c. WireGuard Connection Issues**

- **Check WireGuard Status:**

  ```bash
  sudo wg
  ```

  - Ensure that the peer (your phone) appears and that there are recent handshakes.

- **Check Logs:**

  ```bash
  sudo journalctl -u wg-quick@wg0
  ```

  - Look for any error messages or indications of connection problems.

- **Ensure Port Forwarding is Correct:**
  - Double-check that UDP port `51820` is correctly forwarded to your Raspberry Pi’s internal IP (`192.168.1.102`).

---

## **6. Summary**

You've successfully set up WireGuard on your Raspberry Pi and configured your Android phone to connect to your home network securely. By setting the DNS to your Pi-hole's IP (`192.168.1.102`), all DNS queries from your phone will be filtered through Pi-hole, providing you with ad-blocking and enhanced privacy even when you're connected from external networks like public Wi-Fi or your carrier's 5G network.

**Key Takeaways:**

- **AllowedIPs on Server:** Defines the IP assigned to each peer.
- **AllowedIPs on Client:** Determines which traffic is routed through the VPN.
- **DNS Configuration:** Pointing to Pi-hole enhances DNS-level privacy and ad-blocking.
- **Firewall and Pi-hole Settings:** Ensure accessibility and proper traffic flow through the VPN.

If you follow the above steps and ensure that all configurations are correctly applied, your VPN setup should work seamlessly, allowing you to access your home network and use Pi-hole's DNS filtering from anywhere.

If you encounter any further issues or have additional questions, feel free to ask!

#### You

When creating the tunnel on Android, what do I put in the "addresses" field? I tried putting `0.0.0.0/0` but it said invalid. I tried adding my home IP and that worked - but now where do I configure it to tunnel all Internet traffic through my wireguard server?

#### ChatGPT

You're on the right track! Let's clarify the configuration to ensure all your internet traffic tunnels through your WireGuard server, effectively routing it through your home network regardless of where you're connecting from (e.g., public Wi-Fi, cellular networks).

### **Understanding the WireGuard Configuration**

WireGuard configurations are divided into two main sections:

1. **\[Interface]**: Defines the settings for your device (in this case, your Android phone).
2. **\[Peer]**: Defines the settings for the remote server (your Raspberry Pi).

### **1. Correctly Configuring the \[Interface] Section on Android**

#### **a. Addresses Field**

- **Purpose**: Assigns an IP address to your Android device within the VPN network.
- **What to Put**: Use the IP address assigned to your phone by the server (e.g., `10.8.0.2/32`).

**Do Not** use `0.0.0.0/0` here; it's invalid for the `[Interface]` section and is meant for the `[Peer]` section to define routing rules.

#### **b. DNS Field**

- **Purpose**: Specifies which DNS server your device should use while connected to the VPN.
- **What to Put**: Your Pi-hole's IP address (`192.168.1.102`).

This ensures that all DNS queries are filtered through Pi-hole, providing ad-blocking and enhanced privacy.

### **2. Correctly Configuring the \[Peer] Section on Android**

#### **a. AllowedIPs Field**

- **Purpose**: Determines which traffic is routed through the VPN.
- **What to Put**: `0.0.0.0/0` and `::/0`

Setting `AllowedIPs = 0.0.0.0/0` routes all IPv4 traffic through the VPN. Similarly, `::/0` routes all IPv6 traffic through the VPN. This ensures that **all** your internet traffic appears to originate from your home network.

### **Step-by-Step Configuration on Your Android Phone**

Here's how to properly set up your WireGuard tunnel on your Android device to achieve full traffic tunneling through your home network.

#### **a. Open the WireGuard App**

1. **Install the App** (if you haven't already):
   - **Download:** [WireGuard on Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android)
   - **Install:** Follow the on-screen instructions.

#### **b. Create a New Tunnel**

1. **Launch WireGuard App.**
2. **Tap the "+" Button** at the bottom right corner.
3. **Select "Create from scratch."**

#### **c. Configure the \[Interface] Section**

Fill in the `[Interface]` details as follows:

```ini
[Interface]
PrivateKey = <phone_privatekey>
Address = 10.8.0.2/32
DNS = 192.168.1.102
```

- **PrivateKey**: Paste the content of `phone_privatekey` (generated on the Pi).
- **Address**: Assign the VPN IP to your phone (`10.8.0.2/32`).
- **DNS**: Set to your Pi-hole's IP (`192.168.1.102`).

**Example:**

```ini
[Interface]
PrivateKey = abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address = 10.8.0.2/32
DNS = 192.168.1.102
```

#### **d. Configure the \[Peer] Section**

Fill in the `[Peer]` details as follows:

```ini
[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

- **PublicKey**: Your Raspberry Pi's WireGuard public key (from `wg0.conf`).
- **Endpoint**: Your home network's static IP followed by the WireGuard port (`REDACTED:51820`).
- **AllowedIPs**: `0.0.0.0/0, ::/0` to route **all** traffic through the VPN.
- **PersistentKeepalive**: `25` seconds to maintain the connection, especially useful if your phone is behind NAT.

**Example:**

```ini
[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

#### **e. Save the Configuration**

1. **Tap the Save Icon** (usually a checkmark) to save the tunnel configuration.

#### **f. Activate the Tunnel**

1. **Toggle the Switch** next to your newly created tunnel (`Home VPN`) to connect.

### **3. Verifying the Configuration**

After setting up, it's crucial to verify that everything is functioning as intended.

#### **a. Verify VPN Connection**

1. **Check IP Address:**

   - Open a web browser on your Android phone.
   - Navigate to [whatismyip.com](https://www.whatismyip.com/) or [ipinfo.io](https://ipinfo.io/).
   - Confirm that the displayed IP address matches your home’s public IP (`REDACTED`).

2. **Check DNS Resolution via Pi-hole:**

   - On your Raspberry Pi, monitor Pi-hole’s query logs:

     ```bash
     pihole -t
     ```

   - Perform DNS queries from your phone (e.g., open a website).
   - Ensure that Pi-hole logs show these DNS requests coming from `10.8.0.2` or the corresponding VPN IP.

#### **b. Accessing SMB Shares**

1. **Ensure SMB is Accessible:**

   - On your home PC, verify that SMB sharing is enabled.
   - Ensure that the shared folders are accessible via `192.168.1.x`.

2. **Use a File Explorer App on Android:**

   - **Recommended App:** [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2)
   - **Configure SMB Connection:**
     - Open **Solid Explorer**.
     - Tap the **"+"** button.
     - Select **"New cloud connection"** > **"SMB/CIFS"**.
     - **Host:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP).
     - **Username and Password:** Your SMB credentials.
     - **Workgroup:** (Optional) Your network's workgroup name.

3. **Connect and Browse:**
   - Access the SMB share through the app, confirming connectivity via the VPN.

### **4. Additional Considerations**

#### **a. Pi-hole Configuration**

- **Ensure Pi-hole Accepts Queries from VPN:**
  - Pi-hole should be set to listen on all interfaces or at least on the VPN interface.
  - **Web Interface Steps:**
    1. Navigate to Pi-hole’s admin panel (`http://192.168.1.102/admin`).
    2. Go to **Settings** > **DNS**.
    3. Ensure **"Listen on all interfaces, permit all origins"** or a similar option is selected.

#### **b. Firewall Rules on Raspberry Pi**

- **Allow DNS Traffic from VPN:**

  - Ensure that your firewall allows DNS traffic (port 53) from the VPN subnet (`10.8.0.0/24`):

    ```bash
    sudo iptables -I INPUT -p udp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    sudo iptables -I INPUT -p tcp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    ```

  - **Make Firewall Rules Persistent:**

    ```bash
    sudo apt install iptables-persistent
    sudo netfilter-persistent save
    ```

#### **c. Security Best Practices**

- **Protect Private Keys:**

  - Ensure that both `privatekey` and `phone_privatekey` files are securely stored on your Raspberry Pi.
  - Avoid sharing private keys publicly or storing them in unsecured locations.

- **Regular Updates:**

  - Keep your Raspberry Pi and WireGuard packages up to date to benefit from the latest security patches:

    ```bash
    sudo apt update && sudo apt upgrade -y
    ```

- **Backup Configuration Files:**

  - Regularly backup your WireGuard configuration:

    ```bash
    sudo cp /etc/wireguard/wg0.conf ~/wg0.conf.backup
    ```

#### **d. Managing Multiple Peers**

- If you plan to add more devices in the future:

  1. **Generate New Key Pairs for Each Device:**

     ```bash
     wg genkey | tee device_privatekey | wg pubkey > device_publickey
     ```

  2. **Add Each Device as a New Peer in `wg0.conf`:**

     ```ini
     [Peer]
     # Device Name
     PublicKey = DEVICE_PUBLIC_KEY
     AllowedIPs = 10.8.0.X/32
     ```

  3. **Reload WireGuard:**

     ```bash
     sudo wg-quick down wg0
     sudo wg-quick up wg0
     ```

### **5. Troubleshooting Tips**

#### **a. DNS Not Resolving via Pi-hole**

- **Verify Pi-hole Settings:**
  - Ensure Pi-hole is set to listen on the VPN interface.
- **Check Firewall Rules:**
  - Ensure that DNS traffic is allowed from the VPN subnet.

#### **b. Unable to Connect to SMB Shares**

- **Ping Test:**
  - From your Android phone, use a network utility app to ping `192.168.1.x` to ensure connectivity.
- **SMB Configuration:**
  - Ensure that your home PC’s SMB service is running and accessible from the VPN subnet.
- **Firewall on Home PC:**
  - Ensure that the firewall on your home PC allows SMB traffic from the VPN subnet (`10.8.0.0/24`).

#### **c. WireGuard Connection Issues**

- **Check WireGuard Status:**

  ```bash
  sudo wg
  ```

  - Ensure that the peer (your phone) appears and that there are recent handshakes.

- **Check Logs:**

  ```bash
  sudo journalctl -u wg-quick@wg0
  ```

  - Look for any error messages or indications of connection problems.

- **Ensure Port Forwarding is Correct:**
  - Double-check that UDP port `51820` is correctly forwarded to your Raspberry Pi’s internal IP (`192.168.1.102`).

### **6. Summary**

- **\[Interface] Addresses** on your Android device should be set to its VPN-assigned IP (e.g., `10.8.0.2/32`), **not** `0.0.0.0/0`.
- **\[Peer] AllowedIPs** should be set to `0.0.0.0/0, ::/0` to route all traffic through the VPN.
- **DNS** can and should be set to your Pi-hole's IP (`192.168.1.102`) to utilize its DNS filtering capabilities.
- Ensure all firewall rules and Pi-hole settings are correctly configured to allow and handle VPN traffic.
- Test the setup by verifying your IP address, DNS resolution, and access to SMB shares from your Android device.

By following these steps, your Android phone will tunnel all its internet traffic through your WireGuard server, making it appear as if all traffic originates from your home network. Additionally, DNS queries will be filtered through Pi-hole, enhancing your privacy and reducing unwanted ads.

If you encounter any specific issues during configuration or testing, feel free to provide details, and I'll assist you further!

#### You

There is no AllowedIps field. There is no free-form text editor for me to make a config. The only fields are

Name Private key Addresses Listen port (by default = "random") DNS servers MTU (by default = "auto")

#### ChatGPT

Apologies for any confusion regarding the WireGuard Android app's interface. Let's clarify how to correctly configure the tunnel to ensure **all your internet traffic** is routed through your WireGuard server, effectively tunneling through your home network.

### **Understanding the Configuration Fields**

1. **\[Interface] Section**:

   - **Name**: A descriptive name for your VPN tunnel (e.g., `Home VPN`).
   - **Private Key**: The private key generated for your phone (`phone_privatekey`).
   - **Addresses**: The VPN IP assigned to your phone (e.g., `10.8.0.2/32`).
   - **DNS Servers**: Set to your Pi-hole's IP (`192.168.1.102`).
   - **Listen Port**: Typically left as "random" unless you have a specific reason to change it.
   - **MTU**: Usually left as "auto" unless you need to adjust it for specific network requirements.

2. **\[Peer] Section** (Not part of the initial \[Interface] setup):
   - **Public Key**: Your WireGuard server's public key.
   - **Endpoint**: Your home network's static IP followed by the WireGuard port (`REDACTED:51820`).
   - **Allowed IPs**: Determines which traffic is routed through the VPN. To route **all** traffic, use `0.0.0.0/0, ::/0`.
   - **Persistent Keepalive**: Set to `25` seconds to maintain the connection, especially useful if your phone is behind NAT.

### **Step-by-Step Configuration on Your Android Phone**

Follow these detailed steps to set up your WireGuard tunnel correctly:

#### **1. Open the WireGuard App and Create a New Tunnel**

1. **Launch the WireGuard App** on your Android device.
2. **Tap the "+" Button** at the bottom right corner to create a new tunnel.
3. **Select "Create from scratch."**

#### **2. Configure the \[Interface] Section**

Fill in the \[Interface] fields as follows:

- **Name**: Enter a descriptive name (e.g., `Home VPN`).
- **Private Key**:

  - **Option A**: Let the app generate a key pair automatically by tapping "Generate" or similar.
  - **Option B**: **Manually enter** the `phone_privatekey` you generated on your Raspberry Pi.

    - To do this, tap on the field and paste the content of `phone_privatekey`:

      ```bash
      cat phone_privatekey
      ```

- **Addresses**: Enter the VPN IP assigned to your phone. **Do not** use `0.0.0.0/0` here. Instead, use:

  ```
  10.8.0.2/32
  ```

- **DNS Servers**: Enter your Pi-hole's IP address:

  ```
  192.168.1.102
  ```

- **Listen Port**: Leave as "random" unless you have specific requirements.
- **MTU**: Leave as "auto" unless you need to adjust it.

**Example \[Interface] Configuration:**

```ini
[Interface]
PrivateKey = <phone_privatekey>
Address = 10.8.0.2/32
DNS = 192.168.1.102
```

**Note:** Replace `<phone_privatekey>` with the actual private key value.

#### **3. Add the \[Peer] Configuration**

After configuring the \[Interface], you'll need to add a peer (your WireGuard server). Here's how:

1. **Scroll Down** or **Find the "Peers" Section** within the WireGuard app interface.
2. **Tap on "Add Peer"** or a similar option to start configuring the peer.

**Fill in the \[Peer] Fields as Follows:**

- **Public Key**: Enter your WireGuard server's public key. Retrieve it from your Raspberry Pi:

  ```bash
  cat publickey
  ```

  **Example:**

  ```
  REDACTED
  ```

- **Endpoint**: Enter your home network's static IP and WireGuard port:

  ```
  REDACTED:51820
  ```

- **Allowed IPs**: To route **all** traffic through the VPN, enter:

  ```
  0.0.0.0/0, ::/0
  ```

  **Explanation:**

  - `0.0.0.0/0` routes all IPv4 traffic.
  - `::/0` routes all IPv6 traffic. **Note:** Some interfaces may require separate entries for IPv4 and IPv6. If the app doesn't accept commas, enter them as separate lines or fields.

- **Persistent Keepalive**: Enter `25`. This helps maintain the VPN connection, especially when the device is behind NAT.

**Example \[Peer] Configuration:**

```ini
[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

#### **4. Save and Activate the Tunnel**

1. **Tap the Save Icon** (usually a checkmark) to save the configuration.
2. **Activate the Tunnel** by toggling the switch next to your newly created tunnel (`Home VPN`).

#### **5. Verify the Configuration**

After activating the tunnel, perform the following checks to ensure everything is working correctly:

##### **a. Verify Your IP Address**

1. **Open a Web Browser** on your Android phone.
2. **Navigate to** [whatismyip.com](https://www.whatismyip.com/) or [ipinfo.io](https://ipinfo.io/).
3. **Confirm** that the displayed IP address matches your home’s public IP (`REDACTED`).

##### **b. Verify DNS Resolution via Pi-hole**

1. **On Your Raspberry Pi**, monitor Pi-hole’s query logs:

   ```bash
   pihole -t
   ```

2. **Perform DNS Queries** from your phone by opening various websites.
3. **Ensure** that Pi-hole logs show these DNS requests coming from `10.8.0.2` or the corresponding VPN IP.

##### **c. Access SMB Shares**

1. **Ensure SMB is Accessible:**

   - On your home PC, verify that SMB sharing is enabled.
   - Ensure that shared folders are accessible via `192.168.1.x`.

2. **Use a File Explorer App on Android:**

   - **Recommended App:** [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2) **Configure SMB Connection:**
   - Open **Solid Explorer**.
   - Tap the **"+"** button.
   - Select **"New cloud connection"** > **"SMB/CIFS"**.
   - **Host:** `192.168.1.x` (replace `x` with your home PC’s actual LAN IP).
   - **Username and Password:** Your SMB credentials.
   - **Workgroup:** (Optional) Your network's workgroup name.

3. **Connect and Browse:**
   - Access the SMB share through the app, confirming connectivity via the VPN.

### **Troubleshooting Tips**

If you encounter issues during configuration or testing, consider the following troubleshooting steps:

#### **1. DNS Issues**

- **Ensure Pi-hole is Listening on All Interfaces:**

  - **Web Interface Steps:**
    1. Navigate to Pi-hole’s admin panel (`http://192.168.1.102/admin`).
    2. Go to **Settings** > **DNS**.
    3. Ensure **"Listen on all interfaces, permit all origins"** or similar option is selected.

- **Check Firewall Rules:**

  - Ensure that DNS traffic (port 53) is allowed from the VPN subnet (`10.8.0.0/24`).
  - On Raspberry Pi:

    ```bash
    sudo iptables -I INPUT -p udp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    sudo iptables -I INPUT -p tcp -s 10.8.0.0/24 --dport 53 -j ACCEPT
    ```

  - To make these rules persistent:

    ```bash
    sudo apt install iptables-persistent
    sudo netfilter-persistent save
    ```

#### **2. Unable to Connect to SMB Shares**

- **Ping Test:**

  - From your Android phone, use a network utility app to ping `192.168.1.x` to ensure connectivity.

- **SMB Configuration:**

  - Ensure that your home PC’s SMB service is running and accessible from the VPN subnet.

- **Firewall on Home PC:**
  - Ensure that the firewall on your home PC allows SMB traffic from the VPN subnet (`10.8.0.0/24`).

#### **3. WireGuard Connection Issues**

- **Check WireGuard Status on Pi:**

  ```bash
  sudo wg
  ```

  - Ensure that the peer (your phone) appears and that there are recent handshakes.

- **Check Logs:**

  ```bash
  sudo journalctl -u wg-quick@wg0
  ```

  - Look for any error messages or indications of connection problems.

- **Ensure Port Forwarding is Correct:**
  - Double-check that UDP port `51820` is correctly forwarded to your Raspberry Pi’s internal IP (`192.168.1.102`).

#### **4. General Network Checks**

- **Ensure No IP Conflicts:**

  - Ensure that the VPN subnet (`10.8.0.0/24`) does not overlap with your home network's subnet (`192.168.1.0/24`).

- **Check MTU Settings:**
  - If experiencing connectivity issues, consider manually setting the MTU to `1420` (common for VPNs) instead of "auto".

### **Final Configuration Example**

**WireGuard Server (`/etc/wireguard/wg0.conf`):**

```ini
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = REDACTED
# NAT and forwarding rules on startup
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# Pixel 8
PublicKey = REDACTED
AllowedIPs = 10.8.0.2/32
```

**WireGuard Client (Android Phone) Configuration:**

```ini
[Interface]
PrivateKey = <phone_privatekey>
Address = 10.8.0.2/32
DNS = 192.168.1.102

[Peer]
PublicKey = REDACTED
Endpoint = REDACTED:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### **Summary**

- **\[Interface] Addresses** on your Android device should be set to its VPN-assigned IP (e.g., `10.8.0.2/32`), **not** `0.0.0.0/0`.
- **\[Peer] AllowedIPs** should be set to `0.0.0.0/0, ::/0` to route all traffic through the VPN.
- **DNS** can and should be set to your Pi-hole's IP (`192.168.1.102`) to utilize its DNS filtering capabilities.
- Ensure all firewall rules and Pi-hole settings are correctly configured to allow and handle VPN traffic.
- Test the setup by verifying your IP address, DNS resolution, and access to SMB shares from your Android device.

By following these steps, your Android phone will tunnel all its internet traffic through your WireGuard server, making it appear as if all traffic originates from your home network. Additionally, DNS queries will be filtered through Pi-hole, enhancing your privacy and reducing unwanted ads.

If you encounter any further issues or need additional assistance, feel free to ask!

#### You

there is no [Interface] fields.

Remember I already set up the server on my home network. I'm now trying to use my phone as a client - I want all the Internet traffic from my phone (eg. when out and about on 4g) to appear as if it's coming from my home network IP. I also want to be able to access my LAN SMB shares while out-and-about.

#### ChatGPT

On Android, the WireGuard app doesn’t explicitly label things as “\[Interface]” or “\[Peer]” the way text-based configs do, so it can be confusing. Here’s how to map the traditional WireGuard config sections onto the Android app’s fields so you can route **all** your mobile traffic through your home Pi (and access your LAN shares):

---

## 1. Create a New Tunnel in the WireGuard App

1. **Open the WireGuard app** on your phone.
2. **Tap the “+” button** (bottom right).
3. **Select “Create from scratch.”**

You’ll see a screen with fields for **Name**, **Private Key**, **Addresses**, **DNS Servers**, **Listen Port**, and **MTU** at the top. Beneath that, there is a “Peers” section where you can tap “+ Add Peer.”

---

## 2. Fill Out the Top Fields (Equivalent to “\[Interface]”)

- **Name**: Any descriptive name, e.g. “Home VPN.”
- **Private Key**: Your phone’s private key (the one you created on the Pi using `wg genkey | tee phone_privatekey | wg pubkey > phone_publickey`).

  - On the Pi:

    ```bash
    cat phone_privatekey
    ```

    Copy that whole line and paste it here.

- **Addresses**: `10.8.0.2/32`
  - This is the IP your phone will use on the VPN.
- **DNS Servers**: `192.168.1.102`
  - If you want to use Pi-hole on the Pi as your DNS. If you’re not using Pi-hole, you can use something like `1.1.1.1`.
- **Listen Port**: leave it as “random” or blank. (This is typically only needed if _your phone_ was acting as a server, which it is not.)
- **MTU**: leave as “auto” unless you have a specific reason to tweak it.

It might look like this when done:

```
Name:          Home VPN
Private Key:   <the long base64 string from phone_privatekey>
Addresses:     10.8.0.2/32
DNS Servers:   192.168.1.102
Listen Port:   random
MTU:           auto
```

---

## 3. Add a Peer (Equivalent to “\[Peer]”)

Below those fields, you should see a **“Peers”** heading. Tap the plus (“+ Add Peer”) to open the peer configuration. Enter:

- **Public Key**: Your server’s public key (from `cat publickey` on the Pi).
  - Example: `REDACTED`
- **Preshared Key**: (leave blank unless you specifically set one on the server).
- **Allowed IPs**: `0.0.0.0/0, ::/0`
  - This is key. It tells the phone to send **all** traffic (IPv4 and IPv6) via the VPN.
  - If the app won’t allow a comma-separated entry, try putting them on separate lines, or use the plus (“+”) icon if available. Some versions let you add them one by one.
- **Endpoint**: `YOUR_HOME_IP:51820`
  - If your static IP is `REDACTED`, then `REDACTED:51820`.
- **Keepalive** (aka **PersistentKeepalive**): `25` seconds
  - This helps keep NAT mappings open.

It might look like this:

```
Public Key:       REDACTED
Preshared Key:    (blank)
Allowed IPs:      0.0.0.0/0
                  ::/0
Endpoint:         REDACTED:51820
PersistentKeepalive: 25
```

---

## 4. Save and Connect

1. Tap the **checkmark** icon (top right) to save.
2. Toggle the switch next to the tunnel name (“Home VPN”) to enable.

---

## 5. Verify Everything

1. **Check your external IP**:
   - Browse to [whatismyip.com](https://whatismyip.com/) and confirm you see your home IP (`REDACTED`) rather than your mobile carrier’s IP.
2. **Access your LAN SMB shares**:
   - Use a file explorer that supports SMB (e.g., Solid Explorer).
   - Add a new SMB connection pointing to your PC’s LAN IP, like `192.168.1.x`, using your usual SMB username/password.

If it works from 4G (not on your home Wi-Fi), you know you’re tunneling all traffic through your home network.

---

## Common Pitfalls

- **Forgetting Allowed IPs**: If you don’t set `0.0.0.0/0, ::/0` under the Peer, only traffic to the `10.8.0.x` VPN subnet might route through the VPN, and you won’t get a “full tunnel.”
- **DNS**: If you set DNS to your Pi-hole, make sure Pi-hole is configured to listen on the VPN interface and that your Pi’s firewall allows DNS from `10.8.0.0/24`.
- **Server-Side**: Ensure your server config includes `[Peer]` with `AllowedIPs = 10.8.0.2/32` for your phone’s public key, and that port `51820/udp` is forwarded from your router to the Pi at `192.168.1.102`.

Once configured, you’ll have exactly what you want: your phone’s traffic will appear to come from your home IP, and you can reach local resources like SMB shares over the VPN.

#### You

Great, it's all working. I am connected to Wireguard while on 4g.

I can see my public IP is the same as my home network's public IP. Also, I can browse my SMB shares. Also, I gain the ability to use my Pi-hole while out and about.

Now I have a question:

What is the impact of leaving the VPN connection connected as always-on. What will the behaviour be when I'm already on my home wifi? Will there be a performance impact?

#### ChatGPT

Congratulations on successfully setting up your WireGuard VPN! It's great to hear that everything is functioning as intended, allowing you to access your home network securely from anywhere.

### **Your Current Setup:**

- **Always-On VPN:** Connected via 4G, routing all internet traffic through your home network.
- **Capabilities:**
  - Your phone's public IP matches your home network's IP.
  - Access to SMB shares on your home LAN.
  - Utilization of Pi-hole for DNS filtering while mobile.

### **Your Question:**

> **What is the impact of leaving the VPN connection connected as always-on? What will the behavior be when I'm already on my home Wi-Fi? Will there be a performance impact?**

### **Answer:**

Leaving your VPN connection as always-on is a common configuration for users seeking continuous privacy, security, and access to their home network resources. However, it's essential to understand how this setup behaves under different network conditions, especially when you're connected to your home Wi-Fi. Here's a comprehensive breakdown:

---

#### **1. Behavior When Connected to Home Wi-Fi:**

**a. Loopback Routing:**

- **Direct Access:** When your phone is connected to the same Wi-Fi network as your VPN server (Raspberry Pi), the VPN tunnel can still be active. However, WireGuard is efficient enough to recognize that the destination (your home network) is directly reachable.
- **Local Routing:** Traffic intended for your home LAN (e.g., SMB shares) can bypass the VPN tunnel and communicate directly with the devices on the same local network. This minimizes unnecessary routing through the VPN.

**b. Endpoint Addressing:**

- **Same Network Recognition:** WireGuard doesn't inherently differentiate between internal and external connections. If your phone is on the same network, the communication between the phone and the server remains local, reducing latency.

**c. Potential Redundancy:**

- **Minimal Impact:** While the VPN tunnel remains active, most of your local traffic won't traverse the tunnel unnecessarily. Only traffic destined for IPs outside your home network will use the VPN.

---

#### **2. Performance Impact:**

\*\*a. **Bandwidth and Latency:**

- **Local Network Traffic:** Accessing resources on your home LAN (like SMB shares) remains swift and doesn't incur the overhead of the VPN tunnel.
- **Internet Traffic:** When on home Wi-Fi, your phone routes internet traffic through the VPN as it would from any other network. However, since the VPN server is on your local network, the data doesn't leave your LAN, resulting in minimal latency and no significant bandwidth reduction.

\*\*b. **Resource Utilization:**

- **Raspberry Pi:** Your Pi handles both the VPN server and Pi-hole functionalities. Ensure that the Pi has sufficient resources (CPU, memory) to manage multiple tasks without performance degradation. For most home setups, a Raspberry Pi 4 should handle these tasks efficiently.
- **Phone Battery:** Maintaining an always-on VPN connection can have a slight impact on your phone's battery life. WireGuard is designed to be lightweight and efficient, so the impact should be minimal compared to other VPN protocols.

\*\*c. **Network Overhead:**

- **Encryption and Decryption:** WireGuard uses state-of-the-art cryptography that's both secure and performant. The encryption overhead is negligible on modern devices, including smartphones and Raspberry Pi.

---

#### **3. Advantages of Always-On VPN:**

\*\*a. **Continuous Protection:**

- **Security:** All your internet traffic is encrypted, safeguarding against potential threats on untrusted networks (e.g., public Wi-Fi).
- **Privacy:** Your ISP and other entities cannot easily monitor your browsing activities since all traffic appears to originate from your home IP.

\*\*b. **Seamless Access to Home Resources:**

- **Remote Access:** Access your home SMB shares, Pi-hole, and other LAN resources as if you were physically present on your home network.
- **Consistent DNS Filtering:** Even when mobile, your DNS queries are filtered through Pi-hole, maintaining ad-blocking and tracking protection.

---

#### **4. Considerations and Best Practices:**

\*\*a. **DNS Configuration:**

- **Pi-hole Accessibility:** Ensure Pi-hole is configured to accept DNS queries from the VPN subnet (`10.8.0.0/24`). This is typically handled by your WireGuard setup, but double-check Pi-hole settings to confirm.

\*\*b. **Firewall Rules:**

- **Pi-hole and WireGuard:** Verify that your Raspberry Pi's firewall allows DNS traffic (port 53) from the VPN subnet. This ensures that DNS queries from your phone are correctly processed by Pi-hole.

\*\*c. **Monitoring and Maintenance:**

- **Resource Usage:** Periodically monitor your Raspberry Pi's resource usage to ensure it isn't being overtaxed by the VPN and Pi-hole services.
- **Updates:** Keep your Raspberry Pi, WireGuard, and Pi-hole updated to benefit from security patches and performance improvements.

\*\*d. **Battery Optimization:**

- **Android Settings:** Some Android devices offer battery optimization settings that might interfere with always-on VPNs. Ensure the WireGuard app is exempted from any battery-saving restrictions to maintain a stable connection.

---

#### **5. Potential Scenarios and Their Outcomes:**

\*\*a. **On Home Wi-Fi:**

- **Behavior:** VPN remains connected. Local traffic (to SMB shares) bypasses the VPN, while internet traffic is routed through the VPN server on the same network.
- **Impact:** Minimal performance degradation. Some additional overhead for maintaining the VPN connection, but negligible.

\*\*b. **On External Networks (e.g., 4G, Public Wi-Fi):**

- **Behavior:** All internet traffic is tunneled through your home network. You can access LAN resources remotely.
- **Impact:** Enhanced security and privacy. Potentially slightly higher latency depending on your home network's internet speed and the distance between your mobile device and your home.

---

#### **6. How to Optimize Performance and User Experience:**

\*\*a. **Use Split Tunneling (If Needed):**

- **Selective Routing:** If you prefer only specific traffic (e.g., access to LAN shares) to go through the VPN while other traffic uses the local network's internet, you can adjust the `AllowedIPs` in the client configuration.
- **Note:** This requires modifying the WireGuard client config to specify which IP ranges should use the VPN.

\*\*b. **Adjust MTU Settings:**

- **Optimal Packet Size:** If you experience connectivity issues or reduced speeds, consider manually setting the MTU (Maximum Transmission Unit) to a lower value (e.g., `1420`) to prevent packet fragmentation.

\*\*c. **Ensure Stable Server Connection:**

- **Reliable Home Network:** Your home network's stability directly affects your VPN's reliability. Ensure your Raspberry Pi is always connected and that your router maintains the port forwarding settings.

\*\*d. **Monitor Pi-hole Performance:**

- **DNS Query Load:** With continuous DNS queries from your phone, monitor Pi-hole to ensure it isn't overwhelmed, especially if multiple devices connect via VPN.

---

### **Conclusion:**

**Leaving the VPN connection always-on is generally safe and efficient, especially with WireGuard's optimized performance.** When connected to your home Wi-Fi, the VPN operates seamlessly, routing external traffic through your home network while accessing LAN resources directly. The performance impact is minimal, primarily involving slight additional processing for maintaining the VPN connection and encrypted traffic handling.

**Benefits include:**

- **Enhanced Security:** Continuous encryption protects your data on any network.
- **Privacy:** Your online activities are masked behind your home IP.
- **Access to Home Resources:** Seamless connection to SMB shares and other LAN devices from anywhere.

**Potential Downsides are:**

- **Minor Battery Drain:** Due to the persistent VPN connection.
- **Slight Latency Increase:** Although minimal when on the same network, it can be more noticeable on external networks depending on your home internet speed.

**Overall**, the advantages of an always-on VPN setup with WireGuard, especially for accessing home network resources and maintaining DNS filtering via Pi-hole, outweigh the minor drawbacks. Ensure you follow best practices for security and maintenance to enjoy a smooth and secure VPN experience.

If you have any further questions or need assistance with additional configurations, feel free to ask!

#### You

Thanks. It took a long time to get here. Can you please review the conversation and provide a concise, yet detailed summary for my future reference?

#### ChatGPT

#### You

Thanks. Please provide a summary of my setup for my future reference. Be concise, yet comprehensive, and double check facts for accuracy.

#### ChatGPT

Below is a concise yet comprehensive summary of your final WireGuard setup, capturing all vital details and correct configurations for your reference.

---

## **WireGuard Setup Summary**

### **1. Overview**

- **Server Location:** Raspberry Pi running Debian 12, LAN IP `192.168.1.102`, static public IP `REDACTED`.
- **VPN Subnet:** `10.8.0.0/24`; server is `10.8.0.1`, client (phone) is `10.8.0.2`.
- **Primary Goals:**
  1. Route **all** phone traffic (4G or external Wi-Fi) through your home network.
  2. Access home LAN SMB shares and Pi-hole from anywhere.
  3. Utilize Pi-hole (`192.168.1.102`) for DNS filtering on the phone while remote.

---

### **2. Raspberry Pi Configuration**

1. **Install WireGuard:**

   ```bash
   sudo apt update
   sudo apt install wireguard wireguard-tools -y
   ```

2. **Enable IP Forwarding:**

   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo nano /etc/sysctl.conf  # Ensure net.ipv4.ip_forward=1 is uncommented
   sudo sysctl -p
   ```

3. **Generate Server Keys:**

   ```bash
   wg genkey | tee privatekey | wg pubkey > publickey
   ```

   - Keep `privatekey` secure; `publickey` is shared with clients.

4. **Create `/etc/wireguard/wg0.conf`:**

   ```ini
   [Interface]
   Address = 10.8.0.1/24
   ListenPort = 51820
   PrivateKey = <SERVER_PRIVATE_KEY>
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
   ```

5. **Start WireGuard and Enable at Boot:**

   ```bash
   sudo wg-quick up wg0
   sudo systemctl enable wg-quick@wg0
   ```

6. **Router Port Forwarding:**
   - Forward UDP port `51820` to `192.168.1.102` (Raspberry Pi).

---

### **3. Phone Client Configuration**

1. **Generate Phone Keys on Pi:**

   ```bash
   wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
   ```

2. **Add Peer to Server:**\
   In `/etc/wireguard/wg0.conf`:

   ```ini
   [Peer]
   # Phone
   PublicKey = <PHONE_PUBLIC_KEY>
   AllowedIPs = 10.8.0.2/32
   ```

   Then restart:

   ```bash
   sudo wg-quick down wg0 && sudo wg-quick up wg0
   ```

3. **Configure WireGuard App (Android):**

   - **New Tunnel**
     - **Private Key** = `phone_privatekey` from Pi
     - **Addresses** = `10.8.0.2/32`
     - **DNS Servers** = `192.168.1.102` (Pi-hole)
   - **Add Peer**
     - **Public Key** = Pi’s `publickey`
     - **Endpoint** = `REDACTED:51820`
     - **Allowed IPs** = `0.0.0.0/0, ::/0` (routes all traffic)
     - **Persistent Keepalive** = `25`

4. **Connect:**
   - Toggle the WireGuard tunnel on the phone to verify full-tunnel access.
   - Check [whatismyip.com](https://whatismyip.com/) or similar to confirm your phone’s public IP matches home IP (`REDACTED`).
   - Access SMB shares at `192.168.1.x` and verify Pi-hole DNS in phone’s traffic logs (`pihole -t`).

---

### **4. Validation & Behavior**

- **All Traffic Routing:**\
  By setting `AllowedIPs = 0.0.0.0/0, ::/0` on the phone, **all** external traffic is tunneled through home.
- **Home Wi-Fi Behavior:**\
  If you stay connected to the VPN while on the same LAN as your Pi, local traffic generally bypasses the VPN due to direct LAN accessibility. The overhead remains minimal.
- **Performance Impact:**\
  WireGuard is lightweight. Expect a minor overhead for encryption, slight battery drain on your phone, but generally negligible.

---

### **5. Additional Considerations**

1. **DNS & Pi-hole:**

   - Ensure Pi-hole listens on the VPN subnet (`10.8.0.0/24`).
   - Confirm firewall rules allow DNS (port 53) from the VPN subnet.

2. **SMB Access:**

   - Confirm the PC hosting SMB shares allows connections from `10.8.0.0/24`.
   - Use a file explorer supporting SMB (e.g., Solid Explorer).

3. **Firewall and Updates:**

   - Keep your Pi updated (`sudo apt update && sudo apt upgrade -y`).
   - Secure the Pi with appropriate firewall rules (`iptables` or `ufw`) if needed.

4. **Always-On VPN:**

   - The phone can remain connected indefinitely for continuous Pi-hole DNS and home network access.
   - Minimal performance penalty when on your home Wi-Fi.

5. **Adding More Peers:**
   - For each new device, generate unique keys, add a new `[Peer]` with a unique IP (`10.8.0.x/32`), and configure that device similarly.

---

## **Conclusion**

Your WireGuard VPN setup allows **full tunnel** remote access to your home network, including SMB shares and Pi-hole DNS filtering, all while showing your phone’s external traffic as coming from your home IP. The configuration is stable, efficient, and straightforward to maintain. Keep keys secure, stay current on updates, and enjoy secure, private connections from anywhere.

#### You

Based on up to date research, what are some use-cases for my new setup which I may not have considered?

#### ChatGPT

Congratulations on setting up your WireGuard VPN! Beyond the functionalities you've already implemented, here are some additional use cases you might consider:

1. **Secure IoT Device Connectivity**: Integrate your Internet of Things (IoT) devices into the VPN to enhance security. By routing IoT traffic through WireGuard, you can protect these devices from potential vulnerabilities and unauthorized access. citeturn0academia11

2. **Mesh Networking**: Leverage WireGuard's capability to create a mesh network, allowing multiple devices to connect directly to each other. This setup is beneficial for interconnecting multiple locations or devices without routing all traffic through a central server. citeturn0search0

3. **VPN as a Service (VPNaaS)**: Deploy WireGuard to provide VPN services for various applications, such as securing connections between network functions in a 5G environment. This approach can offer encrypted tunnels and traffic isolation for different services. citeturn0academia9

4. **Bypass Geo-Restrictions**: Use your VPN to access content that is restricted based on geographic location. By connecting through your home network, you can appear to be browsing from your home country, allowing access to region-specific services.

5. **Enhanced Privacy on Public Networks**: When using public Wi-Fi networks, maintain your privacy by routing traffic through your home network via the VPN. This ensures encrypted communication and protects your data from potential eavesdropping.

6. **Simplified Remote Management**: Manage devices on your home network remotely as if you were physically present. This is particularly useful for tasks like configuring routers, accessing files on home servers, or troubleshooting devices.

7. **Cost-Effective Site-to-Site Connectivity**: Connect multiple physical locations securely over the internet without the need for expensive dedicated lines. WireGuard can establish secure tunnels between sites, facilitating seamless communication.

8. **Improved Performance for Remote Work**: Enhance the performance of remote work applications by providing a secure and efficient connection to your home network, reducing latency and improving access speeds compared to traditional VPN solutions.

By exploring these use cases, you can maximize the benefits of your WireGuard VPN setup and tailor it to meet various networking and security needs.

#### You

# Final conversation review task

Explain what I did and why I wanted in a couple of sentences to someone who knows about networking but has never set up a VPN before.

#### ChatGPT

You set up a WireGuard VPN on your Raspberry Pi to route all internet traffic from your phone through your home network, ensuring that your phone uses your home’s public IP and benefits from Pi-hole's DNS filtering even while on mobile data or public Wi-Fi. This setup also enables you to access your home LAN resources, like SMB shares, securely from anywhere.

#### You

My co-worker wants to achieve the same setup with his Raspberry Pi and Android phone. Produce a distilled guide, based on what we learned throughout this conversation. Make sure my co-worker doesn't stumble into the same pitfalls as I did. The final guide should be definitive, with the goal to avoid confusion and ambiguity.

#### ChatGPT

Here’s a distilled, step-by-step guide for your co-worker to achieve the same WireGuard VPN setup on their Raspberry Pi and Android phone, with a focus on avoiding common pitfalls:

---

## **WireGuard VPN Setup Guide: Raspberry Pi and Android**

### **Overview**

This guide will help you set up a WireGuard VPN on a Raspberry Pi so you can route all traffic from your Android phone through your home network (using your home’s public IP). You’ll also be able to access local resources (e.g., SMB shares) securely and use Pi-hole for DNS filtering while on mobile data or public Wi-Fi.

---

### **Step 1: Install WireGuard on Raspberry Pi (Server)**

1. **Install WireGuard:**

   - Update and install WireGuard on the Raspberry Pi (ensure it's running Debian or a similar Linux distro):

     ```bash
     sudo apt update
     sudo apt install wireguard wireguard-tools -y
     ```

2. **Enable IP Forwarding:**

   - Temporarily enable IP forwarding:

     ```bash
     sudo sysctl -w net.ipv4.ip_forward=1
     ```

   - To ensure it's always enabled after a reboot, edit `/etc/sysctl.conf`:

     ```bash
     sudo nano /etc/sysctl.conf
     ```

     Uncomment or add this line:

     ```
     net.ipv4.ip_forward=1
     ```

   - Apply the changes:

     ```bash
     sudo sysctl -p
     ```

3. **Generate Server Keys:**

   - On your Raspberry Pi, generate WireGuard keys for the server:

     ```bash
     wg genkey | tee privatekey | wg pubkey > publickey
     ```

   - Keep the `privatekey` secure. The `publickey` will be shared with the client.

---

### **Step 2: Configure WireGuard on Raspberry Pi**

1. **Create WireGuard Configuration File (`wg0.conf`):**

   - Create and edit the config file:

     ```bash
     sudo nano /etc/wireguard/wg0.conf
     ```

2. **Add Configuration:** **Server Configuration:**

   ```ini
   [Interface]
   Address = 10.8.0.1/24
   ListenPort = 51820
   PrivateKey = <SERVER_PRIVATE_KEY>  # Replace with the content of privatekey file
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

   [Peer]
   # Android Phone
   PublicKey = <PHONE_PUBLIC_KEY>  # To be filled in later
   AllowedIPs = 10.8.0.2/32
   ```

   - Replace `<SERVER_PRIVATE_KEY>` with the content from `privatekey`.
   - `PublicKey` will be filled in later after generating keys for the phone.
   - `AllowedIPs = 10.8.0.2/32` tells the server that the phone will use the IP `10.8.0.2`.

3. **Start WireGuard and Enable at Boot:**

   - Bring up the WireGuard interface:

     ```bash
     sudo wg-quick up wg0
     ```

   - Enable WireGuard to start automatically on boot:

     ```bash
     sudo systemctl enable wg-quick@wg0
     ```

---

### **Step 3: Configure Router Port Forwarding**

1. **Forward UDP port 51820** from your router to the Raspberry Pi’s internal IP (`192.168.1.102`).
2. Access your router's admin interface, typically at `http://192.168.1.1`, and forward UDP port `51820` to the Raspberry Pi’s LAN IP.

---

### **Step 4: Generate Client Keys (Phone)**

1. **Generate Client Keys** on the Raspberry Pi:

   ```bash
   wg genkey | tee phone_privatekey | wg pubkey > phone_publickey
   ```

   - The `phone_privatekey` will go into the Android app.
   - The `phone_publickey` will be added to the server’s configuration.

---

### **Step 5: Add Client (Phone) as Peer on Server**

1. **Add Client to Server Configuration:**

   - Edit `/etc/wireguard/wg0.conf` again:

     ```bash
     sudo nano /etc/wireguard/wg0.conf
     ```

   - Add the peer (your phone’s public key):

     ```ini
     [Peer]
     PublicKey = <PHONE_PUBLIC_KEY>  # Replace with the content of phone_publickey
     AllowedIPs = 10.8.0.2/32
     ```

   - **Reload WireGuard:**

     ```bash
     sudo wg-quick down wg0
     sudo wg-quick up wg0
     sudo wg
     ```

---

### **Step 6: Set Up WireGuard on Android Phone (Client)**

1. **Install WireGuard App** from [Google Play Store](https://play.google.com/store/apps/details?id=com.wireguard.android).

2. **Create a New Tunnel:**

   - Tap the **"+"** button > **Create from scratch**.

3. **Configure the Interface:**

   - **Private Key**: Paste the content of `phone_privatekey`.
   - **Addresses**: `10.8.0.2/32` (This is the phone's VPN IP).
   - **DNS Servers**: `192.168.1.102` (Pi-hole's IP).
   - **Listen Port**: Leave it as "random" (default).
   - **MTU**: Leave as "auto" (default).

4. **Configure the Peer:**

   - **Public Key**: Paste the server’s `publickey` (from `publickey`).
   - **Endpoint**: `137.220.120.19:51820` (Your home’s static public IP and WireGuard port).
   - **Allowed IPs**: `0.0.0.0/0, ::/0` (Route **all** traffic through the VPN).
   - **Persistent Keepalive**: `25` (To maintain the connection, especially behind NAT).

5. **Save and Connect**:
   - Save the configuration.
   - Toggle the connection on.

---

### **Step 7: Verify Everything**

1. **Check Your IP:**

   - Visit [whatismyip.com](https://www.whatismyip.com/) and verify that the IP matches your home’s public IP (`137.220.120.19`).

2. **Verify Pi-hole Filtering:**

   - On your Raspberry Pi, monitor Pi-hole logs:

     ```bash
     pihole -t
     ```

   - Check if DNS queries are coming from `10.8.0.2`.

3. **Access SMB Shares:**
   - Use a file explorer app (e.g., Solid Explorer) to access SMB shares at `192.168.1.x` (your home PC's IP).
   - Ensure the connection is successful.

---

### **Common Pitfalls to Avoid:**

1. **Misconfigured DNS:**

   - Ensure the `DNS Servers` field on your phone is correctly set to `192.168.1.102` (Pi-hole’s IP) for DNS filtering.

2. **Incorrect Allowed IPs:**

   - **Client**: Set `AllowedIPs = 0.0.0.0/0, ::/0` to route all traffic through the VPN.
   - **Server**: Ensure the phone’s `publickey` is correctly added and `AllowedIPs = 10.8.0.2/32` is set.

3. **Router Port Forwarding:**

   - Make sure UDP port `51820` is forwarded correctly from your router to the Raspberry Pi.

4. **Firewall Configuration:**

   - Ensure Pi-hole allows DNS queries from `10.8.0.0/24`.
   - Ensure the Raspberry Pi’s firewall is not blocking the WireGuard or DNS traffic.

5. **VPN Disconnecting on Mobile Networks:**
   - Use **Persistent Keepalive = 25** to keep the VPN connection stable when switching networks (e.g., 4G to Wi-Fi).

---

### **Conclusion**

You’ve set up a **full-tunnel VPN** that routes all internet traffic through your home network while giving you access to your LAN resources like SMB shares and Pi-hole for DNS filtering. This setup is secure, private, and efficient, with minimal performance impact when connected to home Wi-Fi.

---

This guide ensures you avoid common pitfalls, so follow each step carefully and enjoy secure remote access to your home network!
