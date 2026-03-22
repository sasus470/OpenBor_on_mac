/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 *
 * Copyright (c)  OpenBOR Team
 */
#if ANDROID

// CRxTRDude - changed the directory for neatness.
#include "android/app/jni/openbor/video.c"

#else

#include "sdlport.h"
#include "SDL2_framerate.h" // Kratus (01-2023) Added a FPS limit option in the video settings
#include <math.h>
#include "types.h"
#include "video.h"
#include "vga.h"
#include "screen.h"
#include "opengl.h"
#include "savedata.h"
#include "gfxtypes.h"
#include "gfx.h"
#include "pngdec.h"
#include "videocommon.h"
#include "../resources/OpenBOR_Icon_32x32_png.h"

SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *texture = NULL;
FPSmanager framerate_manager; // Kratus (01-2023) Added a FPS limit option in the video settings
s_videomodes stored_videomodes;
yuv_video_mode stored_yuv_mode;
int yuv_mode = 0;
char windowTitle[MAX_LABEL_LEN] = {"OpenBOR"};
int stretch = 0;
int opengl = 0; // OpenGL backend currently in use?
int nativeWidth, nativeHeight; // monitor resolution used in fullscreen mode
int brightness = 0;
#ifdef DARWIN
static int darwin_windowed_x = SDL_WINDOWPOS_UNDEFINED;
static int darwin_windowed_y = SDL_WINDOWPOS_UNDEFINED;
static int darwin_windowed_w = 0;
static int darwin_windowed_h = 0;

static void darwin_get_display_bounds(SDL_Rect *bounds)
{
	int display_index = 0;

	if(!bounds) return;
	bounds->x = 0;
	bounds->y = 0;
	bounds->w = nativeWidth;
	bounds->h = nativeHeight;

	if(window)
	{
		display_index = SDL_GetWindowDisplayIndex(window);
		if(display_index < 0) display_index = 0;
	}
	if(SDL_GetDisplayBounds(display_index, bounds) != 0)
	{
		bounds->x = 0;
		bounds->y = 0;
		bounds->w = nativeWidth;
		bounds->h = nativeHeight;
	}
}

static void darwin_remember_windowed_bounds(void)
{
	if(!window || savedata.fullscreen) return;
	SDL_GetWindowPosition(window, &darwin_windowed_x, &darwin_windowed_y);
	SDL_GetWindowSize(window, &darwin_windowed_w, &darwin_windowed_h);
}

static void darwin_apply_pseudo_fullscreen(void)
{
	SDL_Rect bounds = {0};

	if(!window) return;
	darwin_get_display_bounds(&bounds);

	SDL_SetWindowFullscreen(window, 0);
	SDL_SetWindowBordered(window, SDL_FALSE);
	SDL_SetWindowResizable(window, SDL_FALSE);
	SDL_SetWindowPosition(window, bounds.x, bounds.y);
	SDL_SetWindowSize(window, bounds.w, bounds.h);
	SDL_MaximizeWindow(window);
	SDL_RaiseWindow(window);
}

static void darwin_restore_windowed_mode(int w, int h)
{
	int restore_x = darwin_windowed_x;
	int restore_y = darwin_windowed_y;
	int restore_w = darwin_windowed_w > 0 ? darwin_windowed_w : w;
	int restore_h = darwin_windowed_h > 0 ? darwin_windowed_h : h;

	if(!window) return;

	SDL_SetWindowFullscreen(window, 0);
	SDL_RestoreWindow(window);
	SDL_SetWindowBordered(window, SDL_TRUE);
	SDL_SetWindowResizable(window, SDL_TRUE);
	SDL_SetWindowSize(window, restore_w, restore_h);
	SDL_SetWindowPosition(window, restore_x, restore_y);
	SDL_RaiseWindow(window);
}
#endif

void initSDL()
{
	SDL_DisplayMode video_info;
	int init_flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC;

    /*#if EE_CURRENT_PLATFORM == EE_PLATFORM_WINDOWS
       SDL_setenv("SDL_AUDIODRIVER", "directsound", true);
    #endif*/

	if(SDL_Init(init_flags) < 0)
	{
		printf("SDL Failed to Init!!!! (%s)\n", SDL_GetError());
		borExit(0);
	}
	SDL_ShowCursor(SDL_DISABLE);
	//atexit(SDL_Quit); //White Dragon: use SDL_Quit() into sdlport.c it's best practice!

#ifdef LOADGL
	if(SDL_GL_LoadLibrary(NULL) < 0)
	{
		printf("Warning: couldn't load OpenGL library (%s)\n", SDL_GetError());
	}
#endif

	SDL_GetCurrentDisplayMode(0, &video_info);
	nativeWidth = video_info.w;
	nativeHeight = video_info.h;
	printf("debug:nativeWidth, nativeHeight, bpp, Hz  %d, %d, %d, %d\n", nativeWidth, nativeHeight, SDL_BITSPERPIXEL(video_info.format), video_info.refresh_rate);

	// Kratus (01-2023) Added a FPS limit option in the video settings
	int maxFps = 200;
	SDL_initFramerate(&framerate_manager);
	SDL_setFramerate(&framerate_manager, maxFps);
}

void video_set_window_title(const char* title)
{
	if(window) SDL_SetWindowTitle(window, title);
	strncpy(windowTitle, title, sizeof(windowTitle)-1);
}

static unsigned pixelformats[4] = {SDL_PIXELFORMAT_INDEX8, SDL_PIXELFORMAT_BGR565, SDL_PIXELFORMAT_BGR888, SDL_PIXELFORMAT_ABGR8888};

int SetVideoMode(int w, int h, int bpp, bool gl)
{
	int flags = SDL_WINDOW_SHOWN | SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_RESIZABLE;
	static bool last_gl = false;
	static int last_x = SDL_WINDOWPOS_UNDEFINED;
	static int last_y = SDL_WINDOWPOS_UNDEFINED;
	int create_x = last_x;
	int create_y = last_y;
	int create_w = w;
	int create_h = h;

	if(gl) flags |= SDL_WINDOW_OPENGL;
	if(savedata.fullscreen)
	{
#ifdef DARWIN
		/* Modern macOS + legacy SDL fullscreen has been unstable for this port.
		   Use a borderless fullscreen-sized window instead of native fullscreen. */
#else
		flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
#endif
	}

	if(window && !(SDL_GetWindowFlags(window) & (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP)))
	{
		SDL_GetWindowPosition(window, &last_x, &last_y);
	}

	if(window && gl != last_gl)
	{
		SDL_DestroyWindow(window);
		window = NULL;
	}
	last_gl = gl;

	if(renderer) SDL_DestroyRenderer(renderer);
	if(texture)  SDL_DestroyTexture(texture);
	renderer = NULL;
	texture = NULL;

	if(window)
	{
		if(savedata.fullscreen)
		{
#ifdef DARWIN
			darwin_remember_windowed_bounds();
			darwin_apply_pseudo_fullscreen();
#else
			SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP);
#endif
		}
		else
		{
#ifndef WIN // hiding and showing the window is problematic on Windows
			if(SDL_GetWindowFlags(window) & (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP))
				SDL_HideWindow(window);
#endif
#ifdef DARWIN
			darwin_restore_windowed_mode(w, h);
#else
			SDL_SetWindowFullscreen(window, 0);
			SDL_SetWindowSize(window, w, h);
			SDL_SetWindowPosition(window, last_x, last_y);
			SDL_ShowWindow(window);
#endif
		}
	}
	else
	{
#ifdef DARWIN
		if(savedata.fullscreen)
		{
			SDL_Rect bounds = {0};
			darwin_get_display_bounds(&bounds);
			create_x = bounds.x;
			create_y = bounds.y;
			create_w = bounds.w;
			create_h = bounds.h;
		}
#endif
		window = SDL_CreateWindow(windowTitle, create_x, create_y, create_w, create_h, flags);
		if(!window)
		{
			printf("Error: failed to create window: %s\n", SDL_GetError());
			return 0;
		}
		
		// Kratus (11-2022) Disabled the native OpenBOR icon
		// SDL_Surface* icon = (SDL_Surface*)pngToSurface((void*)openbor_icon_32x32_png.data);
		// SDL_SetWindowIcon(window, icon);
		// SDL_FreeSurface(icon);
		if(!savedata.fullscreen) SDL_GetWindowPosition(window, &last_x, &last_y);
#ifdef DARWIN
		if(savedata.fullscreen)
		{
			SDL_SetWindowBordered(window, SDL_FALSE);
			SDL_SetWindowResizable(window, SDL_FALSE);
			SDL_SetWindowPosition(window, create_x, create_y);
			SDL_SetWindowSize(window, create_w, create_h);
		}
#endif
	}

	if(!gl)
	{
		renderer = SDL_CreateRenderer(window, -1, savedata.vsync ? SDL_RENDERER_PRESENTVSYNC : 0);
		if(!renderer)
		{
			printf("Error: failed to create renderer: %s\n", SDL_GetError());
			return 0;
		}
	}

#ifdef DARWIN
	if(window)
	{
		if(savedata.fullscreen)
		{
			darwin_apply_pseudo_fullscreen();
		}
		else
		{
			darwin_remember_windowed_bounds();
		}
	}
#endif

	return 1;
}

int video_set_mode(s_videomodes videomodes)
{
	stored_videomodes = videomodes;
	yuv_mode = 0;

	if(videomodes.hRes==0 && videomodes.vRes==0)
	{
		Term_Gfx();
		return 0;
	}

	videomodes = setupPreBlitProcessing(videomodes);

	// 8-bit color should be transparently converted to 32-bit
	assert(videomodes.pixel == 2 || videomodes.pixel == 4);

	// try OpenGL initialization first
#ifdef DARWIN
	savedata.usegl = 0;
#endif
	if(savedata.usegl && video_gl_set_mode(videomodes)) return 1;
	else opengl = 0;

	if(!SetVideoMode(videomodes.hRes * videomodes.hScale,
	                 videomodes.vRes * videomodes.vScale,
	                 videomodes.pixel * 8, false))
	{
		return 0;
	}

	if(savedata.hwfilter ||
	   (videomodes.hScale == 1 && videomodes.vScale == 1 && !savedata.fullscreen))
		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");
	else
		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");

	texture = SDL_CreateTexture(renderer,
	                            pixelformats[videomodes.pixel-1],
	                            SDL_TEXTUREACCESS_STREAMING,
	                            videomodes.hRes, videomodes.vRes);

	SDL_ShowCursor(SDL_DISABLE);
	SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
	video_stretch(savedata.stretch);

	return 1;
}

void video_fullscreen_flip()
{
	int restore_yuv = yuv_mode;
	savedata.fullscreen ^= 1;
	if(window) video_set_mode(stored_videomodes);
	if(restore_yuv) video_setup_yuv_overlay(&stored_yuv_mode);
}

void blit()
{
	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
	SDL_RenderClear(renderer);
	SDL_RenderCopy(renderer, texture, NULL, NULL);

	if (brightness > 0)
		SDL_SetRenderDrawColor(renderer, 255, 255, 255, brightness-1);
	else if (brightness < 0)
		SDL_SetRenderDrawColor(renderer, 0, 0, 0, (-brightness)-1);
	SDL_RenderFillRect(renderer, NULL);

	SDL_RenderPresent(renderer);
}

int video_copy_screen(s_screen* src)
{
	// do any needed scaling and color conversion
	s_videosurface *surface = getVideoSurface(src);

	if(opengl) return video_gl_copy_screen(surface);

	SDL_UpdateTexture(texture, NULL, surface->data, surface->pitch);
	blit();

	// Kratus (01-2023) Added a FPS limit option in the video settings
	#if WIN || LINUX
	if(savedata.fpslimit){SDL_framerateDelay(&framerate_manager);}

	#endif

	return 1;
}

void video_clearscreen()
{
	if(opengl) { video_gl_clearscreen(); return; }

	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
	SDL_RenderClear(renderer);
	SDL_RenderPresent(renderer);
}

void video_stretch(int enable)
{
	int effective_stretch;
	stretch = enable;
	effective_stretch = stretch;
#ifdef DARWIN
	if(savedata.fullscreen)
	{
		effective_stretch = 1;
	}
#endif
	stretch = effective_stretch;
	if(window && !opengl)
	{
		if(effective_stretch)
			SDL_RenderSetLogicalSize(renderer, 0, 0);
		else
			SDL_RenderSetLogicalSize(renderer, stored_videomodes.hRes, stored_videomodes.vRes);
	}
}

void video_set_color_correction(int gm, int br)
{
	brightness = br;
	if(opengl) video_gl_set_color_correction(gm, br);
}

int video_setup_yuv_overlay(const yuv_video_mode *mode)
{
	stored_yuv_mode = *mode;
	yuv_mode = 1;
	if(opengl) return video_gl_setup_yuv_overlay(mode);

	SDL_DestroyTexture(texture);
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
	texture = SDL_CreateTexture(renderer,
	                            SDL_PIXELFORMAT_YV12,
	                            SDL_TEXTUREACCESS_STREAMING,
	                            mode->width, mode->height);
	if(!stretch)
		SDL_RenderSetLogicalSize(renderer, mode->display_width, mode->display_height);
	return texture ? 1 : 0;
}

int video_prepare_yuv_frame(yuv_frame *src)
{
	if(opengl) return video_gl_prepare_yuv_frame(src);

	SDL_UpdateYUVTexture(texture, NULL, src->lum, stored_yuv_mode.width,
	        src->cr, stored_yuv_mode.width/2, src->cb, stored_yuv_mode.width/2);
	return 1;
}

int video_display_yuv_frame(void)
{
	if(opengl) return video_gl_display_yuv_frame();

	blit();
	return 1;
}

void vga_vwait(void)
{
	static int prevtick = 0;
	int now = SDL_GetTicks();
	int wait = 1000/60 - (now - prevtick);
	if (wait>0)
	{
		SDL_Delay(wait);
	}
	else SDL_Delay(1);
	prevtick = now;
}

#endif
