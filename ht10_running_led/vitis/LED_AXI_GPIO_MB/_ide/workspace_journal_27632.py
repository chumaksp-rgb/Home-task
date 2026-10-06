# 2026-10-06T09:40:57.119795800
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

vitis.dispose()

