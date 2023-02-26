
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpweatherLCD_and_mqttControl"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

-- UI带屏的项目一般不需要低功耗了吧, 设置到最高性能
if mcu then
    pm.request(pm.NONE)
end

local rtos_bsp = rtos.bsp()

-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,6,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,18
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin()

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,2000000,spi.MSB,1,0)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- direction：lcd屏幕方向 0:0° 1:180° 2:270° 3:90°
lcd.init("st7735s",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)

--如果显示颜色相反，请解开下面一行的注释，关闭反色
-- lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

-- 不在上述内置驱动的, 看demo/lcd_custom


-- @param city 城市拼音
local city = "wuhan"

local device_id     = "esp32"    --改为你自己的设备id
local device_secret = "132"    --改为你自己的设备密钥
local mqttc = nil
local light_status = "on"
local last_status = "off"  --避免每次赋值io产生高频振荡信号
local led_status = 1 --1为初始化状态：双闪 --2未连接broker:常亮 --3已连接并开始收发:单闪
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if rtos.bsp():startsWith("ESP32") then
        -- wifi 联网, ESP32系列均支持
        local ssid = "换成你的WiFi名"
        local password = "换成你的密码"
        -- log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif rtos.bsp() == "AIR105" then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif rtos.bsp() == "EC618" then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    end

    local client_id,user_name,password = iotauth.iotda(device_id,device_secret)
    log.info("iotda",client_id,user_name,password)

    mqttc = mqtt.create(nil,"192.168.1.103", 1883) --换成你的mqtt服务器地址

    mqttc:auth(client_id,user_name,password)
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event:", event, mqtt_client, data, payload)
        if event == "conack" then
            led_status = 1
            sys.publish("mqtt_conack")
            mqtt_client:subscribe("test/sw")
        elseif event == "recv" then
            log.info("mqtt", "topic:", data, "payload:", payload)
            if payload == "Lights On!" then
                light_status = "on"
            elseif payload == "Lights Off!" then
                light_status = "off"
            else
                light_status = nil
            end
        elseif event == "sent" then
            led_status = 3
            gpio.setup(13,gpio.HIGH)
            gpio.setup(12,gpio.HIGH)
            log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    while true do
        if not mqttc:ready() then
            led_status = 2
        end
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)


--发布灯状态
sys.taskInit(function()
	local topic = "luatos/light_status"
	local payload = nil
	local qos = 1
    local result, data = sys.waitUntil("IP_READY")
    while true do --5秒发一次灯的状态
        sys.wait(5000)
        if light_status == "on" then
            payload = "Lights On!"
        elseif light_status == "off" then
            payload = "Lights Off!"
        else
            payload = "Error..."
        end
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(topic, payload, qos)
        end
        log.info("mqtt", "sent", "topic:", topic, "text:",payload)
    end
end)

--继电器控制
sys.taskInit(function()
    local pin_jidianqi = 8
    --pin6继电器一路,高电平接通
    gpio.setup(pin_jidianqi,gpio.LOW)
    while true do
        sys.wait(5)
        if light_status == "on" then
            if last_status == "on" then

            elseif last_status == "off" then
                gpio.setup(pin_jidianqi,gpio.HIGH)
            end
            last_status = "on"
        elseif light_status == "off" then
            if last_status == "off" then

            elseif last_status == "on" then
                gpio.setup(pin_jidianqi,gpio.LOW)
            end
            last_status = "off"
        end
    end
end)

--点灯
sys.taskInit(function()
    while true do
        if led_status == 1 then
            gpio.setup(12,gpio.HIGH)
            gpio.setup(13,gpio.HIGH)
            sys.wait(100)
            gpio.setup(12,gpio.LOW)
            gpio.setup(13,gpio.LOW)
            sys.wait(100)
        elseif led_status == 2 then
            gpio.setup(12,gpio.HIGH)
            gpio.setup(13,gpio.HIGH)
            sys.wait(100)
        elseif led_status == 3 then
            gpio.setup(13,gpio.HIGH)
            sys.wait(700)
            gpio.setup(13,gpio.LOW)
            sys.wait(500)
        end
    end
end)







--心知天气api返回数据解析函数
-- @param tab 收到的解码为table格式的变量
-- @param info 要查询的信息：'city'--某个城市;'weather'--天气状况;'NOWtemperature'--当前温度摄氏度
--                          'today'--今日天气;'tomorrow'--明日天气
local function seniverse_FindData( tab , info )
    if info == "city" then
        return tab["results"][1]["location"]["name"]
    elseif info == "weather" then
        return tab["results"][1]["now"]["text"]
    elseif info == "NOWtemperature" then
        return tab["results"][1]["now"]["temperature"]
    elseif info == "today" then
        return tab["results"][1]["daily"][1]["date"], tab["results"][1]["daily"][1]["text_day"],
        tab["results"][1]["daily"][1]["high"],tab["results"][1]["daily"][1]["low"],
        tab["results"][1]["daily"][1]["humidity"]
    elseif info == "tomorrow" then
        return tab["results"][1]["daily"][2]["date"], tab["results"][1]["daily"][2]["text_day"],
        tab["results"][1]["daily"][2]["high"],tab["results"][1]["daily"][2]["low"],
        tab["results"][1]["daily"][2]["humidity"]
    else
        return nil
    end
end

sys.taskInit(function()
    sys.wait(10000)
    while 1 do
        --心知天气api
        local key = "换成你的私钥"

        --获取实时天气
        local url = "https://api.seniverse.com/v3/weather/now.json?key=" .. key .. "&location=".. city .."&language=zh-Hans&unit=c"
        -- log.info("URL", url)
        local code, headers, body = http.request("GET", url).wait()
        --code 200为请求成功，返回的body为json格式
        -- log.info("http.get", code, headers, body)
        if code == 200 then
            log.info("http.get", "实时天气请求成功")
        else
            log.info("http.get", "ErrCode ", code)
        end
        --解码为table格式
        local tab = json.decode(body)
        log.info("city",seniverse_FindData( tab , 'city' ))
        log.info("weather condition",seniverse_FindData( tab , 'weather' ))
        log.info("temperature",seniverse_FindData( tab , 'NOWtemperature' ).."℃")
        lcd.clear()
        lcd.setFont(lcd.font_opposansm12_chinese)

        lcd.drawStr(20,140,seniverse_FindData( tab , 'weather' ), 0x50ff)
        lcd.setFont(lcd.font_unifont_t_symbols)
        lcd.drawStr(0,120,"---NOW")
        lcd.drawStr(80,140, seniverse_FindData( tab , 'NOWtemperature' )..'°C', 0x50ff)

        -- log.info("sys", rtos.meminfo("sys"))
        -- log.info("lua", rtos.meminfo("lua"))
        sys.wait(300000) --等待5分钟
        lcd.clear()
    end
end)


sys.taskInit(function()
    sys.wait(12000)
    while 1 do
        --心知天气api
        local key = "STxpmSa4oTixXmbym"

        --获取天气预报（今明）
        local url = "https://api.seniverse.com/v3/weather/daily.json?key=" .. key .. "&location=".. city .."&language=zh-Hans&unit=c&start=0&days=5"
        -- log.info("URL", url)
        local code, headers, body = http.request("GET", url).wait()
        --code 200为请求成功，返回的body为json格式
        -- log.info("http.get", code, headers, body)
        if code == 200 then
            log.info("http.get", "天气预报请求成功")
        else
            log.info("http.get", "ErrCode ", code)
        end
        --解码为table格式
        local tab = json.decode(body)
        local date, w, high, low, humidity = seniverse_FindData( tab , "today" )
        log.info("today weather", date, seniverse_FindData( tab , "city" ), w, low..'~'..high..'℃ ', "相对湿度:"..humidity..'%')
        -- lcd.setFont(lcd.font_opposansm12_chinese)
        -- lcd.drawStr(15,20, date, 0x10ff)
        -- lcd.drawStr(75,40, w, 0x10ff)
        date, w, high, low, humidity = seniverse_FindData( tab , "tomorrow" )
        log.info("today weather", date, seniverse_FindData( tab , "city" ), w, low..'~'..high..'℃ ', "相对湿度:"..humidity..'%')
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.drawStr(0,20,"--明日天气")
        lcd.drawStr(15,40, date, 0x10ff)
        lcd.drawStr(20,60, seniverse_FindData( tab , 'city' ), 0xff00)
        lcd.drawStr(75,60, w, 0x10ff)
        lcd.drawStr(15,80, "温度 :", 0x10ff)
        lcd.drawStr(10,100, "相对湿度: "..humidity..'%', 0x10ff)
        lcd.setFont(lcd.font_unifont_t_symbols)
        lcd.drawStr(60,80, low..'~'..high.."°C", 0x10ff)
        sys.wait(300000) --等待5分钟
    end
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
