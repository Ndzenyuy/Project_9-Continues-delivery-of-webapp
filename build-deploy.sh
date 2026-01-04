#!/bin/bash
set -e

echo "Building application..."
mvn clean package -DskipTests

# Stop Tomcat
sudo systemctl stop tomcat9

# Remove BOTH ROOT directory AND ROOT.war
sudo rm -rf /opt/apache-tomcat-9.0.96/webapps/ROOT
sudo rm -f /opt/apache-tomcat-9.0.96/webapps/ROOT.war

# Verify they're gone
sudo ls -la /opt/apache-tomcat-9.0.96/webapps/

# Copy your WAR file
sudo cp target/vprofile-v2.war /opt/apache-tomcat-9.0.96/webapps/ROOT.war

# Verify it's there and correct size (18M)
sudo ls -lh /opt/apache-tomcat-9.0.96/webapps/ROOT.war

# Set ownership
sudo chown tomcat:tomcat /opt/apache-tomcat-9.0.96/webapps/ROOT.war

# Start Tomcat and watch logs
sudo systemctl start tomcat9