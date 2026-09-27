# 2026-09-27T16:13:46.624653700
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

platform = client.create_platform_component(name = "platform_2",hw_design = "$COMPONENT_LOCATION/../../../vivado/LED_AXI_GPIO_Zynq/LED_AXI_GPIO/design_1_wrapper_vitis.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

platform = client.get_component(name="platform_2")
status = platform.build()

