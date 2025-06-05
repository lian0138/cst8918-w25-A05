#!/bin/bash
sudo apt update && apt upgrade -y
sudo apt install -y apache2
sudo systemctl enable apache2
sudo systemctl start apache2

sudo echo "Hello World" > /var/www/html/index.html
sudo systemctl restart apache2