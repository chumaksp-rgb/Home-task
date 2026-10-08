# 2026-10-08T14:49:46.104581800
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

comp = client.create_hls_component(name = "moving_max_test",cfg_file = ["hls_config.cfg"],template = "empty_hls_component")

