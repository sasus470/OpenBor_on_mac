/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 *
 * Copyright (c)  OpenBOR Team
 */

#ifndef VIDEOCOMMON_H
#define VIDEOCOMMON_H

#include "types.h"

typedef struct {
	int width;
	int height;
	int pitch;
	int bytes_per_pixel;
	void *data;
} s_videosurface;

s_videomodes setupPreBlitProcessing(s_videomodes videomodes);
s_videosurface *getVideoSurface(s_screen *src);

#endif
