# BMC kernel patches (linux-6.12)

Platform-specific kernel patches for AST2700 / SPC6 BMC (SONiC BMC, Microsoft Sonic BMC OS). Apply these on top of a linux-6.12 (or compatible) tree when building the BMC kernel.

## Source

Patches are copied from OpenBMC meta-nvidia:

- **meta-ast2700**  
  `meta-nvidia/meta-switch/meta-ast2700/recipes-kernel/linux/linux-aspeed/series/`  
  (24 patches: hwmon, platform/mellanox, leds, i2c-mux, LPC/PCC, eSPI, MCTP, dt-bindings)

- **meta-spc6-ast2700-a1**  
  `meta-nvidia/meta-switch/meta-ast2700/meta-spc6-ast2700-a1/recipes-kernel/linux/linux-aspeed/series/`  
  (2 patches: i3c CCC SETMWL and SETNEWDA workarounds)

## Apply order

Use the numeric prefix order (0001…0030, then dt-bindings). SPC6-specific patches 0025 and 0026 are inserted in that sequence.

To refresh from OpenBMC, re-run the copy from the two `series/` directories into this folder.
