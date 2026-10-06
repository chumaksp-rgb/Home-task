# 2026-10-05T13:53:00.774511
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

vitis.dispose()

