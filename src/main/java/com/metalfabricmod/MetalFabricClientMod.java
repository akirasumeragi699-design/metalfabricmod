package com.metalfabricmod;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.rendering.v1.WorldRenderEvents;
import net.minecraft.client.MinecraftClient;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.FileOutputStream;
import java.io.File;
import java.io.IOException;

import org.lwjgl.glfw.*;
import org.lwjgl.opengl.*;
import static org.lwjgl.glfw.GLFW.*;
import static org.lwjgl.opengl.GL11.*;

@Environment(EnvType.CLIENT)
public class MetalFabricClientMod implements ClientModInitializer {

    private static volatile boolean initialized = false;
    private static volatile boolean initFailed = false;

    public static boolean rayTracingEnabled = false;
    public static int metalFxMode = 0;

    static {
        try {
            InputStream libStream = MetalFabricClientMod.class.getResourceAsStream("/com/metalfabricmod/metalbridge.dylib");
            if (libStream == null) throw new RuntimeException("Resource not found!");

            File tempLib = File.createTempFile("metalbridge", ".dylib");
            tempLib.deleteOnExit();

            try (OutputStream out = new FileOutputStream(tempLib)) {
                libStream.transferTo(out);
            }

            System.load(tempLib.getAbsolutePath());
            System.out.println("[MetalBridge] Loaded dylib: " + tempLib.getAbsolutePath());
        } catch (UnsatisfiedLinkError | IOException e) {
            System.err.println("[MetalBridge] Failed to load dylib: " + e.getMessage());
        }
    }
    @Override
    public void onInitializeClient() {
        // Start GLFW window for Metal controls
        new Thread(() -> new MetalControlWindow().run()).start();

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            if (!initialized && !initFailed) {
                try {
                    applyMetalSettings();
                    initialized = true;
                    System.out.println("[MetalBridge] Native initialized!");
                } catch (Throwable t) {
                    initFailed = true;
                    System.err.println("[MetalBridge] Native init failed: " + t.getMessage());
                }
            }
        });

        WorldRenderEvents.AFTER_TRANSLUCENT.register(context -> {
            if (!initialized || initFailed) return;

            MinecraftClient mc = MinecraftClient.getInstance();
            int w = mc.getWindow().getFramebufferWidth();
            int h = mc.getWindow().getFramebufferHeight();
            int currentTex = 0; // FBO hiện tại nếu bạn dùng riêng
            int processedTex = MetalBridge.processGameTexture(currentTex, w, h);

            // glBindTexture(GL_TEXTURE_2D, processedTex);
        });
    }

    private static void applyMetalSettings() {
        float scale = switch (metalFxMode) {
            case 1 -> 0.75f;
            case 2 -> 0.5f;
            default -> 1f;
        };
        MetalBridge.init(rayTracingEnabled, scale, scale, metalFxMode);
    }

    public static class MetalBridge {
        public static native void init(boolean rayTracing, float scaleW, float scaleH, int quality);
        public static native int processGameTexture(int textureId, int width, int height);
        public static native void shutdown();
        public static native void setRayTracingEnabled(boolean enabled);
        public static native void setMetalFxMode(float scaleW, float scaleH, int quality);
    }

    public static class MetalControlWindow {

        private long window;

        public void run() {
            init();
            loop();
            glfwDestroyWindow(window);
            glfwTerminate();
        }

        private void init() {
            if (!glfwInit()) throw new IllegalStateException("Unable to initialize GLFW");

            glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
            window = glfwCreateWindow(300, 200, "Metal Control Panel", 0, 0);
            if (window == 0) throw new RuntimeException("Failed to create GLFW window");

            glfwMakeContextCurrent(window);
            GL.createCapabilities();

            glfwSetKeyCallback(window, (win, key, scancode, action, mods) -> {
                if (action == GLFW_PRESS) {
                    if (key == GLFW_KEY_R) {
                        MetalFabricClientMod.rayTracingEnabled = !MetalFabricClientMod.rayTracingEnabled;
                        MetalBridge.setRayTracingEnabled(MetalFabricClientMod.rayTracingEnabled);
                        System.out.println("Ray Tracing: " + (MetalFabricClientMod.rayTracingEnabled ? "ON" : "OFF"));
                    }
                    if (key == GLFW_KEY_M) {
                        MetalFabricClientMod.metalFxMode = (MetalFabricClientMod.metalFxMode + 1) % 3;
                        float scale = switch (MetalFabricClientMod.metalFxMode) {
                            case 1 -> 0.75f;
                            case 2 -> 0.5f;
                            default -> 1f;
                        };
                        MetalBridge.setMetalFxMode(scale, scale, MetalFabricClientMod.metalFxMode);
                        System.out.println("MetalFX Mode: " + modeName());
                    }
                }
            });
        }

        private void loop() {
            while (!glfwWindowShouldClose(window)) {
                glClearColor(0.2f, 0.2f, 0.2f, 1f);
                glClear(GL_COLOR_BUFFER_BIT);

                // Có thể vẽ nút OpenGL thật nếu muốn sau này

                glfwSwapBuffers(window);
                glfwPollEvents();
            }
        }

        private static String modeName() {
            return switch (MetalFabricClientMod.metalFxMode) {
                case 1 -> "Low";
                case 2 -> "High";
                default -> "Off";
            };
        }
    }
}
