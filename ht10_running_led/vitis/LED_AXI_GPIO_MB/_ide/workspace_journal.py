# 2026-10-06T10:09:50.875455500
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

vitis.dispose()

