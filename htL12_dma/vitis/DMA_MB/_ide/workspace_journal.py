# 2026-10-01T14:26:21.130367100
import vitis

client = vitis.create_client()
client.set_workspace(path="DMA_MB")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../../vivado/DMA_MB/design_1_DMA_MB.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

