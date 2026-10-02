/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 */

#ifdef OB_METAL

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "v2bridge.h"

static IOSurfaceRef bridge_surface = NULL;
static char bridge_frameinfo_path[1024] = {0};
static char bridge_frame_path[1024] = {0};
static char bridge_log_path[1024] = {0};
static int bridge_frame_fd = -1;
static uint8_t *bridge_frame_mapping = NULL;
static size_t bridge_frame_mapping_size = 0;
static int bridge_active = 0;
static int bridge_hosted = 0;
static int bridge_publish_count = 0;
static int bridge_last_frame_width = 0;
static int bridge_last_frame_height = 0;

static void bridge_log(const char *message)
{
	FILE *file = NULL;

	if(bridge_log_path[0] == '\0' || message == NULL) return;

	file = fopen(bridge_log_path, "a");
	if(file == NULL) return;
	fprintf(file, "%s\n", message);
	fclose(file);
}

static void bridge_logf(const char *format, ...)
{
	FILE *file = NULL;
	va_list args;

	if(bridge_log_path[0] == '\0' || format == NULL) return;

	file = fopen(bridge_log_path, "a");
	if(file == NULL) return;
	va_start(args, format);
	vfprintf(file, format, args);
	va_end(args);
	fprintf(file, "\n");
	fclose(file);
}

static void bridge_convert_565_to_bgra8(const uint16_t *source, int pitch, int width, int height, uint8_t *destination, size_t destination_pitch)
{
	int x, y;

	for(y = 0; y < height; y++)
	{
		const uint16_t *src_row = (const uint16_t *)((const uint8_t *)source + ((size_t)y * (size_t)pitch));
		uint8_t *dst_row = destination + ((size_t)y * destination_pitch);
		for(x = 0; x < width; x++)
		{
			uint16_t pixel = src_row[x];
			uint8_t r = (uint8_t)((pixel & 0x1F) * 255 / 31);
			uint8_t g = (uint8_t)(((pixel >> 5) & 0x3F) * 255 / 63);
			uint8_t b = (uint8_t)(((pixel >> 11) & 0x1F) * 255 / 31);
			dst_row[x * 4 + 0] = b;
			dst_row[x * 4 + 1] = g;
			dst_row[x * 4 + 2] = r;
			dst_row[x * 4 + 3] = 0xFF;
		}
	}
}

static void bridge_convert_rgba_to_bgra8(const uint8_t *source, int pitch, int width, int height, uint8_t *destination, size_t destination_pitch)
{
	int x, y;

	for(y = 0; y < height; y++)
	{
		const uint8_t *src_row = source + ((size_t)y * (size_t)pitch);
		uint8_t *dst_row = destination + ((size_t)y * destination_pitch);
		for(x = 0; x < width; x++)
		{
			const uint8_t *src = src_row + (x * 4);
			uint8_t *dst = dst_row + (x * 4);
			dst[0] = src[2];
			dst[1] = src[1];
			dst[2] = src[0];
			dst[3] = src[3];
		}
	}
}

static void bridge_write_frame_info(int width, int height)
{
	FILE *file = NULL;

	if(!bridge_active || bridge_frameinfo_path[0] == '\0') return;

	file = fopen(bridge_frameinfo_path, "w");
	if(file == NULL) return;
	fprintf(file, "%d %d 4 BGRA8\n", width, height);
	fclose(file);
}

static void bridge_write_frame_data(const uint8_t *data, size_t size)
{
	FILE *file = NULL;

	if(bridge_frame_path[0] == '\0' || data == NULL || size == 0) return;

	file = fopen(bridge_frame_path, "wb");
	if(file == NULL) return;
	fwrite(data, 1, size, file);
	fclose(file);
}

static void bridge_close_frame_mapping(void)
{
	if(bridge_frame_mapping != NULL && bridge_frame_mapping_size > 0)
	{
		munmap(bridge_frame_mapping, bridge_frame_mapping_size);
	}
	bridge_frame_mapping = NULL;
	bridge_frame_mapping_size = 0;

	if(bridge_frame_fd >= 0)
	{
		close(bridge_frame_fd);
	}
	bridge_frame_fd = -1;
}

static int bridge_ensure_frame_mapping(size_t size)
{
	void *mapping = NULL;

	if(bridge_frame_path[0] == '\0' || size == 0)
	{
		return 0;
	}

	if(bridge_frame_mapping != NULL && bridge_frame_mapping_size == size)
	{
		return 1;
	}

	bridge_close_frame_mapping();

	bridge_frame_fd = open(bridge_frame_path, O_RDWR | O_CREAT, 0666);
	if(bridge_frame_fd < 0)
	{
		bridge_logf("Failed to open frame mapping file: %s", bridge_frame_path);
		return 0;
	}

	if(ftruncate(bridge_frame_fd, (off_t)size) != 0)
	{
		bridge_logf("Failed to size frame mapping file to %zu bytes", size);
		bridge_close_frame_mapping();
		return 0;
	}

	mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, bridge_frame_fd, 0);
	if(mapping == MAP_FAILED)
	{
		bridge_logf("Failed to mmap frame mapping file: %s", bridge_frame_path);
		bridge_close_frame_mapping();
		return 0;
	}

	bridge_frame_mapping = (uint8_t *)mapping;
	bridge_frame_mapping_size = size;
	return 1;
}

void video_v2_bridge_init(void)
{
	const char *surface_id_env = getenv("OPENBOR_V2_IOSURFACE_ID");
	const char *frameinfo_env = getenv("OPENBOR_V2_FRAMEINFO_PATH");
	const char *frame_env = getenv("OPENBOR_V2_FRAME_PATH");
	const char *log_env = getenv("OPENBOR_V2_LOG_PATH");
	const char *hosted_env = getenv("OPENBOR_V2_HOSTED");
	IOSurfaceID surface_id = 0;

	video_v2_bridge_shutdown();

	if(log_env != NULL && log_env[0] != '\0')
	{
		snprintf(bridge_log_path, sizeof(bridge_log_path), "%s", log_env);
	}
	else
	{
		bridge_log_path[0] = '\0';
	}
	bridge_log("video_v2_bridge_init()");

	if(frameinfo_env != NULL && frameinfo_env[0] != '\0')
	{
		snprintf(bridge_frameinfo_path, sizeof(bridge_frameinfo_path), "%s", frameinfo_env);
	}
	else
	{
		bridge_frameinfo_path[0] = '\0';
	}

	if(frame_env != NULL && frame_env[0] != '\0')
	{
		snprintf(bridge_frame_path, sizeof(bridge_frame_path), "%s", frame_env);
	}
	else
	{
		bridge_frame_path[0] = '\0';
	}

	bridge_hosted = (hosted_env != NULL && hosted_env[0] == '1') ? 1 : 0;

	if(surface_id_env == NULL || surface_id_env[0] == '\0')
	{
		bridge_active = (bridge_frameinfo_path[0] != '\0' || bridge_frame_path[0] != '\0');
		if(bridge_active)
		{
			bridge_logf("Bridge active without IOSurface: hosted=%d frameInfo=%s frame=%s",
			            bridge_hosted,
			            bridge_frameinfo_path[0] ? bridge_frameinfo_path : "(none)",
			            bridge_frame_path[0] ? bridge_frame_path : "(none)");
		}
		return;
	}

	surface_id = (IOSurfaceID)strtoul(surface_id_env, NULL, 10);
	if(surface_id == 0)
	{
		bridge_log("No valid OPENBOR_V2_IOSURFACE_ID");
		bridge_active = (bridge_frameinfo_path[0] != '\0' || bridge_frame_path[0] != '\0');
		return;
	}

	bridge_surface = IOSurfaceLookup(surface_id);
	if(bridge_surface == NULL)
	{
		bridge_logf("IOSurfaceLookup failed for id=%u", (unsigned int)surface_id);
		bridge_active = (bridge_frameinfo_path[0] != '\0' || bridge_frame_path[0] != '\0');
		if(bridge_active)
		{
			bridge_logf("Bridge fallback active without IOSurface: hosted=%d frameInfo=%s frame=%s",
			            bridge_hosted,
			            bridge_frameinfo_path[0] ? bridge_frameinfo_path : "(none)",
			            bridge_frame_path[0] ? bridge_frame_path : "(none)");
		}
		return;
	}
	bridge_active = 1;
	bridge_publish_count = 0;
	bridge_logf("Bridge active: hosted=%d surfaceID=%u width=%zu height=%zu frameInfo=%s",
	            bridge_hosted,
	            (unsigned int)IOSurfaceGetID(bridge_surface),
	            IOSurfaceGetWidth(bridge_surface),
	            IOSurfaceGetHeight(bridge_surface),
	            bridge_frameinfo_path[0] ? bridge_frameinfo_path : "(none)");
}

void video_v2_bridge_shutdown(void)
{
	if(bridge_surface != NULL)
	{
		CFRelease(bridge_surface);
	bridge_surface = NULL;
	}
	bridge_close_frame_mapping();
	bridge_frameinfo_path[0] = '\0';
	bridge_frame_path[0] = '\0';
	bridge_log("video_v2_bridge_shutdown()");
	bridge_active = 0;
	bridge_hosted = 0;
	bridge_publish_count = 0;
	bridge_last_frame_width = 0;
	bridge_last_frame_height = 0;
	bridge_log_path[0] = '\0';
}

int video_v2_bridge_active(void)
{
	return bridge_active;
}

int video_v2_bridge_hosted(void)
{
	return bridge_hosted;
}

void video_v2_bridge_publish(const void *data, int width, int height, int pitch, int bytes_per_pixel)
{
	size_t destination_pitch = 0;
	uint8_t *destination = NULL;
	uint8_t *scratch = NULL;
	size_t scratch_size = 0;
	int surface_width = 0;
	int surface_height = 0;
	int mirror_frame_buffer = 0;

	if(!bridge_active || data == NULL) return;
	if(width <= 0 || height <= 0) return;
	if(bytes_per_pixel != 2 && bytes_per_pixel != 4) return;

	mirror_frame_buffer = (bridge_frame_path[0] != '\0');
	if(mirror_frame_buffer)
	{
		destination_pitch = (size_t)width * 4u;
		scratch_size = destination_pitch * (size_t)height;
		scratch = (uint8_t *)malloc(scratch_size);
		if(scratch == NULL)
		{
			bridge_logf("Publish skipped: scratch allocation failed for %dx%d", width, height);
			return;
		}
		if(bytes_per_pixel == 2)
		{
			bridge_convert_565_to_bgra8((const uint16_t *)data, pitch, width, height, scratch, destination_pitch);
		}
		else
		{
			bridge_convert_rgba_to_bgra8((const uint8_t *)data, pitch, width, height, scratch, destination_pitch);
		}
	}

	if(bridge_surface != NULL)
	{
		surface_width = (int)IOSurfaceGetWidth(bridge_surface);
		surface_height = (int)IOSurfaceGetHeight(bridge_surface);
		if(width > surface_width || height > surface_height)
		{
			bridge_logf("Publish skipped: frame %dx%d bpp=%d exceeds surface %dx%d", width, height, bytes_per_pixel, surface_width, surface_height);
			return;
		}

		IOSurfaceLock(bridge_surface, 0, NULL);
		destination_pitch = IOSurfaceGetBytesPerRow(bridge_surface);
		destination = (uint8_t *)IOSurfaceGetBaseAddress(bridge_surface);
		if(destination != NULL)
		{
			if(scratch != NULL)
			{
				for(int y = 0; y < height; y++)
				{
					memcpy(destination + ((size_t)y * destination_pitch),
					       scratch + ((size_t)y * (size_t)width * 4u),
					       (size_t)width * 4u);
				}
			}
			else if(bytes_per_pixel == 2)
			{
				bridge_convert_565_to_bgra8((const uint16_t *)data, pitch, width, height, destination, destination_pitch);
			}
			else
			{
				bridge_convert_rgba_to_bgra8((const uint8_t *)data, pitch, width, height, destination, destination_pitch);
			}
		}
		IOSurfaceUnlock(bridge_surface, 0, NULL);
	}
	else if(bridge_frame_path[0] != '\0')
	{
		destination = scratch;
	}

	if(scratch != NULL)
	{
		size_t frame_size = ((size_t)width * 4u) * (size_t)height;
		if(bridge_ensure_frame_mapping(frame_size))
		{
			memcpy(bridge_frame_mapping, scratch, frame_size);
		}
		else
		{
			bridge_write_frame_data((const uint8_t *)scratch, frame_size);
		}
	}
	bridge_publish_count++;
	if(bridge_publish_count <= 3 || (bridge_publish_count % 120) == 0)
	{
		bridge_logf("Publish #%d frame=%dx%d pitch=%d bpp=%d hosted=%d",
		            bridge_publish_count,
		            width,
		            height,
		            pitch,
		            bytes_per_pixel,
		            bridge_hosted);
	}
	if(width != bridge_last_frame_width || height != bridge_last_frame_height)
	{
		bridge_write_frame_info(width, height);
		bridge_last_frame_width = width;
		bridge_last_frame_height = height;
	}
	if(scratch != NULL) free(scratch);
}

#else

#include "v2bridge.h"

void video_v2_bridge_init(void) {}
void video_v2_bridge_shutdown(void) {}
void video_v2_bridge_publish(const void *data, int width, int height, int pitch, int bytes_per_pixel)
{
	(void)data;
	(void)width;
	(void)height;
	(void)pitch;
	(void)bytes_per_pixel;
}
int video_v2_bridge_active(void) { return 0; }
int video_v2_bridge_hosted(void) { return 0; }

#endif
