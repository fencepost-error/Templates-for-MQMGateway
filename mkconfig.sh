#!/bin/bash
# Build MQMGateway and Home Assistant config files from template files and
# apply it to modmqttd.  Arguments:
#
#	-h = Only generate HA config, not MQTT config.
#	-i = Install MQTT config in MQMGateway.
#	-m = Only generate MQTT config, not HA config.
#	-v = Verbose mode, show each template generation.
#
# To control what goes into the config file, scroll down to the section
# with the comment '# Edit the following'.
#
# If you're not generating your YAML with sed you're just not trying.

CONFIG_FILE_DIRECTORY=""
HEADER_FILE_MQTT="config_header_mqtt.yaml"
HEADER_FILE_HA="config_header_ha.yaml"
HEADER_FILE_DASHBOARD="config_header_dashboard.yaml"
HEADER_FILE_TEMP="config_header_temp.yaml"
OUTPUT_FILE_MQTT="config.yaml"
OUTPUT_FILE_HA="home_assistant.yaml"
OUTPUT_FILE_DASHBOARD="dashboard.yaml"
FIXUP_FILE="fixup.tmp"
TEMP_FILE=_mkconfig.tmp
DO_INSTALL=0
DO_MQTT=0
DO_HA=0
VERBOSE=0

# Process any optional flags before the args.

while getopts "himv" options ; do
	case "${options}" in
		h) DO_HA=1 ;;
		i) DO_INSTALL=1 ;;
		m) DO_MQTT=1 ;;
		v) VERBOSE=1 ;;
		*) echo "Invalid option -${OPTARG}" >&2 ;
		   exit 1 ;;
	esac
done
shift $(( OPTIND - 1 ))

# No explicit selection of MQTT or HA means apply all options.

if [ $DO_MQTT -eq 0 ] && [ $DO_HA -eq 0 ] ; then
	DO_MQTT=1 ;
	DO_HA=1 ;
fi

# Check whether the config files are in a subdirectory.

if [ -d "templates" ] ; then
	CONFIG_FILE_DIRECTORY="templates/"
fi

# Check for common problems in template files.  Using a register value of 0
# is particularly problematic since it gets converted to -1, which makes the
# resulting error message look like it's an error return value from a
# libmodbus function.  Using invisible-to-the-editor tabs is also a problem,
# better to catch this at this stage than later when they're in the config
# file.  Note the use of the awkward double-grep, this is because we need to
# use $'\t' (unquoted) to feed a tab character to grep, which means that we
# can't combine it with the comment-excluder.

for file in "${CONFIG_FILE_DIRECTORY}"*.yamlt ; do
	if [ "$(grep -c '^\s*register:\s*0\b' $file)" -gt 0 ] ; then
		echo "Template $file uses 0-based registers, should be 1-based" >&2 ;
		exit 1 ;
	fi
	if [ "$(grep "^[^#]" $file | grep -c $'\t')" -gt 0 ] ; then
		echo "Template $file contains tab characters, should be spaces" >&2 ;
		exit 1 ;
	fi
	if [ "$(grep -c '^\s*button:' $file)" -gt 0 ] ; then
		echo "Warning: $file contains button: definitions" >&2 ;
		echo "         alongside standard sensors, this will require manual editing of" >&2 ;
		echo "         $OUTPUT_FILE_HA to move them into the button: category and" >&2 ;
		echo "         $OUTPUT_FILE_DASHBOARD to change the type from sensor to button." >&2 ;
	fi
done

# Clean up files from previous runs.

if [ -f ${OUTPUT_FILE_MQTT} ] ; then
	rm ${OUTPUT_FILE_MQTT} ;
fi
if [ -f ${OUTPUT_FILE_HA} ] ; then
	rm ${OUTPUT_FILE_HA} ;
fi
if [ -f ${OUTPUT_FILE_DASHBOARD} ] ; then
	rm ${OUTPUT_FILE_DASHBOARD} ;
fi
if [ -f ${FIXUP_FILE} ] ; then
	rm ${FIXUP_FILE} ;
fi
if [ -f ${TEMP_FILE} ] ; then
	rm ${TEMP_FILE} ;
fi

# Create the header.  This performs DNS lookups on the named devices and
# inserts the corresponding IP addresses into the header for the config
# file

compile_header()
	{
	for DNSNAME in $(grep "^[^#] \+address: [a-z]" ${CONFIG_FILE_DIRECTORY}${HEADER_FILE_MQTT} | sed "s/^[ ]*address: //") ; do

		# Get the IP address of the device.  This isn't very fancy, it just
		# returns the first one found without much checking on the assumption
		# that an embedded modbus gateway isn't going to be multihomed.
		IP_ADDRESS=$(dig +short "$DNSNAME" | head -n1)
		if [ -z "$IP_ADDRESS" ] ; then
			echo "No DNS entry for server $DNSNAME" >&2 ;
			exit 1 ;
		fi

		if [ $VERBOSE -eq 1 ] ; then
			echo "Setting address for ${DNSNAME} to ${IP_ADDRESS}" ;
		fi

		# Swap out the DNS name for the IP address
		sed -i s/"${DNSNAME}"/"${IP_ADDRESS}"/g ${OUTPUT_FILE_MQTT}

	done
	}

# Add information to an output file describing how the current section
# was generated.

add_build_info()
	{
	NAME=$1
	TEMPLATE_FILE=$2
	OUTPUT_FILE=$3

	echo "" >> "${OUTPUT_FILE}"
	echo "    # Sensor group '${NAME}' added from '${TEMPLATE_FILE}' template" >> "${OUTPUT_FILE}"
	}

# Fix up switches and binary sensors by moving them to their own section
# following the sensors.  We use ed for this because, while it's possible to
# do it with sed, the process is pretty messy.  This assumes that the switch
# definitions are delimited with "switch:" at the start and "state_off" at
# the end, and the binary sensors with "binary_sensor:" and
# "payload_not_available"

fix_switches()
	{
	FILE=$1

	# Check whether there are any switches present.
	SWITCH_COUNT=$(grep -c "^  switch:$" "$FILE")
	if [ $SWITCH_COUNT -le 0 ] ; then
		return ;
	fi

	if [ $VERBOSE -eq 1 ] ; then
		echo "Fixing up ${SWITCH_COUNT} entities as switches, not sensors" ;
	fi

	# Generate a list of entities that are switches rather than sensors.
	sed -n "/^  switch:$/{ n; p }" "${OUTPUT_FILE_HA}" | sed 's/    - name: //' > "${FIXUP_FILE}" ;

	# Move each switch: entry down past the sensor: section.
	for i in $(seq 1 $SWITCH_COUNT) ; do
		ed -s "$FILE" << __END__
/^  switch:$/,/^      state_off:.*$/+1m/^homeassistant:$/-
wq
__END__
	done

	# Delete the duplicate switch: lines created by moving each
	# individual switch section to the end of the file.
	sed -i '0,/^  switch:$/!{//d}' "${FILE}"

	# Add explanatory text to the "switch" entry.  This used to be required
	# to explain the need to hand-edit the switch names but is no longer
	# necessary since the next block of code does this automatically.
#	sed -i -e "/^  switch:$/{rtemplates/config_info_switches.yamlt" -e "d}" "${FILE}"

	# Rename each switch from sensor.* to switch.*
	while read LINE ; do
		sed -i "s/sensor.${LINE}/switch.${LINE}/g" "${FILE}" ;
		sed -i "s/sensor.${LINE}/switch.${LINE}/g" "${OUTPUT_FILE_DASHBOARD}" ;
	done < "${FIXUP_FILE}"

	rm "${FIXUP_FILE}"
	}

fix_binary_sensors()
	{
	FILE=$1

	# Check whether there are any binary sensors present.
	BINARY_SENSOR_COUNT=$(grep -c "^  binary_sensor:$" "$FILE")
	if [ $BINARY_SENSOR_COUNT -le 0 ] ; then
		return ;
	fi

	if [ $VERBOSE -eq 1 ] ; then
		echo "Fixing up ${BINARY_SENSOR_COUNT} entities as binary sensors, not sensors" ;
	fi

	# Generate a list of entities that are binary sensors rather than sensors.
	sed -n "/^  binary_sensor:$/{ n; p }" "${OUTPUT_FILE_HA}" | sed 's/    - name: //' > "${FIXUP_FILE}" ;

	# Move each binary_sensor: entry down past the sensor: section.  This has
	# to be done as a two-stage operation since there are multiple instances
	# of payload_not_available: which confuses ed, so we first move to the
	# binary_sensor: line and then select from there to the first
	# payload_not_available: that follows it.  The annoying redirect to
	# /dev/null is necessary because the first command is regarded as us
	# telling ed to say something, which overrides the -s quiet mode.
	for i in $(seq 1 $BINARY_SENSOR_COUNT) ; do
		ed -s "$FILE" > /dev/null << __END__
1,/^  binary_sensor:$/
.,/^      payload_not_available:.*$/+1m/^homeassistant:$/-
wq
__END__
	done

	# Delete the duplicate binary_sensor: lines created by moving each
	# individual switch section to the end of the file.
	sed -i '0,/^  binary_sensor:$/!{//d}' "${FILE}"

	# Rename each switch from sensor.* to binary_sensor.*
	while read LINE ; do
		sed -i "s/sensor.${LINE}/binary_sensor.${LINE}/g" "${FILE}" ;
		sed -i "s/sensor.${LINE}/binary_sensor.${LINE}/g" "${OUTPUT_FILE_DASHBOARD}" ;
	done < "${FIXUP_FILE}"

	rm "${FIXUP_FILE}"
	}

# Create the various YAML files and configs needed by Home Assistant.

compile_template_ha()
	{
	local TEMPLATE_FILE=$(echo $1 | sed 's/:/_/g')
	TOPIC=$2
	NAME=$3
	TEMP_FILE_HA="_ha_temp.yaml"

	if [ $VERBOSE -eq 1 ] ; then
		echo "Creating sensor group ${TOPIC} and dasboard card ${NAME} from ${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_ha.yamlt" ;
	fi

	if [ ! -f "${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_ha".yamlt ] ; then
		echo "Template ${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_ha.yamlt not found" >&2 ;
		exit 1 ;
	fi

	# Generate the sensor config file for HA.
	add_build_info "$NAME" "${TEMPLATE_FILE}" "${OUTPUT_FILE_HA}"
	grep -v "friendly_name:" "${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}"_ha.yamlt | sed '/^[[:space:]]*#/d' | sed s/XXXX/"${TOPIC}"/g | sed s/YYYY/"${NAME}"/g > "${TEMP_FILE_HA}"
	cat "${TEMP_FILE_HA}" >> "${OUTPUT_FILE_HA}"

	# Generate the additional sensor friendly-name section needed for the
	# sensor config file.
	echo "" >> "${TEMP_FILE}"
	cat "${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}"_ha.yamlt | sed '/^[[:space:]]*#/d' | sed s/XXXX/"${TOPIC}"/g | sed -E s/"^(.*- name:) (.*)$"/"    sensor.\2:"/g | grep --no-group-separator "sensor\." -A 1 >> "${TEMP_FILE}"

	# Generate the dashboard config file for HA.
	printf "\n      - type: entities\n        title: %s\n        entities:\n" "$NAME" >> "${OUTPUT_FILE_DASHBOARD}"
	grep "name:" "${TEMP_FILE_HA}" | sed '/^#/d' | sed s/"    - name: "/"          - entity: sensor."/g >> "${OUTPUT_FILE_DASHBOARD}"

	# Clean up
	rm "${TEMP_FILE_HA}"
	}

# Create the YAML file needed by MQMGateway.

compile_template_mqtt()
	{
	local TEMPLATE_FILE=$(echo $1 | sed 's/:.*//g')
	TOPIC=$2
	NAME=$3
	NETWORK=$4
	ADDRESS=$5

	if [ $VERBOSE -eq 1 ] ; then
		echo "Creating topic ${TOPIC} from ${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_mqtt.yamlt" ;
	fi

	if [ ! -f "${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_mqtt".yamlt ] ; then
		echo "Template ${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}_mqtt.yamlt not found" >&2 ;
		exit 1 ;
	fi

	add_build_info "$NAME" "${TEMPLATE_FILE}" "${OUTPUT_FILE_MQTT}"
	cat "${CONFIG_FILE_DIRECTORY}${TEMPLATE_FILE}"_mqtt.yamlt | sed '/^#/d' | sed s/XXXX/"${TOPIC}"/g | sed s/YYYY/"${NETWORK}"/g | sed s/ZZZZ/"${ADDRESS}"/g >> "${OUTPUT_FILE_MQTT}"
	}

compile_template()
	{
	TEMPLATE_FILE=$1
	TOPIC=$2
	NAME=$3
	NETWORK=$4
	ADDRESS=$5

	if echo "${TOPIC}" | grep -q "[A-Z]" ; then
		echo "Topic '${TOPIC}' must be given as lowercase only for HA use" >&2 ;
		exit 1 ;
	fi

	if [ $DO_MQTT -eq 1 ] ; then
		compile_template_mqtt "$TEMPLATE_FILE" "$TOPIC" "$NAME" "$NETWORK" "$ADDRESS" ;
	fi

	if [ $DO_HA -eq 1 ] ; then
		compile_template_ha "$TEMPLATE_FILE" "$TOPIC" "$NAME" ;
	fi
	}

# Create the headers for the config files.

cp ${CONFIG_FILE_DIRECTORY}${HEADER_FILE_MQTT} ${OUTPUT_FILE_MQTT}
cp ${CONFIG_FILE_DIRECTORY}${HEADER_FILE_HA} ${OUTPUT_FILE_HA}
cp ${CONFIG_FILE_DIRECTORY}${HEADER_FILE_DASHBOARD} "${OUTPUT_FILE_DASHBOARD}"
cp ${CONFIG_FILE_DIRECTORY}${HEADER_FILE_TEMP} "${TEMP_FILE}"

# "Compile" the input files into the config files.  compile_header arguments
# are the FQDN names of each device.  compile_template arguments are, with
# examples:
#
#	Template file	MQTT topic	HA friendly name	Network		Modbus address
#	temp_humid		annex		"Annex"				annex		10
#
# The 'Template file' can optionally include a colon followed by the HA
# subtype if a single template is being used for multiple entities in HA.
# For example if a template 'sensor' is being used for indoors sensors and
# outdoors sensors the two would be 'sensor:indoors' and 'sensor:outdoors',
# with the generated MQTT using sensor.yamlt and the generated HA using
# sensor_indoors.yamlt and sensor_outdoors.yamlt.  This is because MQTT
# distinguishes between the two using the MQTT topic while HA uses a text
# label, requiring different labels in the different yamlt files for HA.
#
# The 'Network' value is the network name given in config_header_mqtt.yaml,
# which is mapped to an IP address by the config script for use by
# MQMGateway.  This is just a label, for example the network name "annex"
# would be mapped to device "waveshare.annex.lan" in the YAML config.
#
# Note that the topic_name must be all lowercase since HA mangles identifiers
# into lowercase, leading to mismatches if any of the config files refer
# to them in non-lowercase terms.

#########################################################################
# Edit the following section to control what goes into the config files.
#########################################################################

compile_header

compile_template eastron grid "Grid" switchboard 10
compile_template eastron non_backup "Non-backup" switchboard 11
compile_template eastron backup "Backup" switchboard 12
compile_template eastron downstairs "Downstairs" switchboard 13
compile_template eastron hwc "HWC" switchboard 14
compile_template eastron kitchen "Kitchen" switchboard 15

compile_template cdebyte_io_2240 io_switchboard "Water" switchboard 20

compile_template temp_humid network "Network cupboard" network 10
compile_template cdebyte_io_4040:network io_network "Network cupboard" network 20

compile_template temp_humid annex "Annex" annex 10
compile_template temp_humid under_annex "Under Annex" annex 11
compile_template temp_humid deck_left "Deck left" annex 12
compile_template co2 deck_right "Deck right" annex 13
compile_template pm25 environment "Environment" annex 14

compile_template cdebyte_io_4040:annex io_annex "Annex" annex 20
compile_template water_level water_tank "Water tank" annex 30

compile_template mia hvac "HVAC" attic 1

compile_template temp_humid attic_left "Attic Left" attic 10
compile_template temp_humid attic_right "Attic Right" attic 11
compile_template temp roof "Roof" attic 12
compile_template temp_18b20 hwc_temp "Water" attic 20

#########################################################################
# End of user-defined configuration settings
#########################################################################

# If we're generating the HA output, append the friendly-name info to the
# config file and sort out non-sensor entities that need to go into a
# specific location in the config file.

if [ $DO_HA -eq 1 ] ; then
	# Add the friendly names to the config file.
	echo "" >> "${OUTPUT_FILE_HA}" ;
	cat "${TEMP_FILE}" >> "${OUTPUT_FILE_HA}" ;
	rm "${TEMP_FILE}" ;

	# Move entities that are switches and binary sensors down into the
	# correct location before the friendly names we just added above.
	fix_switches "${OUTPUT_FILE_HA}" ;
	fix_binary_sensors "${OUTPUT_FILE_HA}" ;

	# Check for duplicate entries in the dashboard file.
	if [ "$(grep 'title:' ${OUTPUT_FILE_DASHBOARD} | sort | uniq -D | wc -l)" -gt 0 ] ; then
		echo "Warning: ${OUTPUT_FILE_DASHBOARD} contains duplicate cards, will need manual fixup:" ;
		echo "$(grep 'title:' ${OUTPUT_FILE_DASHBOARD} | sort | uniq -D )" ;
	fi
fi

# If we're not installing the config in MQMGateway, we're done

if [ $DO_INSTALL -ne 1 ] ; then
	exit 0 ;
fi

# Install the new config file and restart modmqttd.  We need to pause
# for a second after the restart to allow modmqttd time to initialise.

if [ $VERBOSE -eq 1 ] ; then
	echo "Installing MQTT configuration in MQMGateway" ;
fi

sudo cp config.yaml /etc/modmqttd/config.yaml
sudo systemctl restart modmqttd
sleep 1
sudo systemctl status modmqttd | less
