# 2026-09-28T11:36:06.432970500
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_MB")

platform = client.create_platform_component(name = "platform_2",hw_design = "$COMPONENT_LOCATION/../../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

platform = client.get_component(name="platform_2")
status = platform.build()

