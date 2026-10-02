/*
 * OpenBOR - http://www.chronocrash.com
 * -----------------------------------------------------------------------
 * All rights reserved, see LICENSE in OpenBOR root for details.
 *
 * Copyright (c)  OpenBOR Team
 */

#ifdef OB_METAL

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#include <math.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "SDL.h"
#include "SDL_metal.h"
#include "SDL_syswm.h"
#include "metal.h"

typedef struct
{
	float position[2];
	float texcoord[2];
} ob_metal_vertex;

typedef struct
{
	uint32_t shaderMode;
	float textureWidth;
	float textureHeight;
	float outputWidth;
	float outputHeight;
} ob_metal_uniforms;

static SDL_MetalView metal_view = NULL;
static id<MTLDevice> metal_device = nil;
static id<MTLCommandQueue> metal_queue = nil;
static id<MTLRenderPipelineState> metal_pipeline = nil;
static id<MTLSamplerState> metal_sampler_nearest = nil;
static id<MTLSamplerState> metal_sampler_linear = nil;
static id<MTLTexture> metal_texture = nil;
static CAMetalLayer *metal_layer = nil;
static uint8_t *metal_upload_buffer = NULL;
static size_t metal_upload_buffer_size = 0;
static int metal_width = 0;
static int metal_height = 0;
static int metal_bytes_per_pixel = 0;
static int metal_shader_mode = 0;
static char metal_last_error[256] = "Metal backend probe not run yet";
static const void *ob_window_button_handler_key = &ob_window_button_handler_key;

@interface OBWindowButtonHandler : NSObject
{
	NSRect restoreFrame;
	BOOL hasRestoreFrame;
}
- (void)handleZoom:(id)sender;
@end

@implementation OBWindowButtonHandler
- (void)handleZoom:(id)sender
{
	NSWindow *window = nil;
	NSScreen *screen = nil;
	NSRect visibleFrame;
	NSRect currentFrame;

	if(![sender isKindOfClass:[NSButton class]]) return;
	window = [(NSButton *)sender window];
	if(window == nil) return;

	screen = [window screen];
	if(screen == nil) screen = [NSScreen mainScreen];
	if(screen == nil) return;

	visibleFrame = [screen visibleFrame];
	currentFrame = [window frame];

	if(!hasRestoreFrame ||
	   fabs(currentFrame.origin.x - visibleFrame.origin.x) > 2.0 ||
	   fabs(currentFrame.origin.y - visibleFrame.origin.y) > 2.0 ||
	   fabs(currentFrame.size.width - visibleFrame.size.width) > 2.0 ||
	   fabs(currentFrame.size.height - visibleFrame.size.height) > 2.0)
	{
		restoreFrame = currentFrame;
		hasRestoreFrame = YES;
		[window setFrame:visibleFrame display:YES animate:YES];
	}
	else if(hasRestoreFrame)
	{
		[window setFrame:restoreFrame display:YES animate:YES];
	}
}
@end

static NSString *metal_shader_source =
@"#include <metal_stdlib>\n"
@"using namespace metal;\n"
@"struct VertexIn { float2 position; float2 texcoord; };\n"
@"struct VertexOut { float4 position [[position]]; float2 texcoord; };\n"
@"vertex VertexOut ob_vertex(const device VertexIn *vertices [[buffer(0)]], uint vid [[vertex_id]]) {\n"
@"    VertexOut out;\n"
@"    out.position = float4(vertices[vid].position, 0.0, 1.0);\n"
@"    out.texcoord = vertices[vid].texcoord;\n"
@"    return out;\n"
@"}\n"
@"struct Uniforms { uint shaderMode; float textureWidth; float textureHeight; float outputWidth; float outputHeight; };\n"
@"fragment float4 ob_fragment(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]], constant Uniforms& uniforms [[buffer(0)]]) {\n"
@"    float2 uv = in.texcoord;\n"
@"    float4 color = tex.sample(samp, uv);\n"
@"    float scanPhase = uv.y * uniforms.textureHeight * 3.14159265;\n"
@"    float maskPhase = uv.x * uniforms.textureWidth * 6.28318530;\n"
@"    if (uniforms.shaderMode == 1) {\n"
@"        float scan = 0.82 + 0.18 * sin(scanPhase);\n"
@"        color.rgb *= scan;\n"
@"    } else if (uniforms.shaderMode == 2) {\n"
@"        float2 centered = uv * 2.0 - 1.0;\n"
@"        float vignette = 1.0 - dot(centered * 0.42, centered * 0.42);\n"
@"        vignette = clamp(vignette, 0.72, 1.0);\n"
@"        float scan = 0.84 + 0.16 * sin(scanPhase);\n"
@"        float mask = 0.94 + 0.06 * sin(maskPhase);\n"
@"        color.rgb *= vignette * scan;\n"
@"        color.r *= mask;\n"
@"        color.b *= (2.0 - mask) * 0.98;\n"
@"    }\n"
@"    return color;\n"
@"}\n";

static void metal_set_error(const char *message)
{
	if(!message) message = "Unknown Metal error";
	SDL_strlcpy(metal_last_error, message, sizeof(metal_last_error));
}

static void metal_refresh_shader_mode(void)
{
	const char *shader = getenv("OPENBOR_METAL_SHADER");

	metal_shader_mode = 0;
	if(!shader || !shader[0]) return;
	if(strcmp(shader, "scanlines") == 0) metal_shader_mode = 1;
	else if(strcmp(shader, "crt-lite") == 0) metal_shader_mode = 2;
}

static int metal_build_pipeline(void)
{
	id<MTLLibrary> library = nil;
	id<MTLFunction> vertex_function = nil;
	id<MTLFunction> fragment_function = nil;
	MTLRenderPipelineDescriptor *descriptor = nil;
	NSError *error = nil;
	MTLSamplerDescriptor *sampler_descriptor = nil;

	library = [metal_device newLibraryWithSource:metal_shader_source options:nil error:&error];
	if(library == nil)
	{
		metal_set_error(error ? error.localizedDescription.UTF8String : "Failed to compile Metal shader library");
		return 0;
	}

	vertex_function = [library newFunctionWithName:@"ob_vertex"];
	fragment_function = [library newFunctionWithName:@"ob_fragment"];
	if(vertex_function == nil || fragment_function == nil)
	{
		metal_set_error("Failed to create Metal shader functions");
		return 0;
	}

	descriptor = [[MTLRenderPipelineDescriptor alloc] init];
	descriptor.vertexFunction = vertex_function;
	descriptor.fragmentFunction = fragment_function;
	descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

	metal_pipeline = [metal_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
	if(metal_pipeline == nil)
	{
		metal_set_error(error ? error.localizedDescription.UTF8String : "Failed to create Metal pipeline");
		return 0;
	}

	sampler_descriptor = [[MTLSamplerDescriptor alloc] init];
	sampler_descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
	sampler_descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
	sampler_descriptor.minFilter = MTLSamplerMinMagFilterNearest;
	sampler_descriptor.magFilter = MTLSamplerMinMagFilterNearest;
	metal_sampler_nearest = [metal_device newSamplerStateWithDescriptor:sampler_descriptor];

	sampler_descriptor.minFilter = MTLSamplerMinMagFilterLinear;
	sampler_descriptor.magFilter = MTLSamplerMinMagFilterLinear;
	metal_sampler_linear = [metal_device newSamplerStateWithDescriptor:sampler_descriptor];

	metal_set_error("Metal pipeline ready");
	return 1;
}

static int metal_create_texture(int width, int height, int bytes_per_pixel)
{
	MTLTextureDescriptor *descriptor = nil;

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
	descriptor.usage = MTLTextureUsageShaderRead;
#if TARGET_OS_OSX
	descriptor.storageMode = MTLStorageModeManaged;
#endif
	metal_texture = [metal_device newTextureWithDescriptor:descriptor];
	if(metal_texture == nil)
	{
		metal_set_error("Failed to create Metal texture");
		return 0;
	}

	metal_width = width;
	metal_height = height;
	metal_bytes_per_pixel = bytes_per_pixel;
	return 1;
}

static int metal_ensure_upload_buffer(int width, int height)
{
	size_t needed_size = (size_t)width * (size_t)height * 4;

	if(metal_upload_buffer_size >= needed_size && metal_upload_buffer != NULL)
	{
		return 1;
	}

	free(metal_upload_buffer);
	metal_upload_buffer = malloc(needed_size);
	if(metal_upload_buffer == NULL)
	{
		metal_upload_buffer_size = 0;
		metal_set_error("Failed to allocate Metal upload buffer");
		return 0;
	}

	metal_upload_buffer_size = needed_size;
	return 1;
}

static void metal_convert_565_to_bgra8(const uint16_t *source, int pitch, int width, int height)
{
	int x, y;

	for(y = 0; y < height; y++)
	{
		const uint16_t *src_row = (const uint16_t *)((const uint8_t *)source + (size_t)y * (size_t)pitch);
		uint8_t *dst_row = metal_upload_buffer + ((size_t)y * (size_t)width * 4);
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

static void metal_convert_rgba_to_bgra8(const uint8_t *source, int pitch, int width, int height)
{
	int x, y;

	for(y = 0; y < height; y++)
	{
		const uint8_t *src_row = source + ((size_t)y * (size_t)pitch);
		uint8_t *dst_row = metal_upload_buffer + ((size_t)y * (size_t)width * 4);
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

static void metal_update_drawable_size(SDL_Window *window)
{
	int width = 0;
	int height = 0;

	if(!window || metal_layer == nil) return;
	SDL_Metal_GetDrawableSize(window, &width, &height);
	if(width <= 0 || height <= 0) return;
	metal_layer.drawableSize = CGSizeMake((CGFloat)width, (CGFloat)height);
}

void video_metal_configure_darwin_window(SDL_Window *window)
{
	SDL_SysWMinfo info;
	NSWindow *nswindow = nil;
	NSButton *zoom_button = nil;
	OBWindowButtonHandler *handler = nil;

	if(!window) return;

	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info)) return;
	if(info.subsystem != SDL_SYSWM_COCOA) return;

	nswindow = info.info.cocoa.window;
	if(nswindow == nil) return;

	/* Disable native macOS fullscreen spaces behavior for this SDL window.
	   We manage fullscreen ourselves with a borderless pseudo-fullscreen path. */
	if([nswindow respondsToSelector:@selector(setCollectionBehavior:)])
	{
		NSWindowCollectionBehavior behavior = [nswindow collectionBehavior];
		behavior &= ~NSWindowCollectionBehaviorFullScreenPrimary;
		behavior &= ~NSWindowCollectionBehaviorFullScreenAuxiliary;
		[nswindow setCollectionBehavior:behavior];
	}

	zoom_button = [nswindow standardWindowButton:NSWindowZoomButton];
	if(zoom_button != nil)
	{
		handler = objc_getAssociatedObject(nswindow, ob_window_button_handler_key);
		if(handler == nil)
		{
			handler = [[OBWindowButtonHandler alloc] init];
			objc_setAssociatedObject(nswindow, ob_window_button_handler_key, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		[zoom_button setEnabled:YES];
		[zoom_button setTarget:handler];
		[zoom_button setAction:@selector(handleZoom:)];
	}
}

int video_metal_get_darwin_window_frame(SDL_Window *window, int *x, int *y, int *w, int *h)
{
	SDL_SysWMinfo info;
	NSWindow *nswindow = nil;
	NSRect frame;

	if(!window) return 0;

	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info)) return 0;
	if(info.subsystem != SDL_SYSWM_COCOA) return 0;

	nswindow = info.info.cocoa.window;
	if(nswindow == nil) return 0;

	frame = [nswindow frame];
	if(x) *x = (int)frame.origin.x;
	if(y) *y = (int)frame.origin.y;
	if(w) *w = (int)frame.size.width;
	if(h) *h = (int)frame.size.height;
	return 1;
}

int video_metal_set_darwin_window_frame(SDL_Window *window, int x, int y, int w, int h)
{
	SDL_SysWMinfo info;
	NSWindow *nswindow = nil;
	NSRect frame;

	if(!window) return 0;

	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info)) return 0;
	if(info.subsystem != SDL_SYSWM_COCOA) return 0;

	nswindow = info.info.cocoa.window;
	if(nswindow == nil) return 0;

	frame = NSMakeRect((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
	[nswindow setFrame:frame display:YES];
	[nswindow makeKeyAndOrderFront:nil];
	dispatch_async(dispatch_get_main_queue(), ^{
		[nswindow setFrame:frame display:YES];
		[nswindow makeKeyAndOrderFront:nil];
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[nswindow setFrame:frame display:YES];
		[nswindow makeKeyAndOrderFront:nil];
	});
	return 1;
}

int video_metal_get_darwin_visible_frame(SDL_Window *window, int *x, int *y, int *w, int *h)
{
	SDL_SysWMinfo info;
	NSWindow *nswindow = nil;
	NSScreen *screen = nil;
	NSRect frame;

	if(!window) return 0;

	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info)) return 0;
	if(info.subsystem != SDL_SYSWM_COCOA) return 0;

	nswindow = info.info.cocoa.window;
	if(nswindow == nil) return 0;

	screen = [nswindow screen];
	if(screen == nil) screen = [NSScreen mainScreen];
	if(screen == nil) return 0;

	frame = [screen visibleFrame];
	if(x) *x = (int)frame.origin.x;
	if(y) *y = (int)frame.origin.y;
	if(w) *w = (int)frame.size.width;
	if(h) *h = (int)frame.size.height;
	return 1;
}

void video_metal_hide_darwin_window(SDL_Window *window)
{
	SDL_SysWMinfo info;
	NSWindow *nswindow = nil;

	if(!window) return;

	SDL_VERSION(&info.version);
	if(!SDL_GetWindowWMInfo(window, &info)) return;
	if(info.subsystem != SDL_SYSWM_COCOA) return;

	nswindow = info.info.cocoa.window;
	if(nswindow == nil) return;

	[nswindow orderOut:nil];
}

int video_metal_available(void)
{
	metal_device = MTLCreateSystemDefaultDevice();
	if(metal_device == nil)
	{
		metal_set_error("No Metal device available");
		return 0;
	}
	metal_set_error("Metal device available");
	return 1;
}

int video_metal_set_mode(SDL_Window *window, int width, int height, int bytes_per_pixel, int vsync)
{
	(void)vsync;

	if(!window)
	{
		metal_set_error("SDL window is not available");
		return 0;
	}

	if(!video_metal_available()) return 0;

	if(metal_view == NULL)
	{
		metal_view = SDL_Metal_CreateView(window);
		if(!metal_view)
		{
			metal_set_error(SDL_GetError());
			return 0;
		}
	}

	metal_layer = (__bridge CAMetalLayer *)SDL_Metal_GetLayer(metal_view);
	if(metal_layer == nil)
	{
		metal_set_error("Failed to obtain CAMetalLayer");
		return 0;
	}

	metal_layer.device = metal_device;
	metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	metal_layer.framebufferOnly = YES;
	metal_layer.opaque = YES;
	metal_layer.displaySyncEnabled = vsync ? YES : NO;
	metal_update_drawable_size(window);
	metal_refresh_shader_mode();

	if(metal_queue == nil)
	{
		metal_queue = [metal_device newCommandQueue];
		if(metal_queue == nil)
		{
			metal_set_error("Failed to create Metal command queue");
			return 0;
		}
	}

	if(metal_pipeline == nil && !metal_build_pipeline())
	{
		return 0;
	}

	if(metal_texture == nil || metal_width != width || metal_height != height || metal_bytes_per_pixel != bytes_per_pixel)
	{
		metal_texture = nil;
		if(!metal_create_texture(width, height, bytes_per_pixel))
		{
			return 0;
		}
	}

	metal_set_error("Metal backend initialized");
	return 1;
}

static void metal_fill_vertices(ob_metal_vertex *vertices, CGSize drawable_size, int stretch)
{
	float target_width = (float)drawable_size.width;
	float target_height = (float)drawable_size.height;
	float sx = 1.0f;
	float sy = 1.0f;

	if(!stretch && metal_width > 0 && metal_height > 0 && target_width > 0.0f && target_height > 0.0f)
	{
		float scale = fminf(target_width / (float)metal_width, target_height / (float)metal_height);
		float draw_width = (float)metal_width * scale;
		float draw_height = (float)metal_height * scale;
		sx = draw_width / target_width;
		sy = draw_height / target_height;
	}

	vertices[0] = (ob_metal_vertex){{-sx, -sy}, {0.0f, 1.0f}};
	vertices[1] = (ob_metal_vertex){{ sx, -sy}, {1.0f, 1.0f}};
	vertices[2] = (ob_metal_vertex){{-sx,  sy}, {0.0f, 0.0f}};
	vertices[3] = (ob_metal_vertex){{ sx,  sy}, {1.0f, 0.0f}};
}

int video_metal_copy_frame(const void *data, int width, int height, int pitch, int bytes_per_pixel, int stretch, int smooth)
{
	id<CAMetalDrawable> drawable = nil;
	id<MTLCommandBuffer> command_buffer = nil;
	MTLRenderPassDescriptor *render_pass = nil;
	id<MTLRenderCommandEncoder> encoder = nil;
	ob_metal_vertex vertices[4];
	MTLRegion region;
	CGSize drawable_size;
	int upload_pitch = width * 4;
	ob_metal_uniforms uniforms;

	if(data == NULL || metal_layer == nil || metal_texture == nil || metal_pipeline == nil || metal_queue == nil)
	{
		metal_set_error("Metal backend not ready for frame upload");
		return 0;
	}

	if(width != metal_width || height != metal_height)
	{
		if(!metal_create_texture(width, height, metal_bytes_per_pixel))
		{
			return 0;
		}
	}

	region = MTLRegionMake2D(0, 0, width, height);
	if(bytes_per_pixel != 2 && bytes_per_pixel != 4)
	{
		metal_set_error("Unsupported source pixel size for Metal upload");
		return 0;
	}

	if(!metal_ensure_upload_buffer(width, height))
	{
		return 0;
	}

	if(bytes_per_pixel == 2)
	{
		metal_convert_565_to_bgra8((const uint16_t *)data, pitch, width, height);
	}
	else
	{
		metal_convert_rgba_to_bgra8((const uint8_t *)data, pitch, width, height);
	}

	[metal_texture replaceRegion:region mipmapLevel:0 withBytes:metal_upload_buffer bytesPerRow:upload_pitch];

	drawable = [metal_layer nextDrawable];
	if(drawable == nil)
	{
		metal_set_error("Metal drawable unavailable");
		return 0;
	}

	command_buffer = [metal_queue commandBuffer];
	render_pass = [MTLRenderPassDescriptor renderPassDescriptor];
	render_pass.colorAttachments[0].texture = drawable.texture;
	render_pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	render_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	render_pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

	encoder = [command_buffer renderCommandEncoderWithDescriptor:render_pass];
	[encoder setRenderPipelineState:metal_pipeline];
	[encoder setFragmentTexture:metal_texture atIndex:0];
	[encoder setFragmentSamplerState:(smooth ? metal_sampler_linear : metal_sampler_nearest) atIndex:0];

	drawable_size = metal_layer.drawableSize;
	metal_fill_vertices(vertices, drawable_size, stretch);
	uniforms.shaderMode = (uint32_t)metal_shader_mode;
	uniforms.textureWidth = (float)width;
	uniforms.textureHeight = (float)height;
	uniforms.outputWidth = (float)drawable_size.width;
	uniforms.outputHeight = (float)drawable_size.height;
	[encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
	[encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	[encoder endEncoding];

	[command_buffer presentDrawable:drawable];
	[command_buffer commit];

	metal_set_error("Metal frame presented");
	return 1;
}

void video_metal_clear(void)
{
	id<CAMetalDrawable> drawable = nil;
	id<MTLCommandBuffer> command_buffer = nil;
	MTLRenderPassDescriptor *render_pass = nil;

	if(metal_layer == nil || metal_queue == nil) return;

	drawable = [metal_layer nextDrawable];
	if(drawable == nil) return;

	command_buffer = [metal_queue commandBuffer];
	render_pass = [MTLRenderPassDescriptor renderPassDescriptor];
	render_pass.colorAttachments[0].texture = drawable.texture;
	render_pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	render_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	render_pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

	id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:render_pass];
	[encoder endEncoding];
	[command_buffer presentDrawable:drawable];
	[command_buffer commit];
}

void video_metal_shutdown(void)
{
	metal_texture = nil;
	metal_pipeline = nil;
	metal_sampler_nearest = nil;
	metal_sampler_linear = nil;
	metal_queue = nil;
	metal_layer = nil;
	free(metal_upload_buffer);
	metal_upload_buffer = NULL;
	metal_upload_buffer_size = 0;
	if(metal_view != NULL)
	{
		SDL_Metal_DestroyView(metal_view);
		metal_view = NULL;
	}
	metal_width = 0;
	metal_height = 0;
	metal_bytes_per_pixel = 0;
	metal_set_error("Metal backend shut down");
}

const char *video_metal_last_error(void)
{
	return metal_last_error;
}

#endif
