
#!/bin/bash

# 将服务单元复制到 systemd 目录
sudo cp ../apiok.service /etc/systemd/system/
sudo systemctl daemon-reload

# 启动并启用服务
sudo systemctl start apiok
sudo systemctl enable apiok

echo "apiok has been installed and started as a system service."
