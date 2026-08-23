// SPDX-License-Identifier: GPL-2.0
/*
 * Diagnostic module: attempt to re-power the MDSS GDSC power domain by
 * calling pm_runtime_get_sync() on the still-present
 * "ae00000.display-subsystem" platform device, after msm_dpu's driver
 * unplugged itself following a bus fault (see project notes -- a
 * debugfs regmap dump of the DISPCC clock controller walked into a
 * gated register and faulted the interconnect, which took the display
 * off without a full kernel panic).
 *
 * This deliberately goes through the kernel's own genpd/gdsc framework
 * (the same gdsc_enable() in drivers/clk/qcom/gdsc.c already read for
 * the U-Boot port) rather than raw ioremap/writel from this module --
 * that first attempt (see git history of this file) correctly refused
 * to touch DISPCC's MMIO range at all because request_mem_region()
 * showed it's still exclusively owned by the live disp_cc-sm8550
 * clock-controller driver. Going through pm_runtime instead respects
 * that ownership instead of fighting it.
 *
 * Logs the pm_genpd_summary-equivalent state before and after via the
 * return value of pm_runtime_get_sync(), then releases the reference.
 * One-shot: always returns non-zero from init so it doesn't stay
 * resident.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>

#define MDSS_DEV_NAME "ae00000.display-subsystem"

static int __init sheng_mdss_pm_test_init(void)
{
	struct device *dev;
	int ret;

	dev = bus_find_device_by_name(&platform_bus_type, NULL, MDSS_DEV_NAME);
	if (!dev) {
		pr_err("sheng_mdss_pm_test: device '%s' not found on platform bus\n",
		       MDSS_DEV_NAME);
		return -ENODEV;
	}

	pr_info("sheng_mdss_pm_test: found %s, runtime_status=%d pm_usage_count=%d runtime_enabled=%d\n",
		dev_name(dev), dev->power.runtime_status,
		atomic_read(&dev->power.usage_count),
		pm_runtime_enabled(dev));

	ret = pm_runtime_get_sync(dev);
	pr_info("sheng_mdss_pm_test: pm_runtime_get_sync() returned %d, runtime_status now=%d\n",
		ret, dev->power.runtime_status);

	if (ret >= 0) {
		pm_runtime_put(dev);
		pr_info("sheng_mdss_pm_test: released reference, runtime_status now=%d\n",
			dev->power.runtime_status);
	} else {
		pm_runtime_put_noidle(dev);
	}

	put_device(dev);

	return -ECANCELED;
}

static void __exit sheng_mdss_pm_test_exit(void)
{
}

module_init(sheng_mdss_pm_test_init);
module_exit(sheng_mdss_pm_test_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Diagnostic: attempt MDSS GDSC re-power via pm_runtime on the orphaned mdss device");
MODULE_AUTHOR("sheng-development");
