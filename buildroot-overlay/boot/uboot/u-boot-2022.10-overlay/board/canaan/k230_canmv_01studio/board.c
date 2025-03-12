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

#define AIC8800

sysctl_boot_mode_e sysctl_boot_get_boot_mode(void)
{
	return SYSCTL_BOOT_SDIO0;
}

#ifdef CONFIG_BOARD_LATE_INIT
int board_late_init(void)
{
#ifndef AIC8800
    #define USB_IDPULLUP0 		(1<<4)
    #define USB_DMPULLDOWN0 	(1<<8)
    #define USB_DPPULLDOWN0 	(1<<9)



    u32 usb_ctl3 = readl((const volatile void __iomem *)(SDIO0_BASE_ADDR + 0x7c));

	usb_ctl3 |= USB_IDPULLUP0;
	usb_ctl3 &= ~(USB_DMPULLDOWN0 | USB_DPPULLDOWN0);
	writel(usb_ctl3, ( volatile void __iomem *)(SDIO0_BASE_ADDR + 0x7c));
	//printf("usb_ctl3 =%x\n",usb_ctl3);

	usb_ctl3 = readl((const volatile void __iomem *)(SDIO0_BASE_ADDR + 0x9c));
	usb_ctl3 |= USB_IDPULLUP0;
	usb_ctl3 |= (USB_DMPULLDOWN0 | USB_DPPULLDOWN0);
	writel(usb_ctl3, ( volatile void __iomem *)(SDIO0_BASE_ADDR + 0x9c));
#endif
	env_set_ulong("mmc_boot_dev_num", g_bootmod - SYSCTL_BOOT_SDIO0);

#ifdef AIC8800
	u32 wifi_regon_gpio1_dir = readl((void*)(GPIO_BASE_ADDR1 + 0x4));
	wifi_regon_gpio1_dir |= 1 << 21;
	writel(wifi_regon_gpio1_dir, (void*)(GPIO_BASE_ADDR1 + 0x4));

	// reset gpio1 -> WIFI REGON
	u32 wifi_regon_gpio1_data = readl((void*)(GPIO_BASE_ADDR1 + 0x0));
	wifi_regon_gpio1_data &= ~(1 << 21);
	writel(wifi_regon_gpio1_data, (void*)(GPIO_BASE_ADDR1 + 0x0));
	mdelay(50);
	// reset gpio1 -> WIFI REGON
	wifi_regon_gpio1_data |= 1 << 21;
	writel(wifi_regon_gpio1_data, (void*)(GPIO_BASE_ADDR1 + 0x0));
#endif

	//printf("usb_ctl3 =%x\n",usb_ctl3);
    return 0;
}
#endif
