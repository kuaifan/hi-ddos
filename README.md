## 运行脚本
```
./cmd
```

## 输入a，安装cdn节点程序
![image](https://user-images.githubusercontent.com/85656971/169776758-f79c17f7-18b4-4b33-a538-18268b656031.png)


## 部署完成后，需要修改webhook地址
> 文件：hi-ddos/nodes/init.sh
```
WEBHOOK_URL="http://127.0.0.1:85/hooks/ipreport"

修改为主控的webhook地址
```
