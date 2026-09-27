# 2026-09-27T16:13:46.624653700
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

platform = client.create_platform_component(name = "platform_2",hw_design = "$COMPONENT_LOCATION/../../../vivado/LED_AXI_GPIO_Zynq/LED_AXI_GPIO/design_1_wrapper_vitis.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

platform = client.get_component(name="platform_2")
status = platform.build()

comp = client.create_app_component(name="app_component_2",platform = "$COMPONENT_LOCATION/../platform_2/export/platform_2/platform_2.xpfm",domain = "standalone_ps7_cortexa9_0")

comp = client.get_component(name="app_component_2")
status = comp.import_files(from_loc="", files=["C:\PROJECTS_FPGA\Home_tasks\HT1\ht10_running_led\vitis\LED_AXI_GPIO_Zynq\main_combined.c"], is_skip_copy_sources = False)

status = platform.build()

comp = client.get_component(name="app_component_2")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

