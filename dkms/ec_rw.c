// SPDX-License-Identifier: GPL-2.0-only
/*
 * ec_rw - expose ACPI Embedded Controller (EC) RAM as a misc device
 *
 * This tiny module gives user space raw read/write access to the 256 bytes
 * of EC RAM through /dev/ec_rw (misc device, mode 0600, root only).  It is
 * used by the Thunderobot ZERO fan-control daemon to drive the fans, which
 * on this laptop are controlled purely by the EC firmware and have no
 * standard hwmon/PWM interface.
 *
 * Why a custom module instead of loading ec_sys with write_support=1?
 *   - The ec_sys write_support parameter is an "unsafe module parameter"
 *     and is rejected by kernel lockdown (enforced when Secure Boot is on).
 *   - Writable debugfs files are also denied under lockdown.
 *   A misc character device is not subject to either restriction, so this
 *   module works on Secure Boot systems as long as it is signed with an
 *   enrolled MOK key (see dkms.conf / docs/secure-boot.md).
 *
 * Security note: this gives root the ability to poke arbitrary EC registers.
 * The EC firmware is responsible for keeping the system safe; writing
 * unknown registers can cause hangs or forced reboots.  Only the two fan
 * duty registers (0x2C/0x2D) are known-safe for this laptop.
 *
 * Build: shipped as a DKMS module (dkms/).  The kernel symbols ec_read() and
 * ec_write() are exported (EXPORT_SYMBOL) by drivers/acpi/ec.c.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/miscdevice.h>
#include <linux/err.h>

#define EC_RW_SIZE 256

extern int ec_read(u8 addr, u8 *val);
extern int ec_write(u8 addr, u8 val);

static ssize_t ec_rw_read(struct file *file, char __user *buf, size_t len,
			  loff_t *ppos)
{
	u8 data[EC_RW_SIZE];
	loff_t pos = *ppos;
	int i;

	if (pos >= EC_RW_SIZE)
		return 0;
	if (len > EC_RW_SIZE - pos)
		len = EC_RW_SIZE - pos;

	for (i = 0; i < (int)len; i++) {
		if (ec_read(pos + i, &data[i]))
			return -EIO;
	}
	if (copy_to_user(buf, data, len))
		return -EFAULT;
	*ppos = pos + len;
	return len;
}

static ssize_t ec_rw_write(struct file *file, const char __user *buf,
			   size_t len, loff_t *ppos)
{
	u8 data[32];
	loff_t pos = *ppos;
	int i;

	if (pos >= EC_RW_SIZE)
		return -ENOSPC;
	if (len > sizeof(data))
		len = sizeof(data);
	if (len > EC_RW_SIZE - pos)
		len = EC_RW_SIZE - pos;

	if (copy_from_user(data, buf, len))
		return -EFAULT;

	for (i = 0; i < (int)len; i++) {
		if (ec_write(pos + i, data[i]))
			return -EIO;
	}
	*ppos = pos + len;
	return len;
}

static loff_t ec_rw_llseek(struct file *file, loff_t offset, int whence)
{
	loff_t new_pos;

	switch (whence) {
	case SEEK_SET:
		new_pos = offset;
		break;
	case SEEK_CUR:
		new_pos = file->f_pos + offset;
		break;
	case SEEK_END:
		new_pos = EC_RW_SIZE + offset;
		break;
	default:
		return -EINVAL;
	}
	if (new_pos < 0 || new_pos > EC_RW_SIZE)
		return -EINVAL;
	file->f_pos = new_pos;
	return new_pos;
}

static const struct file_operations ec_rw_fops = {
	.owner = THIS_MODULE,
	.llseek = ec_rw_llseek,
	.read = ec_rw_read,
	.write = ec_rw_write,
};

static struct miscdevice ec_rw_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "ec_rw",
	.fops = &ec_rw_fops,
	.mode = 0600,
};

static int __init ec_rw_init(void)
{
	return misc_register(&ec_rw_misc);
}

static void __exit ec_rw_exit(void)
{
	misc_deregister(&ec_rw_misc);
}

module_init(ec_rw_init);
module_exit(ec_rw_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Expose EC RAM read/write via misc device for fan control");
MODULE_VERSION("1.0");
