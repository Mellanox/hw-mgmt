/*
 * drivers/misc/mlxcpld-io.c
 * Copyright (c) 2016 Mellanox Technologies. All rights reserved.
 * Copyright (c) 2016 Vadim Pasternak <vadimp@mellanox.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the names of the copyright holders nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * Alternatively, this software may be distributed under the terms of the
 * GNU General Public License ("GPL") version 2 as published by the Free
 * Software Foundation.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pci.h>
#include <linux/slab.h>

#define MLXCPLD_IO_DEVICE_NAME			"mlxcpld_io"

/* LPC IFC in PCH defines */
#define MLXCPLD_IO_CPLD_LPC_I2C_BASE_ADRR	0x2000
#define MLXCPLD_IO_CPLD_LPC_REG_BASE_ADRR	0x2500
#define MLX_IO_LPC_BMC_BASE_ADRR		0xe4
#define MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID	0
#define MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID	31
#define MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID	0
#define MLXCPLD_IO_CPLD_LPC_QM67_DEV_ID		0x1c4f
#define MLXCPLD_IO_CPLD_LPC_QM77_DEV_ID		0x1e55
#define MLXCPLD_IO_CPLD_LPC_RNG_DEV_ID		0x1f38
/* Reserved bits are: 2, 16, 17, 24 - 31 */
#define MLXCPLD_IO_CPLD_RESERVED_MASK		0xff030002
/* Bits 18 - 23 allow decode range address mask, bit 1 enables decode range */
#define MLXCPLD_IO_CPLD_LPC_DECODE_MASK		0xfc0001
/* Bits 1, 2 should be cleared in base address */
#define MLXCPLD_IO_CPLD_LPC_CLEAR_MASK		0xfff3

/* Use generic decode range 4 for CPLD LPC */
#define MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_RANGE4	0x90
#define MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_BASE	0x84
#define MLXCPLD_IO_CPLD_LPC_RNG_CTRL		0x84
#define MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_RANGES	4
#define MLX_IO_LPC_BMC_RANGE					3
#define MLXCPLD_IO_CPLD_LPC_I2C_RANGE		2
#define MLXCPLD_IO_CPLD_LPC_RANGE			3
#define MLXCPLD_IO_CPLD_LPC_CLKS_EN			0
#define MLXCPLD_IO_CPLD_LPC_IO_RANGE		0x100

/* struct mlxcpld_io - private data:
 * @lpc_reg: register space
 * @dev_id: platform device id
 * @pdev: platform device
 */
struct mlxcpld_io {
	u32 lpc_reg[MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_RANGES];
	u16 dev_id;
	struct platform_device *pdev;
};

/* Regions for LPC I2C controller and LPC base register space */ 
static struct resource mlxcpld_io_lpc_resources[] = {
	[0] = DEFINE_RES_NAMED(MLXCPLD_IO_CPLD_LPC_I2C_BASE_ADRR,
			       MLXCPLD_IO_CPLD_LPC_IO_RANGE,
			       "mlxcpld_io_cpld_lpc_i2c_ctrl", IORESOURCE_IO),
	[1] = DEFINE_RES_NAMED(MLXCPLD_IO_CPLD_LPC_REG_BASE_ADRR,
			       MLXCPLD_IO_CPLD_LPC_IO_RANGE,
			       "mlxcpld_io_cpld_lpc_regs", IORESOURCE_IO),
};

static struct platform_device *mlxcpld_io_plat;

static int
mlxcpld_io_lpc_i2c_dec_range_config(struct mlxcpld_io *mlxcpld_io,
				    struct pci_dev *pdev, u8 range,
				    u16 base_addr)
{
	u16 rng_reg;
	u32 val;
	int err;

	if (range >= MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_RANGES) {
		dev_err(&mlxcpld_io->pdev->dev, "Incorrect LPC decode range %d %d\n",
			range, MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_RANGES);
		return -ERANGE;
	}

	rng_reg = MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_BASE + 4 * range;
	err = pci_read_config_dword(pdev, rng_reg, &val);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "Access to LPC_PCH config failed, err %d\n",
			err);
		return -EFAULT;
	}
	mlxcpld_io->lpc_reg[range] = val;

	/* Clean all bits excepted reserved (reserved: 2, 16, 17 , 24 - 31). */
	val &= MLXCPLD_IO_CPLD_RESERVED_MASK;
	/* 
	 * Set bits 18 - 23 to allow decode range address mask, set bit 1 to
	 * enable decode range, clear bit 1,2 in base address.
	 */
	val |= MLXCPLD_IO_CPLD_LPC_DECODE_MASK | (base_addr &
	       MLXCPLD_IO_CPLD_LPC_CLEAR_MASK);
	err = pci_write_config_dword(pdev, rng_reg, val);
	if (err)
		dev_err(&mlxcpld_io->pdev->dev, "Config of LPC_PCH Generic Decode Range %d failed, err %d\n",
			range, err);

	return err;
}

static void
mlxcpld_io_lpc_dec_rng_config_clean(struct pci_dev *pdev, u32 val, u8 range)
{
	/* Restore old value */
	if (pci_write_config_dword(pdev,
				   (MLXCPLD_IO_CPLD_LPC_PCH_GEN_DEC_BASE +
				   range * 4), val))
		dev_err(&pdev->dev, "Deconfig of LPC_PCH Generic Decode Range %x failed\n",
			range);
}

static int
mlxcpld_io_lpc_request_region(struct mlxcpld_io *mlxcpld_io,
			      struct resource *res)
{
	resource_size_t size = resource_size(res);

	if (!devm_request_region(&mlxcpld_io->pdev->dev, res->start, size,
				 res->name)) {
		devm_release_region(&mlxcpld_io->pdev->dev, res->start, size);

		if (!devm_request_region(&mlxcpld_io->pdev->dev, res->start, size,
					 res->name)) {
			dev_err(&mlxcpld_io->pdev->dev, "Request ioregion 0x%llx len 0x%llx for %s fail\n",
				res->start, size, res->name);
			return -EIO;
		}
	}

	return 0;
}

static int mlxcpld_io_lpc_request_regions(struct mlxcpld_io *mlxcpld_io)
{
	int i;
	int err;

	for (i = 0; i < ARRAY_SIZE(mlxcpld_io_lpc_resources); i++) {
		err = mlxcpld_io_lpc_request_region(mlxcpld_io,
					&mlxcpld_io_lpc_resources[i]);
		if (err)
			return err;
	}

	return 0;
}

static int
mlxcpld_io_lpc_ivb_config(struct mlxcpld_io *mlxcpld_io, struct pci_dev *pdev)
{
	int err;

	err = mlxcpld_io_lpc_i2c_dec_range_config(mlxcpld_io, pdev,
					MLXCPLD_IO_CPLD_LPC_I2C_RANGE,
					MLXCPLD_IO_CPLD_LPC_I2C_BASE_ADRR);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "LPC decode range %d config failed, err %d\n",
			MLXCPLD_IO_CPLD_LPC_I2C_RANGE, err);
		pci_dev_put(pdev);
		return -EFAULT;
	}

	err = mlxcpld_io_lpc_i2c_dec_range_config(mlxcpld_io, pdev,
					MLXCPLD_IO_CPLD_LPC_RANGE,
					MLXCPLD_IO_CPLD_LPC_REG_BASE_ADRR);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "LPC decode range %d config failed, err %d\n",
			MLXCPLD_IO_CPLD_LPC_I2C_RANGE, err);
		return -EFAULT;
	}

	err = mlxcpld_io_lpc_i2c_dec_range_config(mlxcpld_io, pdev,
					MLX_IO_LPC_BMC_RANGE,
					MLX_IO_LPC_BMC_BASE_ADRR);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "LPC decode range %d config failed, err %d\n",
			MLX_IO_LPC_BMC_RANGE, err);
		return -EFAULT;
	}

	return err;
}

static void
mlxcpld_io_lpc_ivb_config_clean(struct mlxcpld_io *mlxcpld_io,
				struct pci_dev *pdev)
{
	mlxcpld_io_lpc_dec_rng_config_clean(pdev,
				mlxcpld_io->lpc_reg[MLXCPLD_IO_CPLD_LPC_RANGE],
				MLXCPLD_IO_CPLD_LPC_RANGE);
	mlxcpld_io_lpc_dec_rng_config_clean(pdev,
				mlxcpld_io->lpc_reg[MLXCPLD_IO_CPLD_LPC_I2C_RANGE],
				MLXCPLD_IO_CPLD_LPC_I2C_RANGE);

}

static int
mlxcpld_io_lpc_range_config(struct mlxcpld_io *mlxcpld_io,
			    struct pci_dev *pdev)
{
	u32 val, lpc_clks;
	int err;

	err = pci_read_config_dword(pdev, MLXCPLD_IO_CPLD_LPC_RNG_CTRL, &val);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "Access to LPC Ctrl reg failed, err %d\n",
			err);
		return -EFAULT;
	}
	lpc_clks = val & 0x3;
	if (lpc_clks != MLXCPLD_IO_CPLD_LPC_CLKS_EN) {
		val &= 0xFFFFFFFC;
		err = pci_write_config_dword(pdev,
					     MLXCPLD_IO_CPLD_LPC_RNG_CTRL,
					     val);
		if (err) {
			dev_err(&mlxcpld_io->pdev->dev, "Config LPC CLKS CTRL failed, err %d\n",
				err);
			return -EFAULT;
		}
	}

	return err;
}

static int mlxcpld_io_lpc_config(struct mlxcpld_io *mlxcpld_io)
{
	struct pci_dev *pdev = NULL;
	u16 dev_id;
	int err;

	pdev = pci_get_bus_and_slot(MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
				PCI_DEVFN(MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
				MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID));

	if (!pdev) {
		dev_err(&mlxcpld_io->pdev->dev, "LPC controller bus:%d slot:%d func:%d not found\n",
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID);
		return -EFAULT;
	}

	err = pci_read_config_word(pdev, 2, &dev_id);
	if (err) {
		dev_err(&mlxcpld_io->pdev->dev, "Access PCIe LPC interface failed, err %d\n",
			err);
		goto failure;
	}

	switch (dev_id) {
	case MLXCPLD_IO_CPLD_LPC_QM67_DEV_ID:
	case MLXCPLD_IO_CPLD_LPC_QM77_DEV_ID:
		err = mlxcpld_io_lpc_ivb_config(mlxcpld_io, pdev);
		break;
	case MLXCPLD_IO_CPLD_LPC_RNG_DEV_ID:
		err = mlxcpld_io_lpc_range_config(mlxcpld_io, pdev);
		break;
	default:
		err = -ENXIO;
		dev_err(&mlxcpld_io->pdev->dev, "Unsupported DevId 0x%x bus:%d slot:%d func:%d\n",
			dev_id, MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID);
		goto failure;
	}
	mlxcpld_io->dev_id = dev_id;

failure:
	pci_dev_put(pdev);
	return err;
}

static int mlxcpld_io_lpc_config_clean(struct mlxcpld_io *mlxcpld_io)
{
	struct pci_dev *pdev = NULL;
	int err = 0;

	pdev = pci_get_bus_and_slot(MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
				PCI_DEVFN(MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
				MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID));
	if (!pdev) {
		dev_err(&mlxcpld_io->pdev->dev, "LPC controller bus:%d slot:%d func:%d not found\n",
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID);
		return -EFAULT;
	}

	switch (mlxcpld_io->dev_id) {
	case MLXCPLD_IO_CPLD_LPC_QM67_DEV_ID:
	case MLXCPLD_IO_CPLD_LPC_QM77_DEV_ID:
		mlxcpld_io_lpc_ivb_config_clean(mlxcpld_io, pdev);
		break;
	case MLXCPLD_IO_CPLD_LPC_RNG_DEV_ID:
		break;
	default:
		err = -ENXIO;
		dev_err(&mlxcpld_io->pdev->dev, "Unsupported DevId 0x%x bus:%d slot:%d func:%d\n",
			mlxcpld_io->dev_id, MLXCPLD_IO_CPLD_LPC_CTRL_IFC_BUS_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_SLOT_ID,
			MLXCPLD_IO_CPLD_LPC_CTRL_IFC_FUNC_ID);
		break;
	}

	pci_dev_put(pdev);

	return err;
}

static int __init mlxcpld_io_init(void)
{
	struct mlxcpld_io *mlxcpld_io;
	int err;

	mlxcpld_io_plat = platform_device_alloc(MLXCPLD_IO_DEVICE_NAME,
						PLATFORM_DEVID_NONE);
	if (!mlxcpld_io_plat)
		return -ENOMEM;

	err = platform_device_add(mlxcpld_io_plat);
	if (err)
		goto fail_platform_device_add;

	mlxcpld_io = devm_kzalloc(&mlxcpld_io_plat->dev,
				  sizeof(struct mlxcpld_io), GFP_KERNEL);
	if (!mlxcpld_io) {
		err = -ENOMEM;
		dev_err(&mlxcpld_io_plat->dev, "Failed to allocate mlxcpld_io\n");
		goto fail_alloc;
	}

	platform_set_drvdata(mlxcpld_io_plat, mlxcpld_io);
	mlxcpld_io->pdev = mlxcpld_io_plat;

	err = mlxcpld_io_lpc_config(mlxcpld_io);
	if (err) {
		dev_err(&mlxcpld_io_plat->dev, "Failed to configure LPC interface\n");
		goto fail_alloc;
	}

	err = mlxcpld_io_lpc_request_regions(mlxcpld_io);
	if (err) {
		dev_err(&mlxcpld_io_plat->dev, "Request ioregion failed (%d)\n",
			err);
		goto fail_alloc;
	}

	return err;

fail_alloc:
	platform_device_del(mlxcpld_io_plat);
fail_platform_device_add:
	platform_device_put(mlxcpld_io_plat);

	return err;
}

static void __exit mlxcpld_io_exit(void)
{
	struct mlxcpld_io *mlxcpld_io = platform_get_drvdata(mlxcpld_io_plat);

	mlxcpld_io_lpc_config_clean(mlxcpld_io);
	platform_device_del(mlxcpld_io_plat);
	platform_device_put(mlxcpld_io_plat);
}

module_init(mlxcpld_io_init);
module_exit(mlxcpld_io_exit);

MODULE_AUTHOR("Vadim Pasternak <vadimp@mellanox.com>"); 
MODULE_DESCRIPTION("Mellanox CPLD IO driver");
MODULE_LICENSE("Dual BSD/GPL");
MODULE_ALIAS("mlxcpld-io");
