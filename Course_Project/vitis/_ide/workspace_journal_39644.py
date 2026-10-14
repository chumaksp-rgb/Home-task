# 2026-10-14T13:52:29.002456900
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

platform = client.create_platform_component(name = "Metronome_platform",hw_design = "$COMPONENT_LOCATION/../../vivado/Metronome/Metronome_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

comp = client.create_app_component(name="app_metronome",platform = "$COMPONENT_LOCATION/../Metronome_platform/export/Metronome_platform/Metronome_platform.xpfm",domain = "standalone_microblaze_0")

platform = client.get_component(name="Metronome_platform")
status = platform.build()

comp = client.get_component(name="app_metronome")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

