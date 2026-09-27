# 2026-09-27T16:38:15.851366
import vitis

client = vitis.create_client()
client.set_workspace(path="LED_AXI_GPIO_Zynq")

platform = client.get_component(name="platform_2")
status = platform.build()

comp = client.get_component(name="app_component_2")
comp.build()

comp = client.get_component(name="app_component_2")
status = comp.import_files(from_loc="$COMPONENT_LOCATION/src", files=["main_combined.c"], dest_dir_in_cmp = "app_component_2", is_skip_copy_sources = False)

status = platform.build()

comp = client.get_component(name="app_component_2")
comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

comp = client.get_component(name="app_component_2")
status = comp.import_files(from_loc="$COMPONENT_LOCATION/src", files=["main_combined.c"], dest_dir_in_cmp = "src", is_skip_copy_sources = False)

status = platform.build()

comp = client.get_component(name="app_component_2")
comp.build()

status = comp.clean()

comp = client.get_component(name="app_component_2")
status = comp.import_files(from_loc="$COMPONENT_LOCATION/..", files=["main_combined.c"], dest_dir_in_cmp = "src", is_skip_copy_sources = False)

comp = client.get_component(name="app_component_2")
status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

