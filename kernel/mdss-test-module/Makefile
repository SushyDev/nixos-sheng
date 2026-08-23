obj-m += sheng_mdss_test.o
obj-m += sheng_dsi_lab.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
