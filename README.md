# Mellanox HW-Mgmt-Pkg

This package supports Mellanox switches based x86 family for chassis management.

## Getting Started
Repo supports the following branches:

1. Master - compliance to Kernel 4.9 supports Debian9, Sonic and ONL.
2. Sonic-3.16 - compliance to Sonic OS based Kernel 3.16.
3. ONL-3.16 - compliance to ONL OS based Kernel 3.16.
4. Common-3.16 - compliance to Debian8.

Supported systems:

- MSN274* Panther SF
- MSN21* Bulldog
- MSN24* Spider
- MSN27*|MSB*|MSX* Neptune, Tarantula, Scorpion, Scorpion2
- MSN201* Boxer
- QMB7*|SN37*|SN34* Jupiter, Jaguar, Anaconda

### Prerequisites

Linux based Debian stretch distribution and dkms package should be installed on the build system.

### Building Package 

Installation guideline for Kernel4.9 package (master branch)

Download the package from github master branch.

```
git clone https://github.com/Mellanox/hw-mgmt.git
```

Go into hw-mgmt base folder and build Debian package.

```
cd hw-mgmt
debuild -us -uc
```

Package build is expected in lower path - "hw-management_1.mlnx.V2.0.XXXX_amd64.deb"

```
cd ..
```

## Installing on switch

Copy Debian package "hw-management_1.mlnx.V2.0.XXXX_amd64.deb" from previous step to the system.
Operate Debian install. 

```
dpkg -i hw-management_1.mlnx.V2.0.XXXX_amd64.deb
```

### Initialization/de-initialization on switch

Post installation requires init, run the following command for that.

```
/etc/mlnx/mlnx-hw-management start
```

De-init in case of no use. 

```
/etc/mlnx/mlnx-hw-management stop
```

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

