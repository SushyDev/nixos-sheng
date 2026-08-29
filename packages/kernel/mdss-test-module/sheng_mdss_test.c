// SPDX-License-Identifier: GPL-2.0
/*
 * Diagnostic module: re-power the MDSS GDSC after msm_dpu unplugs itself
 * following a bus fault, by calling pm_runtime_get_sync() on the still-present
 * display-subsystem platform device.
 *
 * Through genpd rather than raw ioremap/writel, because DISPCC's MMIO range is
 * still exclusively owned by the live disp_cc-sm8550 driver.
 *
 * One-shot: always returns non-zero from init so it does not stay resident.
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
