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
 #ifndef __VVCAM_PIPELINE_LINK_H__
 #define __VVCAM_PIPELINE_LINK_H__

extern struct v4l2_subdev *g_vvcam_isp_subdev[VVCAM_ISP_DEV_MAX];

static struct vvcam_v4l2_link pipeline0[] = {
    {
        .local_is_video = true,
        .video_index = 0,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 1,
    },
    {
        .local_is_video = true,
        .video_index = 1,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 2,
    },
    {
        .local_is_video = true,
        .video_index = 2,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 3,
    },
    {
        .local_is_video = true,
        .video_index = 3,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 4,
    },

};

static struct vvcam_v4l2_link pipeline1[] = {
    {
        .local_is_video = true,
        .video_index = 0,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 1,
    },
    {
        .local_is_video = true,
        .video_index = 1,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 2,
    },
    {
        .local_is_video = true,
        .video_index = 2,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 3,
    },
};

static struct vvcam_v4l2_link mcm_pipeline0[] = {
    {
        .local_is_video = true,
        .video_index = 0,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 1,
    },
    {
        .local_is_video = true,
        .video_index = 1,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 6,
    },
    {
        .local_is_video = true,
        .video_index = 2,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 11,
    },
    {
        .local_is_video = true,
        .video_index = 3,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 16,
    },
    {
        .local_is_video = true,
        .video_index = 4,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 4,
    },
    {
        .local_is_video = true,
        .video_index = 5,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 9,
    },
    {
        .local_is_video = true,
        .video_index = 6,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 14,
    },
    {
        .local_is_video = true,
        .video_index = 7,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[0],
        .remote_pad = 19,
    },
};

static struct vvcam_v4l2_link mcm_pipeline1[] = {
    {
        .local_is_video = true,
        .video_index = 0,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 1,
    },
    {
        .local_is_video = true,
        .video_index = 1,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 6,
    },
    {
        .local_is_video = true,
        .video_index = 2,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 11,
    },
    {
        .local_is_video = true,
        .video_index = 3,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 16,
    },
    {
        .local_is_video = true,
        .video_index = 4,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 4,
    },
    {
        .local_is_video = true,
        .video_index = 5,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 9,
    },
    {
        .local_is_video = true,
        .video_index = 6,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 14,
    },
    {
        .local_is_video = true,
        .video_index = 7,
        .local_pad = 0,
        .remote_subdev = &g_vvcam_isp_subdev[1],
        .remote_pad = 19,
    },
};

 #endif
