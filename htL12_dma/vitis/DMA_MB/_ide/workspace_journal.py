# 2026-10-01T14:34:17.793890
import vitis

client = vitis.create_client()
client.set_workspace(path="DMA_MB")

vitis.dispose()

