# 2026-10-05T13:25:44.787653200
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

platform = client.get_component(name="platform_2")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

vitis.dispose()

