/* Copyright (c) 2024, Canaan Bright Sight Co., Ltd
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 1. Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "vi_vo.h"
#include "hand_keypoint.h"

HandKeypoint::HandKeypoint(const char *kmodel_file, const int debug_mode)
:AIBase(kmodel_file, "HandKeypoint", debug_mode)
{
    model_name_ = "HandKeypoint";
    ai2d_out_tensor_ = get_input_tensor(0);
}

HandKeypoint::HandKeypoint(const char *kmodel_file, FrameCHWSize isp_shape, const int debug_mode)
: AIBase(kmodel_file,"HandKeypoint", debug_mode)
{
    model_name_ = "HandKeypoint";
    isp_shape_ = isp_shape;
    dims_t in_shape{1, isp_shape.channel, isp_shape.height, isp_shape.width};
    int isp_size = isp_shape.channel * isp_shape.height * isp_shape.width;
    ai2d_out_tensor_ = get_input_tensor(0);
}

HandKeypoint::~HandKeypoint()
{
}

void HandKeypoint::pre_process(cv::Mat ori_img, Bbox &bbox)
{
    ScopedTiming st(model_name_ + " pre_process image", debug_mode_);
    std::vector<uint8_t> chw_vec;
    Utils::hwc_to_chw(ori_img, chw_vec);
    Utils::crop_resize({ori_img.channels(), ori_img.rows, ori_img.cols}, chw_vec, bbox, ai2d_out_tensor_);
}

// for video
void HandKeypoint::pre_process(runtime_tensor& img_data, Bbox &bbox)
{
    ScopedTiming st(model_name_ + " pre_process_video", debug_mode_);
    Utils::crop_resize(bbox, ai2d_builder_, img_data, ai2d_out_tensor_);
}

void HandKeypoint::inference()
{
    this->run();
    this->get_output();
}

void HandKeypoint::draw_keypoints(cv::Mat &img, std::string text, Bbox &bbox, bool pic_mode, std::vector<int> &two_point)
{
    ScopedTiming st(model_name_ + " draw_keypoints", debug_mode_);
    int src_width = img.cols, src_height = img.rows;
    float *pred = p_outputs_[0];
    // 绘制关键点像素坐标
    int64_t output_tensor_size = output_shapes_[0][1];// 关键点输出 （x,y）*21= 42
    std::vector<int>results(output_tensor_size);
    if(pic_mode)
    {
        for (unsigned i = 0; i < output_tensor_size / 2; i++)
        {
            float x_kp;
            float y_kp;
            x_kp = pred[i * 2] * bbox.w + bbox.x;
            y_kp = pred[i * 2 + 1] * bbox.h + bbox.y;

            results[i * 2] = static_cast<int>(x_kp);
            results[i * 2 + 1] = static_cast<int>(y_kp);
            cv::circle(img, cv::Point(results[i * 2], results[i * 2 + 1]), 2, cv::Scalar(255, 155, 0), 3);
        }

        for (unsigned k = 0; k < 5; k++)
        {
            int i = k*8;
            unsigned char R = 255, G = 0, B = 0;

            switch(k)
            {
                case 0:R = 255; G = 0; B = 0;break;
                case 1:R = 255; G = 0; B = 255;break;
                case 2:R = 255; G = 255; B = 0;break;
                case 3:R = 0; G = 255; B = 0;break;
                case 4:R = 0; G = 0; B = 255;break;
                default: std::cout << "error" << std::endl;
            }

            cv::line(img, cv::Point(results[0], results[1]), cv::Point(results[i + 2], results[i + 3]), cv::Scalar(B,G,R), 2, cv::LINE_AA);
            cv::line(img, cv::Point(results[i + 2], results[i + 3]), cv::Point(results[i + 4], results[i + 5]), cv::Scalar(B, G, R), 2, cv::LINE_AA);
            cv::line(img, cv::Point(results[i + 4], results[i + 5]), cv::Point(results[i + 6], results[i + 7]), cv::Scalar(B, G, R), 2, cv::LINE_AA);
            cv::line(img, cv::Point(results[i + 6], results[i + 7]), cv::Point(results[i + 8], results[i + 9]), cv::Scalar(B, G, R), 2, cv::LINE_AA);
        }
    }
    else
    { 
        int osd_width = img.cols;
        int osd_height = img.rows;
        for (unsigned i = 0; i < output_tensor_size / 2; i++)
        {
            float x_kp;
            float y_kp;
            x_kp = pred[i * 2] * bbox.w + bbox.x;
            y_kp = pred[i * 2 + 1] * bbox.h + bbox.y;

            results[i * 2] = static_cast<int>(x_kp);
            results[i * 2 + 1] = static_cast<int>(y_kp);
        }

        two_point.push_back(results[8]);
        two_point.push_back(results[9]);
        two_point.push_back(results[16 + 8]);
        two_point.push_back(results[16 + 9]);
    }

}

vector<float*> HandKeypoint::get_out()
{
    return p_outputs_;
}


