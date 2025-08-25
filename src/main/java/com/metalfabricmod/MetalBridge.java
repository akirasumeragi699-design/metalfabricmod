package com.metalfabricmod;

public class MetalBridge {
    public static native void init(boolean rayTracing, float scaleW, float scaleH, int quality);
    public static native int processGameTexture(int textureId, int width, int height);
    public static native void shutdown();

    // NEW
    public static native void setRayTracingEnabled(boolean enabled);
    public static native void setMetalFxMode(float scaleW, float scaleH, int quality);
}
