# Mellanox hardware management reference design

This package supports thermal control and hardware management for Mellanox
switches.

Supported systems:

- MSN2740
- MSN2100
- MSN2410
- MSN2700
- MSN2010
- MQMB7800
- MSN3700
- MSN3800

Supported Kerenls version 

- 4.9.xx
- 4.19.xx


# Packaging:
The package depends on the next packages:
- init-system-helpers:	helper tools for all init systems
- lsb-base:		Linux Standard Base init script functionality
- udev:			/dev/ and hotplug management daemon
- i2c-tools:		heterogeneous set of I2C tools for Linux

Package contains the folder debian, with the rules for Debian package build.

Location:
https://github.com/Mellanox/hw-mgmt

To get package sources:
git clone https://mellanoxbsp@github.com/Mellanox/hw-mgmt

For Debian package build:
On a debian-based system, install the following programs:
sudo apt-get install devscripts build-essential lintian

- Go into thermal-control base folder and build Debian package.
- Run:
  debuild -us -uc
- Find in upper folder f.e. hw-management_1.mlnx.18.12.2018_amd64.deb

For converting deb package to rpm package:
On a debian-based system, install the following program:
sudo apt-get install alien

- alien --to-rpm hw-management_1.mlnx.18.12.2018_amd64.deb
- Find hw-management-1.mlnx.18.12.2018-2.x86_64.rpm

## Installation from local file and de-installation
Copy deb or rpm package to the system, for example to /tmp.

For deb package install with:
dpkg -i /tmp/ hw-management_1.mlnx.18.12.2018_amd64.deb
remove with:
dpkg --purge hw-management

For rpm install with:
- yum localinstall /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm
  or
- rpm -ivh /tmp/hw-management-1.mlnx.18.12.2018-2.x86_64.rpm
  remove with:
- yum remove hw-management
  or
- rpm -e hw-management


## Activation, de-activation and reading status
hw-management can be initialized and de-initialized by systemd service.
The next command could be used in order to configure persistent initialization
and de-initialization of hw-management:
- systemctl enable hw-management
- systemctl disable hw-management
- Running status of hw-management unit can be obtained by the following
  command:
- systemctl status hw-management
- Logging records of the thermal control written by systemd-journald.service
  can be queried by the following commands:
- journalctl --unit=hw-management
- journalctl -f -u hw-management
- Once "systemctl enable hw-management" is invoked, the thermal control will
  be automatically activated after the next and the following system reboots,
  until "systemctl disable hw-management" is not invoked.
  Application could be stopped by the following commands:
- systemctl stop hw-management.service

## Authors

* **Michael Shych** <michaelsh@mellanox.com>
* **Mykola Kostenok** <c_mykolak@mellanox.com>
* **Ohad Oz** <ohado@mellanox.com>
* **Oleksandr Shamray** <oleksandrs@mellanox.com>
* **Vadim Pasternak** <vadimp@mellanox.com>

## License

This project is Licensed under the GNU General Public License Version 2.

## Acknowledgments

* Mellanox Low-Level Team.
