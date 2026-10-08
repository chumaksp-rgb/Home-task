# 2026-10-08T14:49:46.104581800
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

comp = client.create_hls_component(name = "moving_max_test",cfg_file = ["hls_config.cfg"],template = "empty_hls_component")

cfg = client.get_config_file(path="/c:/PROJECTS_FPGA/Home_tasks/HT1/ht_L15_moving_max/vitis/moving_max_test/hls_config.cfg")

cfg.set_value(section="hls", key="syn.compile.pipeline_loops", value="0")

comp = client.get_component(name="moving_max_test")
comp.run(operation="C_SIMULATION")

comp.run(operation="SYNTHESIS")

comp.run(operation="C_SIMULATION")

comp.run(operation="SYNTHESIS")

comp.run(operation="CO_SIMULATION")

