#!/bin/bash
# ----------------------------------------------------
# EC2 UserData: OpenJDK 17 + Maven + Tomcat 9 Setup
# ----------------------------------------------------

set -e

echo "Updating system..."
apt update -y

echo "Installing OpenJDK 17, Maven, and required tools..."
apt install -y \
  openjdk-17-jdk \
  maven \
  wget \
  tar

# ----------------------------------------------------
# Verify installations (logs only)
# ----------------------------------------------------
java -version
mvn -version

# ----------------------------------------------------
# Create tomcat user
# ----------------------------------------------------
echo "Creating tomcat user..."
useradd -r -m -U -d /opt/apache-tomcat-9.0.96 -s /bin/false tomcat || true

# ----------------------------------------------------
# Install Tomcat
# ----------------------------------------------------
echo "Downloading Tomcat 9.0.96..."
cd /tmp
wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.96/bin/apache-tomcat-9.0.96.tar.gz

echo "Extracting Tomcat..."
tar xf apache-tomcat-9.0.96.tar.gz -C /opt/

chown -R tomcat:tomcat /opt/apache-tomcat-9.0.96
chmod +x /opt/apache-tomcat-9.0.96/bin/*.sh

# ----------------------------------------------------
# Create systemd service
# ----------------------------------------------------
echo "Creating Tomcat systemd service..."
cat <<EOF > /etc/systemd/system/tomcat9.service
[Unit]
Description=Apache Tomcat 9
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="CATALINA_HOME=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_BASE=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_PID=/opt/apache-tomcat-9.0.96/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC \
--add-opens java.base/java.lang=ALL-UNNAMED \
--add-opens java.base/java.lang.invoke=ALL-UNNAMED \
--add-opens java.base/java.lang.reflect=ALL-UNNAMED \
--add-opens java.base/java.io=ALL-UNNAMED \
--add-opens java.base/java.security=ALL-UNNAMED \
--add-opens java.base/java.util=ALL-UNNAMED \
--add-opens java.base/java.util.concurrent=ALL-UNNAMED \
--add-opens java.rmi/sun.rmi.transport=ALL-UNNAMED"

ExecStart=/opt/apache-tomcat-9.0.96/bin/startup.sh
ExecStop=/opt/apache-tomcat-9.0.96/bin/shutdown.sh

RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------
# Enable and start Tomcat
# ----------------------------------------------------
echo "Enabling and starting Tomcat..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable tomcat9
systemctl start tomcat9

echo "----------------------------------------------------"
echo "Setup complete:"
echo " - Java 17 installed"
echo " - Maven installed"
echo " - Tomcat running on port 8080"
echo "----------------------------------------------------"
