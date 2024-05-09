/****************************************************************************
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2023 VeriSilicon Holdings Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 *****************************************************************************
 *
 * The GPL License (GPL)
 *
 * Copyright (c) 2023 VeriSilicon Holdings Co., Ltd.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program;
 *
 *****************************************************************************
 *
 * Note: This software is released under dual MIT and GPL licenses. A
 * recipient may use this file under the terms of either the MIT license or
 * GPL License. If you wish to use only one license not the other, you can
 * indicate your decision by deleting one of the above license notices in your
 * version of this file.
 *
 *****************************************************************************/

#include <linux/module.h>
#include <linux/version.h>
#include <linux/platform_device.h>
#include "vvcam_video_platform.h"

static int devices_mask = 0x01;
MODULE_PARM_DESC(devices_mask, "vvcam video devices mask");

static void vvcam_video_pdev_release(struct device *dev)
{
    dev_info(dev, "%s\n", __func__);
	return;
}

static struct platform_device vvcam_video0_pdev = {
	.name          = "vvcam-video",
	.id            = 0,
	.dev.release   = vvcam_video_pdev_release,
};

static struct platform_device vvcam_video1_pdev = {
	.name          = "vvcam-video",
	.id            = 1,
	.dev.release   = vvcam_video_pdev_release,
};

int vvcam_video_platform_device_register(void)
{
    int ret = 0;
    int devs_mask = 0;

    if (devices_mask & 0x01) {
        ret = platform_device_register(&vvcam_video0_pdev);
        if (ret) {
            goto err_register;
        }
        devs_mask |= 0x01;
    }

    if (devices_mask & 0x02) {
        ret = platform_device_register(&vvcam_video1_pdev);
        if (ret) {
            goto err_register;
        }
        devs_mask |= 0x02;
    }

    return ret;

err_register:
    if (devs_mask & 0x01)
		platform_device_unregister(&vvcam_video0_pdev);
	if (devs_mask & 0x02)
		platform_device_unregister(&vvcam_video1_pdev);

    return ret;
}

void vvcam_video_platform_device_unregister(void)
{
    if (devices_mask & 0x01)
        platform_device_unregister(&vvcam_video0_pdev);

    if (devices_mask & 0x02)
        platform_device_unregister(&vvcam_video1_pdev);

    return;
}

module_param(devices_mask, int, 0644);
