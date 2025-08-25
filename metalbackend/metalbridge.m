// MetalBridge.m
// Build:
// clang -fobjc-arc -dynamiclib -framework Foundation -framework Metal -framework AppKit -framework QuartzCore -framework OpenGL -framework IOSurface -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/darwin -o metalbridge.dylib MetalBridge.m

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLCurrent.h>
#import <IOSurface/IOSurface.h>
#import <jni.h>
#import <simd/simd.h>

#ifndef GL_SILENCE_DEPRECATION
#define GL_SILENCE_DEPRECATION
#endif

// ---------- Globals ----------
static id<MTLDevice> gDevice = nil;
static id<MTLCommandQueue> gQueue = nil;
static id<MTLRenderPipelineState> gPipeline = nil;
static id<MTLBuffer> gVertexBuffer = nil;
static id<MTLTexture> gMetalTex = nil;      // Metal render target (IOSurface-backed)
static IOSurfaceRef gIOSurf = nil;
static GLuint gGLTex = 0;
static int gTexW = 512, gTexH = 512;

// Settings
static BOOL gRayTracingEnabled = NO;
static int gMetalFxMode = 0; // 0=Off,1=Quality,2=Performance
static float gFxScaleW = 1.0f, gFxScaleH = 1.0f;

// ---------- Vertex Data ----------
typedef struct { float position[2]; float color[4]; } Vertex;
static const Vertex kVertices[] = {
    { {  0.0f,  0.6f }, { 1,0,0,1 } },
    { { -0.6f, -0.6f }, { 0,1,0,1 } },
    { {  0.6f, -0.6f }, { 0,0,1,1 } },
};

// ---------- Helpers ----------
static void logMsg(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[MetalBridge] %@", s);
}

static id<MTLTexture> newMetalTextureFromIOSurface(int w, int h) {
    if (!gDevice) return nil;
    if (gIOSurf) { CFRelease(gIOSurf); gIOSurf = nil; }

    NSDictionary *props = @{
        (NSString*)kIOSurfaceWidth: @(w),
        (NSString*)kIOSurfaceHeight: @(h),
        (NSString*)kIOSurfaceBytesPerElement: @4,
        (NSString*)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
    };
    gIOSurf = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!gIOSurf) { logMsg(@"Failed to create IOSurface"); return nil; }

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [gDevice newTextureWithDescriptor:td iosurface:gIOSurf plane:0];
    if (!tex) { logMsg(@"Failed to create Metal texture from IOSurface"); CFRelease(gIOSurf); gIOSurf = nil; return nil; }

    if (gGLTex == 0) glGenTextures(1, &gGLTex);
    glBindTexture(GL_TEXTURE_2D, gGLTex);

    CGLContextObj ctx = CGLGetCurrentContext();
    if (!ctx) logMsg(@"CGL context is NULL");

    CGLTexImageIOSurface2D(ctx, GL_TEXTURE_2D, GL_RGBA, w, h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, gIOSurf, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    return tex;
}

static BOOL ensureDevice() {
    if (gDevice) return YES;
    gDevice = MTLCreateSystemDefaultDevice();
    if (!gDevice) { logMsg(@"No Metal device"); return NO; }
    gQueue = [gDevice newCommandQueue];
    return YES;
}

static void compileShaders() {
    NSError *err = nil;
    NSString *src = @"using namespace metal;"
                    "struct VertexIn { float2 pos [[attribute(0)]]; float4 col [[attribute(1)]]; };"
                    "struct VSOut { float4 pos [[position]]; float4 col; };"
                    "vertex VSOut vs_main(VertexIn vin [[stage_in]]) { VSOut o; o.pos = float4(vin.pos, 0, 1); o.col = vin.col; return o; }"
                    "fragment float4 fs_main(VSOut in [[stage_in]]) { return in.col; }";
    id<MTLLibrary> lib = [gDevice newLibraryWithSource:src options:nil error:&err];
    if (!lib) { logMsg(@"Shader compile error: %@", err); return; }
    id<MTLFunction> vfn = [lib newFunctionWithName:@"vs_main"];
    id<MTLFunction> ffn = [lib newFunctionWithName:@"fs_main"];
    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction = vfn;
    pd.fragmentFunction = ffn;
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    NSError *e2 = nil;
    gPipeline = [gDevice newRenderPipelineStateWithDescriptor:pd error:&e2];
    if (!gPipeline) logMsg(@"Pipeline error: %@", e2);
}

static void createVertexBuffer() {
    if (!gDevice) return;
    if (gVertexBuffer) return;
    gVertexBuffer = [gDevice newBufferWithBytes:kVertices length:sizeof(kVertices) options:MTLResourceStorageModeShared];
}

// ---------- JNI Exports ----------

JNIEXPORT void JNICALL Java_com_metalfabricmod_MetalBridge_init(JNIEnv *env, jclass clazz, jboolean useRT, jfloat scaleW, jfloat scaleH, jint quality) {
    @autoreleasepool {
        if (!ensureDevice()) return;
        gRayTracingEnabled = useRT;
        gFxScaleW = scaleW;
        gFxScaleH = scaleH;
        gMetalFxMode = (int)quality;
        createVertexBuffer();
        compileShaders();
        gTexW = 512; gTexH = 512;
        gMetalTex = newMetalTextureFromIOSurface(gTexW, gTexH);
        logMsg(@"Init done. RT=%d MetalFXMode=%d GLTex=%u", gRayTracingEnabled, gMetalFxMode, gGLTex);
    }
}

JNIEXPORT jint JNICALL Java_com_metalfabricmod_MetalBridge_renderFrame(JNIEnv *env, jclass clazz) {
    @autoreleasepool {
        if (!gDevice || !gQueue || !gPipeline || !gMetalTex) return 0;
        logMsg(@"Rendering frame: RT=%d, MetalFXMode=%d", gRayTracingEnabled, gMetalFxMode);

        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = gMetalTex;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.1, 0.15, 1.0);

        id<MTLCommandBuffer> cmd = [gQueue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:gPipeline];
        [enc setVertexBuffer:gVertexBuffer offset:0 atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        return (jint)gGLTex;
    }
}

JNIEXPORT void JNICALL Java_com_metalfabricmod_MetalBridge_setRayTracingEnabled(JNIEnv *env, jclass clazz, jboolean enabled) {
    gRayTracingEnabled = enabled;
    logMsg(@"RayTracing toggled: %d", gRayTracingEnabled);
}

JNIEXPORT void JNICALL Java_com_metalfabricmod_MetalBridge_setMetalFxMode(JNIEnv *env, jclass clazz, jfloat sw, jfloat sh, jint mode) {
    gFxScaleW = sw;
    gFxScaleH = sh;
    gMetalFxMode = mode;
    logMsg(@"MetalFX mode set: %d (scale %.2f x %.2f)", gMetalFxMode, gFxScaleW, gFxScaleH);
}

JNIEXPORT void JNICALL Java_com_metalfabricmod_MetalBridge_shutdown(JNIEnv *env, jclass clazz) {
    @autoreleasepool {
        if (gIOSurf) { CFRelease(gIOSurf); gIOSurf = nil; }
        if (gGLTex) { glDeleteTextures(1, &gGLTex); gGLTex = 0; }
        gMetalTex = nil; gVertexBuffer = nil; gPipeline = nil; gQueue = nil; gDevice = nil;
        logMsg(@"Shutdown complete");
    }
}
