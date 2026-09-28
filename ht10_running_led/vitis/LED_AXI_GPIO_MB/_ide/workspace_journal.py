# 2026-09-28T13:29:36.552124400
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

platform = client.get_component(name="platform_2")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/design_1_wrapper_real_HW.xsa")

status = platform.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

