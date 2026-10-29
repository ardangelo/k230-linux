#include <asm/asm.h>
#include <asm/io.h>
#include <asm/types.h>
#include <lmb.h>
#include <cpu_func.h>
#include <stdio.h>
#include <common.h>
#include <command.h>
#include <image.h>
#include <gzip.h>
#include <asm/spl.h>
#include "sysctl.h"

#include <pufs_hmac.h>
#include <pufs_ecp.h>
#include <pufs_rt.h>
#include "pufs_sm2.h"
#include <pufs_sp38a.h>
#include <pufs_sp38d.h>
#include <linux/kernel.h>
// #include "sdk_autoconf.h"
// #include "k230_board_common.h"
#include <env_internal.h>
#include <linux/delay.h>
#include <platform.h>
#include "../common/k230_board_common.h"

#define K230_STATUS_GPIO 25
#define K230_STATUS_MASK BIT(K230_STATUS_GPIO)
#define K230_STATUS_IOMUX (IOMUX_BASE_ADDR + K230_STATUS_GPIO * 4)
#define K230_STATUS_IOMUX_CFG (BIT(9) | BIT(7) | BIT(5) | (3U << 1))

/* Keep the status output low through U-Boot initialization and handoff. */
static void k230_status_drive_low(void)
{
	u32 data = readl((void *)(GPIO_BASE_ADDR0 + 0x0));
	u32 direction;

	/* Set output data before direction and pad configuration to avoid a pulse. */
	data &= ~K230_STATUS_MASK;
	writel(data, (void *)(GPIO_BASE_ADDR0 + 0x0));

	direction = readl((void *)(GPIO_BASE_ADDR0 + 0x4));
	direction |= K230_STATUS_MASK;
	writel(direction, (void *)(GPIO_BASE_ADDR0 + 0x4));

	/* GPIO, 1.8 V, output enabled, pull-down and drive strength 3. */
	writel(K230_STATUS_IOMUX_CFG, (void *)K230_STATUS_IOMUX);
}

int board_init(void)
{
	k230_status_drive_low();
	return 0;
}

void quick_boot_board_init(void)
{
	k230_status_drive_low();
}

void board_quiesce_devices(void)
{
	k230_status_drive_low();
}

void board_cleanup_before_linux(void)
{
	k230_status_drive_low();
}

sysctl_boot_mode_e sysctl_boot_get_boot_mode(void)
{
	return SYSCTL_BOOT_SDIO0;
}

#ifdef CONFIG_BOARD_LATE_INIT
int board_late_init(void)
{
	u32 direction, data;

	wifi_gpio_rst(53);
	env_set_ulong("mmc_boot_dev_num", g_bootmod - SYSCTL_BOOT_SDIO0);

	/* AIC8800D WIFI_REGON: assert reset for 50 ms, then release it. */
	direction = readl((void *)(GPIO_BASE_ADDR1 + 0x4));
	direction |= BIT(21);
	writel(direction, (void *)(GPIO_BASE_ADDR1 + 0x4));

	data = readl((void *)(GPIO_BASE_ADDR1 + 0x0));
	data &= ~BIT(21);
	writel(data, (void *)(GPIO_BASE_ADDR1 + 0x0));
	mdelay(50);
	data |= BIT(21);
	writel(data, (void *)(GPIO_BASE_ADDR1 + 0x0));

	return 0;
}
#endif
