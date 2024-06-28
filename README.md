# Templates-for-MQMGateway
Script compiler and device templates for MQMGateway

This is a script compiler and a set of device templates for @BlackZork's
excellent Modbus-to-MQTT [MQMGateway](https://github.com/BlackZork/mqmgateway/).
It makes it easier to work with sets of Modbus devices, which would otherwise
require hand-editing a long YAML config file.  In particular it:

* Applies a single template file to as many devices as you specify.
* Translates device DNS names to their IP addresses.
* Performs checks for common errors in config files.
* Generates the required config.yaml and applies it to modmqttd.
* (Work in progress: Generate matching YAML config files for Home Assistant).

This means the entire process of creating the YAML config file and applying it
to modmqttd requires only a single command.

# License

This software is licensed under the
[AGPL-3.0 license](https://www.gnu.org/licenses/agpl-3.0.html) to match
MQMGateway.

# Supported Devices

YAML templates for the following devices are currently provided:

- Eastron SDM 2x0 power meters: eastron.yamlt.
- Generic Aliexpress temperature/humidity sensors, e.g. ComWinTop: temp_humid.yamlt.
- Generic pressure-based water level sensors, e.g. Seeed Studio, QuiDian: water_level.yamlt.
- Waveshare I/O modules: waveshare_io.yamlt.
- Wayjun pulse counter modules: pulse_count.yamlt.

All contributions for further devices are welcome.

# Usage

Everything is controlled by a script `mkconfig.sh` which controls what
templates are used in building the config file and what goes into them.  The
control section starts at the comment `# Edit the following section`.  There
are two commands in there, `compile_header` and `compile_template`.

`compile_header` takes `config_header.yamlt` and generates the start of the
`config.yaml` file.  Specifically, it takes a list of DNS names and inserts
the corresponding IP addresses into the config file.  A typical
`compile_header` command would be:

```
compile_header outdoors.modbus.lan indoors.modbus.lan basement.modbus.lan
```

This inserts the IP addresses for `outdoors.modbus.lan` and the other two DNS
names into the config file.

`compile_template` takes the given template file, inserts the given MQTT
topic, network, and Modbus address, and adds it to the `config.yaml` file.  A
typical `compile_template` command would be:

```
compile_template temp_humid front_door outdoors 10
```

This takes the template `temp_humid.yamlt`, sets the MQTT topic to
`front_door`, the network to `outdoors`, and the Modbus address to 10, and
adds it to `config.yamlt`.

The advantage of using templates is that you can very easily set up entire
Modbus device networks with only a few lines of config.  For example if you
have three outdoors temperature/humidity sensors you can create the config
file with:

```
compile_template temp_humid front_door outdoors 10
compile_template temp_humid back_door outdoors 11
compile_template temp_humid shed outdoors 12
```

Finally, mkconfig will apply the new configuration to modmqqtd.  If you don't
want to apply the new configuration but only generate the config file, run in
debug mode with `-d`.

Suggestions for updates to the documentation to cover unclear portions are
welcome, having worked with the code it's not always clear which bits need the
most explanation.

# Template files

A template file is a standard YAML config as used by MQMGateway, with three
special placeholders:

- XXXX in the template is replaced with the MQTT topic name.
- YYYY in the template is replaced with the Modbus network name.
- ZZZZ in the template is replaced with the Modbus device address.

To see an example, look at any of the `.yamlt` template files.

# Home Assistant

The next step will be to extend the templates to target use in Home Assistant,
which would otherwise also require extensive hand-written YAML in order to
function.  This means that Modbus -> MQTT -> Home Assistant configuration can
be performed in a single operation.
