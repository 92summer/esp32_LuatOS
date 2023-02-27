# esp32_LuatOS
# http获取天气信息在LCD上显示和MQTT灯控程序

| 物料       | 参数                                    |
| ---------- | --------------------------------------- |
| 显示屏     | 1.8寸tftLCD，分辨率128*160，主控st7735s |
| 主控板     | 合宙esp32c3开发板，适配LuatOS           |
| 继电器模块 | 双路5V可选高低电平触发                  |

# v1.1  
新加了一个mqtt客户端用于接收luatos/city消息，更改要显示的城市天气信息  
![Screenrecorder-2023-02-27-13-05-13-952](https://user-images.githubusercontent.com/80613363/221519840-444c480d-fc87-42b1-a8d2-44a83a3bf06f.gif)

