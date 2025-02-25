#include <stdio.h>
#include <stdlib.h>
#include "alsa/asoundlib.h"
#include "alsa/pcm.h"
#include "get_pcm.h"

#define PCM_DEVICE "default"

static snd_pcm_t *pcm_handle;
static snd_pcm_hw_params_t *params;
static snd_pcm_uframes_t frames;

int initPcm(int sample_rate, int num_channels,int frame_samples,int bits_per_sample) {
    int rc;
    int dir = 0;
    int size=0;
    frames=frame_samples;

    // Open PCM device for recording (capture)
    rc = snd_pcm_open(&pcm_handle, PCM_DEVICE, SND_PCM_STREAM_CAPTURE, 0);
    if (rc < 0) {
        fprintf(stderr, "unable to open pcm device: %s\n", snd_strerror(rc));
        return -1;
    }

    // Allocate a hardware parameters object
    snd_pcm_hw_params_alloca(&params);

    // Fill it in with default values
    snd_pcm_hw_params_any(pcm_handle, params);

    // Set the desired hardware parameters
    snd_pcm_hw_params_set_access(pcm_handle, params, SND_PCM_ACCESS_RW_INTERLEAVED);
    snd_pcm_hw_params_set_format(pcm_handle, params, SND_PCM_FORMAT_S16_LE);
    snd_pcm_hw_params_set_channels(pcm_handle, params, num_channels);
    snd_pcm_hw_params_set_rate_near(pcm_handle, params, (unsigned int*)&sample_rate, &dir);
    snd_pcm_hw_params_set_period_size(pcm_handle, params, frames, dir);
    snd_pcm_uframes_t frame_size = frame_samples*2*3;
    snd_pcm_hw_params_set_buffer_size_near(pcm_handle, params, &frame_size);

    // Write the parameters to the driver
    rc = snd_pcm_hw_params(pcm_handle, params);
    if (rc < 0) {
        fprintf(stderr, "unable to set hw parameters: %s\n", snd_strerror(rc));
        snd_pcm_close(pcm_handle);
        return -1;
    }
    // Use a buffer large enough to hold one period
    snd_pcm_hw_params_get_period_size(params, &frames, &dir);
    return 0;
}

void getPcm(char* encoder_input_buffer) {
    if (encoder_input_buffer == NULL) {
        fprintf(stderr, "encoder_input_buffer is NULL\n");
        return;
    }

    if (pcm_handle == NULL) {
        fprintf(stderr, "pcm_handle is NULL\n");
        return;
    }

    int rc=0;
    rc = snd_pcm_readi(pcm_handle, encoder_input_buffer, frames);
    if (rc == -EPIPE) {
        fprintf(stderr, "overrun occurred\n");
        snd_pcm_prepare(pcm_handle);
        return;
    } else if (rc < 0) {
        fprintf(stderr, "error from read: %s\n", snd_strerror(rc));
        return;
    } else if (rc != (int)frames) {
        fprintf(stderr, "short read, read %d frames\n", rc);
        return;
    }
}


int deinitPcm(){
    snd_pcm_drain(pcm_handle);
    snd_pcm_close(pcm_handle);
    return 0;
}


