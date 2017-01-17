BUILDTOOLS_OVERRIDE=1

EXTRA_CFLAGS += -Wall -Werror
EXTRA_CFLAGS += -Wno-date-time
EXTRA_CFLAGS += -I$(M)/include/
EXTRA_CFLAGS += -I$(M)/include/linux/
EXTRA_CFLAGS += -I$(M)/include/linux/mlx_sx/

ifeq ($(ARCH),x86_64)
  EXTRA_CFLAGS += -I$(M)/arch/x86
endif
ifeq ($(ARCH),ppc)
  EXTRA_CFLAGS += -I$(M)/arch/powerpc
endif

lpci2c-objs := lpc_i2c.o
obj-m += lpci2c.o mlnx-mux-drv.o mlnx-cpld-drv.o mlnx-asic-drv.o mlnx-a2d-drv.o leds-mlx.o

