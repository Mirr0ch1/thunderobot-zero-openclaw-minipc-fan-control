obj-m += ec_rw.o

# DKMS passes KERNELRELEASE; fall back for manual builds
KDIR ?= /lib/modules/$(KERNELRELEASE)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
