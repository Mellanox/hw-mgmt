# BMC U-Boot (recipes-kernel/u-boot)

Platform-specific U-Boot DTS and config for AST2700 SPC6 BMC. One subfolder per U-Boot version.

## 2023.10

From OpenBMC: `meta-nvidia/meta-switch/meta-ast2700/meta-spc6-ast2700-a1/recipes-bsp/u-boot/files/`

- **ast2700-nvidia-spc6-bmc.dts** – device tree for SPC6 AST2700 BMC
- **u-boot-spc6.cfg** – U-Boot config fragment (SRC_URI: append for spc6-ast2700-a1-bmc)

Version matches branch `v2023.10-aspeed-ast2700` in meta-ast2700 u-boot-aspeed-sdk.
