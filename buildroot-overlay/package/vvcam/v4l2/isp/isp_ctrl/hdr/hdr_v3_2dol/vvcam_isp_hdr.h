/****************************************************************************
*
*    The MIT License (MIT)
*
*    Copyright (c) 2014 - 2024 Vivante Corporation
*
*    Permission is hereby granted, free of charge, to any person obtaining a
*    copy of this software and associated documentation files (the "Software"),
*    to deal in the Software without restriction, including without limitation
*    the rights to use, copy, modify, merge, publish, distribute, sublicense,
*    and/or sell copies of the Software, and to permit persons to whom the
*    Software is furnished to do so, subject to the following conditions:
*
*    The above copyright notice and this permission notice shall be included in
*    all copies or substantial portions of the Software.
*
*    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
*    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
*    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
*    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
*    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
*    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
*    DEALINGS IN THE SOFTWARE.
*
*****************************************************************************
*
*    The GPL License (GPL)
*
*    Copyright (C) 2014 - 2024 Vivante Corporation
*
*    This program is free software; you can redistribute it and/or
*    modify it under the terms of the GNU General Public License
*    as published by the Free Software Foundation; either version 2
*    of the License, or (at your option) any later version.
*
*    This program is distributed in the hope that it will be useful,
*    but WITHOUT ANY WARRANTY; without even the implied warranty of
*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*    GNU General Public License for more details.
*
*    You should have received a copy of the GNU General Public License
*    along with this program; if not, write to the Free Software Foundation,
*    Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*
*****************************************************************************
*
*    Note: This software is released under dual MIT and GPL licenses. A
*    recipient may use this file under the terms of either the MIT license or
*    GPL License. If you wish to use only one license not the other, you can
*    indicate your decision by deleting one of the above license notices in your
*    version of this file.
*
*****************************************************************************/


#ifndef __VVCAM_ISP_HDR_H__
#define __VVCAM_ISP_HDR_H__

#include "vvcam_isp_ctrl.h"

#define VVCAM_ISP_CID_HDR_ENABLE            (VVCAM_ISP_CID_HDR_BASE + 0x0000)
#define VVCAM_ISP_CID_HDR_DEGHOST_LS_ENABLE (VVCAM_ISP_CID_HDR_BASE + 0x0001)
#define VVCAM_ISP_CID_HDR_DEGHOST_LSVS_ENABLE \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0002)
#define VVCAM_ISP_CID_HDR_RESET             (VVCAM_ISP_CID_HDR_BASE + 0x0003)
#define VVCAM_ISP_CID_HDR_COLOR_WEIGHT      (VVCAM_ISP_CID_HDR_BASE + 0x0004)
#define VVCAM_ISP_CID_HDR_RATIO             (VVCAM_ISP_CID_HDR_BASE + 0x0005)
#define VVCAM_ISP_CID_HDR_TRANS_RANGE       (VVCAM_ISP_CID_HDR_BASE + 0x0006)
#define VVCAM_ISP_CID_HDR_EXTEND_BIT        (VVCAM_ISP_CID_HDR_BASE + 0x0007)

#define VVCAM_ISP_CID_HDR_DEGHOST_MOTION_WEIGHT \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0008)
#define VVCAM_ISP_CID_HDR_DEGHOST_LS_MOTION_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0009)
#define VVCAM_ISP_CID_HDR_DEGHOST_LS_MOTION_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000A)
#define VVCAM_ISP_CID_HDR_DEGHOST_LSVS_MOTION_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000B)
#define VVCAM_ISP_CID_HDR_DEGHOST_LSVS_MOTION_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000C)
#define VVCAM_ISP_CID_HDR_DEGHOST_LS_DARK_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000D)
#define VVCAM_ISP_CID_HDR_DEGHOST_LS_DARK_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000E)
#define VVCAM_ISP_CID_HDR_DEGHOST_LSVS_DARK_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x000F)
#define VVCAM_ISP_CID_HDR_DEGHOST_LSVS_DARK_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0010)

#define VVCAM_ISP_CID_HDR_STAT_COLOR_WEIGHT (VVCAM_ISP_CID_HDR_BASE + 0x0011)
#define VVCAM_ISP_CID_HDR_STAT_RATIO        (VVCAM_ISP_CID_HDR_BASE + 0x0012)
#define VVCAM_ISP_CID_HDR_STAT_TRANS_RANGE  (VVCAM_ISP_CID_HDR_BASE + 0x0013)
#define VVCAM_ISP_CID_HDR_STAT_EXTEND_BIT   (VVCAM_ISP_CID_HDR_BASE + 0x0014)

#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_MOTION_WEIGHT \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0015)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LS_MOTION_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0016)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LS_MOTION_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0017)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LSVS_MOTION_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0018)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LSVS_MOTION_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x0019)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LS_DARK_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x001A)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LS_DARK_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x001B)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LSVS_DARK_LOWER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x001C)
#define VVCAM_ISP_CID_HDR_STAT_DEGHOST_LSVS_DARK_UPPER_THR \
                                            (VVCAM_ISP_CID_HDR_BASE + 0x001D)

#ifdef __KERNEL__
int vvcam_isp_hdr_ctrl_count(void);
int vvcam_isp_hdr_ctrl_create(struct vvcam_isp_dev *isp_dev);
#endif

#endif
