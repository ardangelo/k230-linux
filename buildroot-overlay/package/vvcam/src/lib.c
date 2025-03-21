#include <stdio.h>
#include <vvcam_sensor.h>

extern struct vvcam_sensor vvcam_ov5647;
extern struct vvcam_sensor vvcam_imx335;
extern struct vvcam_sensor vvcam_gc2093;
extern struct vvcam_sensor vvcam_gc2053;
extern struct vvcam_sensor vvcam_bf3238;


void vvcam_sensor_init(void) {
    // get /dev/media0
    printf("k230 builtin sensor driver, built %s %s, API version %lu\n", __DATE__, __TIME__, VVCAM_API_VERSION);
    vvcam_sensor_add(&vvcam_ov5647);
    vvcam_sensor_add(&vvcam_imx335);
    vvcam_sensor_add(&vvcam_gc2093);
    vvcam_sensor_add(&vvcam_gc2053);
    vvcam_sensor_add(&vvcam_bf3238);
}
