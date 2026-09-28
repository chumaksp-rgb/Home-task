# 2026-09-28T09:14:33.350443600
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

platform = client.get_component(name="platform_2")
status = platform.build()

status = platform.build()

status = platform.build()

comp = client.get_component(name="app_component_2")
comp.build()

status = comp.clean()

status = comp.clean()

status = comp.clean()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

