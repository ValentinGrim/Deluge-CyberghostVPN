#!/bin/bash

	config_ini=/home/root/.cyberghost/config.ini #CyberGhost Auth token
	startup () {
		echo "deluge-cyberghostvpn - Docker Edition"
		echo "----------------------------------------------------------------------"
		echo "	Originally created By: Tyler McPhee"
		echo "		GitHub: https://github.com/tmcphee/cyberghostvpn"
		echo "		DockerHub: https://hub.docker.com/r/tmcphee/cyberghostvpn"
		echo "	"
		echo "	Forked By : ValentinGrim"
		echo "		Adding deluged and deluged-web"
		echo "		GitHub: https://github.com/ValentinGrim/deluge-cyberghostvpn"
		echo "	Ubuntu:${linux_version} | CyberGhost:${cyberghost_version} | ${script_version}"
		echo "----------------------------------------------------------------------"

		echo "**************User Defined Variables**************"

		if [ -n "$ACC" ]; then
			echo "	ACC: [PASSED - NOT SHOWN]"
		fi
		if [ -n "$PASS" ]; then
			echo "	PASS: [PASSED - NOT SHOWN]"
		fi

		if [ -n "$COUNTRY" ]; then
			echo "	COUNTRY: ${COUNTRY}"
		fi
		if [ -n "$NETWORK" ]; then
			echo "	NETWORK: ${NETWORK}"
		fi
		if [ -n "$WHITELISTPORTS" ]; then
			echo "	WHITELISTPORTS: ${WHITELISTPORTS}"
		fi
		if [ -n "$ARGS" ]; then
			echo "	ARGS: ${ARGS}"
		fi
		if [ -n "$NAMESERVER" ]; then
			echo "	NAMESERVER: ${NAMESERVER}"
		fi
		if [ -n "$PROTOCOL" ]; then
			echo "	PROTOCOL: ${PROTOCOL}"
		fi

		if [ -n "$DELUGED_PORT" ]; then
			echo "	DELUGED PORT: ${DELUGED_PORT}"
		fi
		if [ -n "$DELUGEWEB_PORT" ]; then
			echo "	DELUGE WEB PORT: ${$DELUGEWEB_PORT}"
		fi

		echo "**************************************************"

	}

	ip_stats () {
		str="$(cat /etc/resolv.conf)"
		value=${str#* }

		echo "************CyberGhost Connection Info************"
		echo "	IP: ""$(curl -s https://ipinfo.io/ip -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	CITY: ""$(curl -s https://ipinfo.io/city -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	REGION: ""$(curl -s https://ipinfo.io/region -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	COUNTRY: ""$(curl -s https://ipinfo.io/country -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	DNS: ${value}"
		echo "**************************************************"
	}

	#Originated from Run.sh. Migrated for speed improvements
	cyberghost_start () {
		#Check for CyberGhost Auth file
		if [ -f "$config_ini" ]; then

			# Check if country is set. Default to US
			if ! [ -n "$COUNTRY" ]; then
				echo "Country variable not set. Defaulting to US"
				export COUNTRY="US"
			fi

			# Check if protocol is set. Default WireGuard
			if ! [ -n "$PROTOCOL" ]; then
				export PROTOCOL="wireguard"
			fi

			#Launch and connect to CyberGhost VPN
			sudo cyberghostvpn --torrent --connect --country-code "$COUNTRY" --"$PROTOCOL" "$ARGS"

			# Add CyberGhost nameserver to resolv for DNS
			# Add Nameserver via env variable $NAMESERVER
			if [ -n "$NAMESERVER" ]; then
				echo 'nameserver ' "$NAMESERVER" > /etc/resolv.conf
			else
				# SMART DNS
				# This will switch baised on country selected
				# https://support.cyberghostvpn.com/hc/en-us/articles/360012002360
				case "$COUNTRY" in
					"NL") echo 'nameserver 75.2.43.210' > /etc/resolv.conf
					;;
					"GB") echo 'nameserver 75.2.79.213' > /etc/resolv.conf
					;;
					"JP") echo 'nameserver 76.223.64.81' > /etc/resolv.conf
					;;
					"DE") echo 'nameserver 13.248.182.241' > /etc/resolv.conf
					;;
					"US") echo 'nameserver 99.83.181.72' > /etc/resolv.conf
					;;
					*) echo 'nameserver 1.1.1.1' > /etc/resolv.conf
					;;
			esac
			fi
		fi
		ip_stats
	}

	#Check if the site is reachable
	check_up() {
		ping -c1 "1.1.1.1" > /dev/null 2>&1 #Ping CloudFlare
		if [ $? -eq 0 ]; then
			return 0
		fi
		return 1
	}

	#Setup and start deluged and deluge-web
	deluge_start() {
		if [ ! -n "$DELUGED_PORT" ]; then
			export DELUGED_PORT=58846
		fi

		if [ ! -n "$DELUGEWEB_PORT" ]; then
			export DELUGEWEB_PORT=8112
		fi

		if [ ! -d  /var/log/deluge ]; then
			sudo mkdir -p /config/log/deluge
			sudo chmod -R 755 /config/log/deluge
		fi

		sudo chown -R root:root /config/
		sudo chmod -R 755 /config/

		echo "Start deluged and deluge-web..."
		sudo deluged -p $DELUGED_PORT -c /config/ -l /config/log/daemon.log -L warning
		deluge-web -p $DELUGEWEB_PORT -c /config/ -l /config/log/web.log -L warning
		echo "Started"
	}

	if ! [ -n "$FIREWALL" ]; then
		export FIREWALL="True"
	fi

	startup

	#Check if CyberGhost CLI is installed. If not install it
	FILE=/usr/local/cyberghost/uninstall.sh
	if [ ! -f "$FILE" ]; then
		echo "CyberGhost CLI not installed. Installing..."
		bash /install.sh
		echo "Installed"
	fi

	#Run Firewall if Enabled. Default Enabled
	sysctl -w net.ipv6.conf.all.disable_ipv6=1 #Disable IPV6
	sysctl -w net.ipv6.conf.default.disable_ipv6=1
	sysctl -w net.ipv6.conf.lo.disable_ipv6=1
	sysctl -w net.ipv6.conf.eth0.disable_ipv6=1
	sysctl -w net.ipv4.ip_forward=1

	#Login to account if config not exist
	if [ ! -f "$config_ini" ]; then
		echo "Logging into CyberGhost..."

		#Check for CyberGhost Credentials and Login
		if [ -n "$ACC" ] && [ -n "$PASS" ]; then
			expect /auth.sh
		else
			echo "[E1] Can't Login. User didn't provide login credentials. Set the ACC and PASS ENV variables and try again."
			exit
		fi
	else
		#Verify the config.ini has successfully created the Account and assigned a Device
		echo "Verifying Login Auth..."
		if ! grep -q '[Device]' $config_ini; then
			echo "Failed"
			rm "$config_ini"
			echo "Logging into CyberGhost..."
			expect /auth.sh
		else
			echo "Passed"
		fi
	fi

	if [ -n "${NETWORK}" ]; then
		echo "Adding network route..."
		export LOCAL_GATEWAY=$(ip r | awk '/^def/{print $3}') # Get local Gateway
		ip route add "$NETWORK" via "$LOCAL_GATEWAY" dev eth0 #Enable access to local lan
		echo "$NETWORK" "routed to" "$LOCAL_GATEWAY" "on eth0"
	fi

	#WIREGUARD START AND WATCH
	cyberghost_start
	t_hr="$(date -u --date="+5 minutes" +%H)" #Next time to check internet is reachable
	t_min="$(date -u --date="+5 minutes" +%M)"

	deluge_start
	while true #Watch if Connection is lost then reconnect
	do
		sleep 30
		if [[ $(sudo cyberghostvpn --status | grep 'No VPN connections found.' | wc -l) = "1" ]]; then
			echo '[E2] VPN Connection Lost - Attempting to reconnect....'
			cyberghost_start
		fi

		#Every 30 Minutes ping CloudFlare to check internet reachability
		if [ "$(date +%H)" = "$t_hr" ] && [ "$(date +%M)" = "$t_min" ]; then
			if ! check_up; then
				echo '[E3] Internet not reachable - Restarting VPN...'
				sudo cyberghostvpn --stop
				cyberghost_start
				t_hr="$(date -u --date="+5 minutes" +%H)" #Next time to check internet is reachable
				t_min="$(date -u --date="+5 minutes" +%M)"
			fi
		fi
	done

	echo '[FATAL ERROR] - $?'


#ERROR CODES
#E1 Can't Login to CyberGhost - Credentials not provided
#E2 VPN Connection Lost
#E3 Internet Connection Lost
