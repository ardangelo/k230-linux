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


#ifndef __VVCAM_ISP_EVENT_H__
#define __VVCAM_ISP_EVENT_H__

#define	 VVCAM_ISP_DEAMON_EVENT (V4L2_EVENT_PRIVATE_START + 2000)

enum vvcam_isp_vevent_id {
    VVCAM_ISP_EVENT_SET_FMT,
    VVCAM_ISP_EVENT_REQBUFS,
    VVCAM_ISP_EVENT_QBUF,
    VVCAM_ISP_EVENT_BUF_DONE,
    VVCAM_ISP_EVENT_STREAMON,
    VVCAM_ISP_EVENT_STREAMOFF,
    VVCAM_ISP_EVENT_S_CTRL,
    VVCAM_ISP_EVENT_G_CTRL,
    VVCAM_ISP_EVENT_S_SELECTION,
    VVCAM_ISP_EVENT_MAX,
};

struct vvcam_isp_plane {
    uint32_t dma_addr;
	uint32_t size;
};

struct vvcam_isp_buf {
    uint32_t pad;
    uint32_t index;
    uint32_t num_planes;
	struct vvcam_isp_plane planes[VIDEO_MAX_PLANES];
};

struct vvcam_isp_ctrl {
    uint32_t cid;
    uint32_t size;
#ifdef __KERNEL__
    uint8_t data[0];
#endif
};

struct vvcam_isp_event_pkg_head {
    uint32_t pad;
    uint8_t  dev;
    uint32_t eid;
    uint64_t shm_addr;
    uint32_t shm_size;
    uint32_t data_size;
};

struct vvcam_isp_event_pkg {
    struct vvcam_isp_event_pkg_head head;
    uint8_t  ack;
    int32_t  result;
    uint8_t data[2048];
};

struct vvcam_isp_crop_size {
    uint32_t width;
    uint32_t height;
    uint32_t x;
    uint32_t y;
};

#define VVCAM_ISP_IOC_BUFDONE    _IOWR('I',  BASE_VIDIOC_PRIVATE + 0, struct vvcam_isp_buf)

#ifdef __KERNEL__
#include "vvcam_isp_driver.h"

int vvcam_isp_set_fmt_event(struct vvcam_isp_dev *isp_dev, int pad, struct v4l2_mbus_framefmt *format);
int vvcam_isp_requebus_event(struct vvcam_isp_dev *isp_dev, int pad, uint32_t num_buffers);
int vvcam_isp_qbuf_event(struct vvcam_isp_dev *isp_dev, int pad, struct vvcam_vb2_buffer *buf);
int vvcam_isp_s_stream_event(struct vvcam_isp_dev *isp_dev, int pad, uint32_t status);
int vvcam_isp_s_ctrl_event(struct vvcam_isp_dev *isp_dev, int pad, struct v4l2_ctrl *ctrl);
int vvcam_isp_g_ctrl_event(struct vvcam_isp_dev *isp_dev, int pad, struct v4l2_ctrl *ctrl);
int vvcam_isp_s_selection_event(struct vvcam_isp_dev *isp_dev, int pad, struct vvcam_isp_crop_size *crop_size);


#endif


#endif
