# 2026-09-29T08:36:32.961428100
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

vitis.dispose()

