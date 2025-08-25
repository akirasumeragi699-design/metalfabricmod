.PHONY: all build clean

# Thư mục
RES_DIR := src/main/resources
OUT_DIR := out
DIST_DIR := dist
BUILD_CLASSES := build/classes/java/main
JAR_NAME := MetalFabricMod.jar
MANIFEST := myManifest.mf

all: build

build:
	@echo "Preparing output directory..."
	@mkdir -p $(OUT_DIR)/classes

	@echo "Copying compiled classes from Gradle build..."
	@if [ -d "$(BUILD_CLASSES)" ]; then cp -r $(BUILD_CLASSES)/* $(OUT_DIR)/classes/; fi

	@echo "Copying resources..."
	@if [ -d "$(RES_DIR)" ]; then cp -r $(RES_DIR)/* $(OUT_DIR)/classes/; fi

	@echo "Copying metalbridge.dylib..."
	@if [ -f "metalbackend/metalbridge.dylib" ]; then cp metalbackend/metalbridge.dylib $(OUT_DIR)/classes/; fi

	@echo "Packaging JAR..."
	@mkdir -p $(DIST_DIR)
	@jar cfm $(DIST_DIR)/$(JAR_NAME) $(MANIFEST) -C $(OUT_DIR)/classes .

clean:
	@echo "Cleaning output and distribution directories..."
	@rm -rf $(OUT_DIR) $(DIST_DIR)
