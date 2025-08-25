# MetalFabricMod

**MetalFabricMod** is a Java mod built using Gradle and a Makefile for packaging into a JAR.

## Requirements

- **Java 17 or higher**    

## Project Structure

- `src/main/java/com/metalfabricmod/` → Java source code  
- `src/main/resources/` → Resources (textures, configs, etc.)  
- `metalbackend/` → Native library (`metalbridge.dylib`)  
- `build/` → Gradle build output  
- `out/` → Makefile temporary output  
- `dist/` → Packaged JAR location  
- `myManifest.mf` → Manifest file for the JAR  

## Build Instructions

### 1. Build with Makefile

The Makefile performs the following steps:

1. Copy compiled classes from Gradle build (`build/classes/java/main`)  
2. Copy resources from `src/main/resources`  
3. Copy `metalbridge.dylib` if it exists  
4. Package everything into `dist/MetalFabricMod.jar` using `myManifest.mf`  

Run the build with:

```
make all
```

The resulting JAR file will be located at `dist/MetalFabricMod.jar`.

### 2. Clean

To remove temporary and distribution files, run:

```
make clean
```

This deletes the `out/` and `dist/` directories.

## Notes

- Ensure the Gradle build succeeds before running `make all`.  
- Make sure `myManifest.mf` exists for proper JAR packaging.  
- Place any new native libraries in `metalbackend/` so the Makefile includes them automatically.
