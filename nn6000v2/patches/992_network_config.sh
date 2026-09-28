#!/bin/sh
# ============================================================
# 网络初始化配置脚本
# 首次启动时自动配置 WiFi 和 PPPoE 宽带
#
# 执行顺序很重要：/etc/init.d/boot 里是
#     [ -f /etc/board.json ] && /sbin/wifi config   # 生成 /etc/config/wireless
#     uci_apply_defaults                            # 才跑 /etc/uci-defaults/*
# 而 wifi 生成器（wifi-scripts/files/lib/wifi/mac80211.uc）写出的默认值是
#     ssid=OWRT  encryption=psk2+ccmp  key=12345678  disabled=0
# 所以本脚本是在"已经生成好的配置"上覆盖。
# 旧版本用"加密方式不是 none 就跳过"来判断，在 ucode 生成器下永远命中跳过，
# 导致 SSID/密码从来没生效过（一直显示 OWRT/12345678）。
# ============================================================

# ==================== WiFi 配置 ====================
# 5G
WIFI_5G_SSID="NN6000_5G"
WIFI_5G_KEY="12345679"

# 2.4G
WIFI_2G_SSID="NN6000"
WIFI_2G_KEY="12345679"

# WPA2-PSK
WIFI_ENCRYPTION="psk2+ccmp"

# ==================== PPPoE 宽带配置 ====================
# 填写你的宽带账号密码，使用 "-" 表示跳过配置
# 在 GitHub Actions 构建时可以通过输入参数自动替换此处的值
PPPOE_USERNAME="-"
PPPOE_PASSWORD="-"
# ============================================================

board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null)

# 出厂默认 SSID：命中说明用户还没改过，可以套用我们的默认值；
# 已经是别的名字说明用户自己改过，升级时保留他的设置。
is_factory_ssid() {
	case "$1" in
		""|OWRT|OpenWrt|ImmortalWrt) return 0 ;;
		*) return 1 ;;
	esac
}

# 按 radio 的 band 选项匹配（不假定 radio0 是 5G、radio1 是 2.4G，
# 生成器给 radio 编号的顺序取决于 board.json 里 phy 的枚举顺序）
configure_wifi() {
	local dev="$1"
	local iface="default_${dev}"
	local band ssid key

	band=$(uci -q get "wireless.${dev}.band")
	case "$band" in
		5g) ssid="$WIFI_5G_SSID"; key="$WIFI_5G_KEY" ;;
		2g) ssid="$WIFI_2G_SSID"; key="$WIFI_2G_KEY" ;;
		*) return 0 ;;
	esac

	is_factory_ssid "$(uci -q get "wireless.${iface}.ssid")" || return 0

	uci -q batch <<EOF
set wireless.${iface}.ssid="${ssid}"
set wireless.${iface}.encryption="${WIFI_ENCRYPTION}"
set wireless.${iface}.key="${key}"
set wireless.${iface}.disabled='0'
set wireless.${dev}.disabled='0'
set wireless.${iface}.ieee80211k='1'
set wireless.${iface}.bss_transition='1'
EOF
}

link_nn6000v2_wifi_cfg() {
	local dev
	for dev in $(uci -q show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.]*\)=wifi-device$/\1/p'); do
		configure_wifi "$dev"
	done
}

setup_pppoe() {
	if [ "$PPPOE_USERNAME" = "-" ] || [ "$PPPOE_PASSWORD" = "-" ]; then
		echo "PPPoE: 使用占位符，跳过配置"
		return 0
	fi

	if [ ! -f /etc/config/network ]; then
		echo "PPPoE: network 配置文件不存在"
		return 1
	fi

	local wan_proto=$(uci -q get network.wan.proto)
	local wan_username=$(uci -q get network.wan.username)
	local wan_password=$(uci -q get network.wan.password)

	if [ "$wan_proto" = "pppoe" ] && [ "$wan_username" != "-" ] && [ "$wan_password" != "-" ]; then
		echo "PPPoE: 已配置有效账号，跳过"
		return 0
	fi

	uci -q batch <<EOF
set network.wan.proto='pppoe'
set network.wan.username='${PPPOE_USERNAME}'
set network.wan.password='${PPPOE_PASSWORD}'
set network.wan.keepalive='5 3'
set network.wan.demand='0'
EOF

	uci commit network
	echo "PPPoE: 配置完成 - 用户名: ${PPPOE_USERNAME}"
}

need_restart=0

case "$${board_name}" in
link,nn6000-v2)
	link_nn6000v2_wifi_cfg
	uci commit wireless
	need_restart=1
	;;
esac

setup_pppoe

if [ "$need_restart" -eq 1 ]; then
	/etc/init.d/network restart
	# 有 WiFi 固件：确保首次启动就把无线拉起来（无 WiFi 驱动时静默跳过）
	wifi up >/dev/null 2>&1 || true
fi
