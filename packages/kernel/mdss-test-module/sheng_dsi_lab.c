// SPDX-License-Identifier: GPL-2.0
/*
 * sheng_dsi_lab -- interactive DSI command bench for the Xiaomi Pad 6S Pro.
 *
 * WHY THIS EXISTS
 *
 * U-Boot's panel init provably does not configure the DDIC. That was
 * established with a paired control: the same kernel read path returns
 * ret=0 val=0x9e when Linux runs its own init, and ret=-61 (-ENODATA)
 * when only U-Boot has touched the panel -- with the panel confirmed
 * powered (avdd/avee IN_OUT=0x3) and reset confirmed deasserted
 * (GPIO133 IN_OUT=0x3), so the DDIC was awake and simply had nothing
 * to say. Meanwhile the U-Boot side is exhaustively verified: the 87
 * command payloads are byte-identical to the ones Linux transmits, they
 * leave the host at a measured LP escape rate, no DMA times out, the
 * reset pulse is physically real (pad reads 0x0 while driven low), and
 * every register in DPU/DSI/PHY/DISPCC matches live rendering silicon.
 *
 * Iterating that in U-Boot costs a build, a flash, a reboot and a DRAM
 * log read per question. This module moves the experiment into Linux,
 * where the transport is known-good and a question costs one echo.
 *
 * THE KEY ENABLER: the panel driver sends its entire init sequence to
 * dsi0 ONLY -- "qcom,sync-dual-dsi in dsi nodes will send them to both
 * dsi ports" (panel-novatek-nt36532e.c). So a single mipi_dsi_device is
 * enough to drive a bonded dual-DSI panel, and dsi0 is reachable from
 * its DT node with no kernel patch at all.
 *
 * USAGE (pair with panel_novatek_nt36532e.noinit=1 so the panel is left
 * exactly as U-Boot configured it, while Linux still brings up host,
 * PHY, DPU and streams video):
 *
 *   cat  /sys/kernel/debug/sheng_dsi/pm        # is the DDIC configured?
 *   echo "ff 26" > /sys/kernel/debug/sheng_dsi/send
 *   echo "d 120" > /sys/kernel/debug/sheng_dsi/send   # delay 120ms
 *   cat  init.txt > /sys/kernel/debug/sheng_dsi/send  # whole table
 *   cat  /sys/kernel/debug/sheng_dsi/status    # result of last batch
 *   echo hs > /sys/kernel/debug/sheng_dsi/mode # LP vs HS transmission
 *
 * The command table lives in userspace, so changing it costs nothing.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/display/drm_dsc.h>

#define LAB_MAX_PAYLOAD 256

static struct mipi_dsi_device *lab_dsi;
static struct dentry *lab_dir;
static char lab_status[192] = "no batch run yet";

static int lab_pm_show(struct seq_file *s, void *unused)
{
	u8 val = 0xAA;
	int ret;

	if (!lab_dsi) {
		seq_puts(s, "no dsi device\n");
		return 0;
	}

	/* 0xAA is a sentinel: if the read fails without touching it, the
	 * value printed is provably ours and not a real panel answer. */
	ret = mipi_dsi_dcs_get_power_mode(lab_dsi, &val);
	seq_printf(s, "ret=%d val=0x%02x mode_flags=0x%lx\n",
		   ret, val, lab_dsi->mode_flags);
	if (ret == 0)
		seq_printf(s, "decode: booster=%d sleep_out=%d normal=%d display_on=%d\n",
			   !!(val & BIT(7)), !!(val & BIT(4)),
			   !!(val & BIT(3)), !!(val & BIT(2)));
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(lab_pm);

static int lab_status_show(struct seq_file *s, void *unused)
{
	seq_printf(s, "%s\n", lab_status);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(lab_status);

/* One line = one action.
 *   "d <ms>"        -> sleep
 *   "aa bb cc ..."  -> one DCS write (type picked by length, as the
 *                      panel driver's own helpers do)
 * '#' starts a comment. Blank lines ignored.
 */
static int lab_run_line(char *line, int lineno, int *nsent)
{
	u8 payload[LAB_MAX_PAYLOAD];
	int n = 0;
	char *tok;
	int ret;

	tok = strim(line);
	if (!*tok || *tok == '#')
		return 0;

	/* "pps <128 hex bytes>" -- the DSC Picture Parameter Set is packet
	 * type 0x0A, NOT a DCS write, so it cannot be expressed as a plain
	 * byte list. Replaying an init sequence without it silently omits
	 * DSC configuration and the panel will not come up, which is a very
	 * easy way to blame the wrong thing. */
	if (!strncmp(tok, "pps", 3) && (tok[3] == ' ' || tok[3] == '\t')) {
		struct drm_dsc_picture_parameter_set pps;
		u8 *p = (u8 *)&pps;
		int i = 0;

		line = tok + 4;
		while ((tok = strsep(&line, " \t")) != NULL) {
			u8 byte;

			if (!*tok)
				continue;
			if (*tok == '#')
				break;
			if (i >= sizeof(pps))
				return -E2BIG;
			if (kstrtou8(tok, 16, &byte))
				return -EINVAL;
			p[i++] = byte;
		}
		if (i != sizeof(pps)) {
			snprintf(lab_status, sizeof(lab_status),
				 "FAILED line %d: pps needs %zu bytes, got %d",
				 lineno, sizeof(pps), i);
			return -EINVAL;
		}
		ret = mipi_dsi_picture_parameter_set(lab_dsi, &pps);
		if (ret < 0) {
			snprintf(lab_status, sizeof(lab_status),
				 "FAILED line %d: pps ret %d (after %d ok)",
				 lineno, ret, *nsent);
			return ret;
		}
		(*nsent)++;
		return 0;
	}

	if (tok[0] == 'd' && (tok[1] == ' ' || tok[1] == '\t')) {
		unsigned int ms;

		if (kstrtouint(strim(tok + 1), 10, &ms))
			return -EINVAL;
		if (ms > 5000)
			ms = 5000;
		msleep(ms);
		return 0;
	}

	while ((tok = strsep(&line, " \t")) != NULL) {
		u8 byte;

		if (!*tok)
			continue;
		if (*tok == '#')
			break;
		if (n >= LAB_MAX_PAYLOAD)
			return -E2BIG;
		if (kstrtou8(tok, 16, &byte))
			return -EINVAL;
		payload[n++] = byte;
	}

	if (!n)
		return 0;

	ret = mipi_dsi_dcs_write_buffer(lab_dsi, payload, n);
	if (ret < 0) {
		snprintf(lab_status, sizeof(lab_status),
			 "FAILED line %d cmd 0x%02x len %d ret %d (after %d ok)",
			 lineno, payload[0], n, ret, *nsent);
		return ret;
	}
	(*nsent)++;
	return 0;
}

static ssize_t lab_send_write(struct file *f, const char __user *ubuf,
			      size_t len, loff_t *off)
{
	char *buf, *cur, *line;
	int lineno = 0, nsent = 0, ret = 0;

	if (!lab_dsi)
		return -ENODEV;
	if (len > SZ_64K)
		return -E2BIG;

	buf = memdup_user_nul(ubuf, len);
	if (IS_ERR(buf))
		return PTR_ERR(buf);

	cur = buf;
	while ((line = strsep(&cur, "\n")) != NULL) {
		lineno++;
		ret = lab_run_line(line, lineno, &nsent);
		if (ret)
			break;
	}

	if (!ret)
		snprintf(lab_status, sizeof(lab_status),
			 "OK %d commands sent, %d lines", nsent, lineno);
	pr_info("sheng_dsi_lab: %s\n", lab_status);

	kfree(buf);
	return ret ? ret : len;
}

static const struct file_operations lab_send_fops = {
	.owner = THIS_MODULE,
	.open  = simple_open,
	.write = lab_send_write,
	.llseek = noop_llseek,
};

/* LP vs HS matters here: U-Boot transmits in LP (measured 0.727us/byte,
 * the escape-clock rate). If the DDIC only latches this table in one
 * mode, that alone would explain everything. */
static ssize_t lab_mode_write(struct file *f, const char __user *ubuf,
			      size_t len, loff_t *off)
{
	char kbuf[8] = {};

	if (!lab_dsi)
		return -ENODEV;
	if (len >= sizeof(kbuf))
		return -EINVAL;
	if (copy_from_user(kbuf, ubuf, len))
		return -EFAULT;

	if (!strncmp(kbuf, "lp", 2))
		lab_dsi->mode_flags |= MIPI_DSI_MODE_LPM;
	else if (!strncmp(kbuf, "hs", 2))
		lab_dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
	else
		return -EINVAL;

	pr_info("sheng_dsi_lab: mode_flags now 0x%lx\n", lab_dsi->mode_flags);
	return len;
}

static const struct file_operations lab_mode_fops = {
	.owner = THIS_MODULE,
	.open  = simple_open,
	.write = lab_mode_write,
	.llseek = noop_llseek,
};

static int __init sheng_dsi_lab_init(void)
{
	struct device_node *np;

	np = of_find_compatible_node(NULL, NULL, "novatek,nt36532e");
	if (!np) {
		pr_err("sheng_dsi_lab: no novatek,nt36532e node\n");
		return -ENODEV;
	}

	lab_dsi = of_find_mipi_dsi_device_by_node(np);
	of_node_put(np);
	if (!lab_dsi) {
		pr_err("sheng_dsi_lab: panel node has no mipi_dsi_device\n");
		return -ENODEV;
	}

	lab_dir = debugfs_create_dir("sheng_dsi", NULL);
	debugfs_create_file("pm", 0444, lab_dir, NULL, &lab_pm_fops);
	debugfs_create_file("status", 0444, lab_dir, NULL, &lab_status_fops);
	debugfs_create_file("send", 0200, lab_dir, NULL, &lab_send_fops);
	debugfs_create_file("mode", 0200, lab_dir, NULL, &lab_mode_fops);

	pr_info("sheng_dsi_lab: ready on %s, mode_flags=0x%lx lanes=%d\n",
		dev_name(&lab_dsi->dev), lab_dsi->mode_flags, lab_dsi->lanes);
	return 0;
}

static void __exit sheng_dsi_lab_exit(void)
{
	debugfs_remove_recursive(lab_dir);
}

module_init(sheng_dsi_lab_init);
module_exit(sheng_dsi_lab_exit);

MODULE_DESCRIPTION("Interactive DSI command bench for sheng panel bring-up");
MODULE_LICENSE("GPL");
