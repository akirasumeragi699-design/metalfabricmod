OUT = metalbridge.dylib
SRC = metalbridge.m
CC = clang

JAVA_HOME = $(shell /usr/libexec/java_home -v 21)
JNI_INCLUDE = -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/darwin

CFLAGS = -fobjc-arc -dynamiclib \
	-framework Foundation -framework Metal -framework MetalFX \
	-framework AppKit -framework QuartzCore -framework OpenGL -framework IOSurface \
	-DGL_SILENCE_DEPRECATION $(JNI_INCLUDE)

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(CFLAGS) -o $(OUT) $(SRC)

clean:
	rm -f $(OUT)
