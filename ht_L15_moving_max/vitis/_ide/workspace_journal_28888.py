# 2026-10-09T08:29:21.144678600
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

comp = client.get_component(name="moving_max_test")
comp.run(operation="PACKAGE")

comp.run(operation="SYNTHESIS")

comp.run(operation="PACKAGE")

vitis.dispose()

