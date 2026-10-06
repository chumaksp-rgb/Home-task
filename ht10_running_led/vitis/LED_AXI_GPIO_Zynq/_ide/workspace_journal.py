# 2026-10-06T09:47:26.079750100
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

vitis.dispose()

