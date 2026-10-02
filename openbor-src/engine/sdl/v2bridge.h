/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 */

#ifndef BOR_V2BRIDGE_H
#define BOR_V2BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

void video_v2_bridge_init(void);
void video_v2_bridge_shutdown(void);
void video_v2_bridge_publish(const void *data, int width, int height, int pitch, int bytes_per_pixel);
int video_v2_bridge_active(void);
int video_v2_bridge_hosted(void);

#ifdef __cplusplus
}
#endif

#endif
