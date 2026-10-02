/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 *
 * Copyright (c)  OpenBOR Team
 */

#ifndef BOR_METAL_H
#define BOR_METAL_H

#include "SDL.h"

#ifdef OB_METAL

int video_metal_available(void);
int video_metal_set_mode(SDL_Window *window, int width, int height, int bytes_per_pixel, int vsync);
int video_metal_copy_frame(const void *data, int width, int height, int pitch, int bytes_per_pixel, int stretch, int smooth);
void video_metal_clear(void);
void video_metal_shutdown(void);
const char *video_metal_last_error(void);
void video_metal_configure_darwin_window(SDL_Window *window);
int video_metal_get_darwin_window_frame(SDL_Window *window, int *x, int *y, int *w, int *h);
int video_metal_set_darwin_window_frame(SDL_Window *window, int x, int y, int w, int h);
int video_metal_get_darwin_visible_frame(SDL_Window *window, int *x, int *y, int *w, int *h);
void video_metal_hide_darwin_window(SDL_Window *window);

#else

#define video_metal_available()              0
#define video_metal_set_mode(W,X,Y,Z,Q)      0
#define video_metal_copy_frame(A,B,C,D,E,F,G)  0
#define video_metal_clear()
#define video_metal_shutdown()
#define video_metal_last_error()             "Metal backend not built"
#define video_metal_configure_darwin_window(W)
#define video_metal_get_darwin_window_frame(W,X,Y,Z,Q) 0
#define video_metal_set_darwin_window_frame(W,X,Y,Z,Q) 0
#define video_metal_get_darwin_visible_frame(W,X,Y,Z,Q) 0
#define video_metal_hide_darwin_window(W)

#endif

#endif
