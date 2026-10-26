#!/bin/bash
# Workaround for kernel bug #220783 (i2c_designware spurious-IRQ regression).
#
# At boot the spurious-IRQ detector disables the interrupt line that
# i2c_designware.0 shares with idma64.0 ("irq N: nobody cared" ->
# "Disabling IRQ #N"). The I2C-HID touchpad probe then fails with
# "-110 (ETIMEDOUT)" and no input device is created.
#
# Re-binding the controller issues a fresh request_irq(), which clears
# IRQ_SPURIOUS_DISABLED and brings the line back.
#
# The script is a no-op when the touchpad already came up on its own, and
# only acts when the kernel really disabled the IRQ, so it becomes inert
# once the kernel is fixed upstream.

set -u

ADAPTER="${TOUCHPAD_I2C_ADAPTER:-i2c_designware.0}"
MATCH="${TOUCHPAD_MATCH:-GXTP7863.*Touchpad}"
TIMEOUT="${TOUCHPAD_WAIT:-3}"

touchpad_present() {
    grep -qE "$MATCH" /proc/bus/input/devices 2>/dev/null
}

# 1. If the touchpad is already detected and working, exit immediately.
if touchpad_present; then
    exit 0
fi

irq="$(awk -v dev="$ADAPTER" '$0 ~ dev { sub(":", "", $1); print $1; exit }' /proc/interrupts)"

# 2. If the kernel disabled the IRQ, don't wait — re-bind immediately.
if [ -n "$irq" ] && journalctl -k -b -q --no-pager 2>/dev/null | grep -q "Disabling IRQ #$irq"; then
    for _ in 1 2 3; do
        logger -t touchpad-irq-fix "IRQ $irq was disabled by the spurious-IRQ detector; re-binding $ADAPTER immediately"
        echo "$ADAPTER" > /sys/bus/platform/drivers/i2c_designware/unbind 2>/dev/null || exit 0
        sleep 0.5
        echo "$ADAPTER" > /sys/bus/platform/drivers/i2c_designware/bind 2>/dev/null || exit 0
        sleep 1
        touchpad_present && exit 0
    done
    logger -t touchpad-irq-fix "touchpad still not detected after re-binding $ADAPTER"
    exit 1
fi

# 3. Fallback: if IRQ was not disabled, wait briefly in case device is still probing.
for _ in $(seq 1 $((TIMEOUT * 2))); do
    touchpad_present && exit 0
    sleep 0.5
done

logger -t touchpad-irq-fix "touchpad not detected, but IRQ ${irq:-unknown} is not disabled; leaving the bus alone"
exit 0
