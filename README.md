# Templates-for-MQMGateway
Script compiler and device templates for MQMGateway and Home Assistant

This is a script compiler and a set of device templates for @BlackZork's
excellent Modbus-to-MQTT [MQMGateway](https://github.com/BlackZork/mqmgateway/)
and from there to Home Assistant.  It makes it easier to work with sets of
Modbus devices, which would otherwise require hand-editing a long YAML config
file.  In particular it:

* Applies a single template file to as many devices as you specify.
* Translates device DNS names to their IP addresses.
* Performs checks for common errors in config files.
* Generates the required config.yaml and applies it to modmqttd.
* Generates the YAML required for use with Home Assistant.
* Generates corresponding JSON for use in Home Assistant dashboards.

This means that the entire process of creating the YAML config file and
applying it to modmqttd requires only a single command, and the next step to
Home Assistant just requires adding the YAML to the appropriate HA config file
and the corresponding JSON to the desktop you want to display the sensors on.

# License

This software is licensed under the
[AGPL-3.0 license](https://www.gnu.org/licenses/agpl-3.0.html) to match
MQMGateway.

# Supported Devices

YAML templates for the following devices are currently provided:

- CDEbyte digital/analog I/O devices: cdebyte_io_XXX.yamlt. 
- Eastron SDM 2x0 power meters: eastron_XXX.yamlt.
- Generic CO2 sensors, e.g. ComWinTop: co2_XXX.yamlt.
- Generic PM2.5/PM10 sensors, e.g. ComWinTop: pm25_XXX.yamlt.
- Generic pressure-based water level sensors, e.g. Seeed Studio, QuiDian: water_level_XXX.yamlt.
- Generic temperature/humidity sensors, e.g. ComWinTop: temp_humid_XXX.yamlt.
- MIA HVAC systems: mia_XXX.yamlt.
- Modbus gateway boards for DS18B20 temperature sensors, e.g. eletechsup.
- Waveshare I/O modules: waveshare_io_XXX.yamlt.
- Wayjun pulse counter modules: pulse_count_XXX.yamlt.

There are two subtypes, the `XXX_mqtt.yamlt` files are YAML templates for
MQMGateway, the `XXX_ha.yamlt` files are YAML templates for Home Assistant and
`XXX_ha.json` are the corresponding JSON files for Home Assistant dashboards.
All contributions for further devices are welcome.

# Usage

Everything is controlled by a script `mkconfig.sh` which controls what
templates are used in building the config file and what goes into them.  The
control section starts at the comment `# Edit the following section`.  There
are two commands in there, `compile_header` and `compile_template`.

`compile_header` takes `config_header_XXX.yaml` and generates the start of the
YAML config file.  Specifically, it takes a list of DNS names in
`config_header_mqtt.yaml` inserts the corresponding IP addresses into the
config file.  The `compile_header` directive takes no arguments and just tells
the script compiler to generate the required headers that begin each YAML
config file:

```
compile_header 
```

`compile_template` takes the given template file, inserts the given MQTT
topic, network, and Modbus address (for MQMGatway) or MQTT topic and sensor
name (for Home Assistant) and adds it to the MQMGatway or Home Assistant
config file.  A typical `compile_template` command would be:

```
compile_template temp_humid front_door outdoors 10
```

This takes the template `temp_humid_mqtt.yamlt`, sets the MQTT topic to
`front_door`, the network to `outdoors`, and the Modbus address to 10, and
adds it to `config.yaml`.  It then takes the template `temp_humid_ha.yamlt`,
sets the Home Assistant sensor names to `front_door_XXX`, and adds it to
`homeassistant.yaml`.

The advantage of using templates is that you can very easily set up entire
Modbus device networks for both MQMGatway and Home Assistant with only a few
lines of config.  For example if you have three outdoors temperature/humidity
sensors you can create the config file with:

```
compile_template temp_humid front_door outdoors 10
compile_template temp_humid back_door outdoors 11
compile_template temp_humid shed outdoors 12
```

If run with the `-i` install argument `mkconfig` will apply the new
configuration to modmqttd once it's generated.  To only generate the HA config
files, use `-h`.  To only generate the MQMGateway files, use `-m`.

Suggestions for updates to the documentation to cover unclear portions are
welcome, having worked with the code it's not always clear which bits need the
most explanation.

# Template files

A template file is a standard YAML config as used by MQMGateway and Home
Assistant.  There are three special placeholders for MQMGateway templates:

- XXXX in the template is replaced with the MQTT topic name.
- YYYY in the template is replaced with the Modbus network name.
- ZZZZ in the template is replaced with the Modbus device address.

There are two special placeholders for Home Assistant templates:

- XXXX in the template is replaced with the MQTT topic name.
- YYYY in the template is replaced with the sensor group name.

To see an example, look at any of the `.yamlt` template files.  The
`XXX_mqtt.yamlt` files are for MQMGateway, the `XXX_ha.yamlt` files are for
Home Assistant.
