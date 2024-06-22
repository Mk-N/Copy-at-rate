import sys
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation

log_file_path = sys.argv[1]
graph_directory = sys.argv[2]

def update_graphs(i):
	data = pd.read_csv(log_file_path)

	# First Graph: Bytes copied vs Data rate and Target data rate
	plt.figure(1)
	plt.clf()
	plt.plot(data['BytesCopied'], data['DataRateKBps'], label='Data Rate KBps')
	plt.plot(data['BytesCopied'], data['TargetDataRateKBps'], label='Target Data Rate KBps', linestyle='--')
	plt.xlabel('Bytes Copied')
	plt.ylabel('Data Rate (KBps)')
	plt.legend()
	plt.title('Data Rate vs Bytes Copied')
	plt.savefig(f"{graph_directory}/data_rate_vs_bytes_copied.svg")

	# Second Graph: Bytes copied vs Sleep time and Chunk size
	plt.figure(2)
	plt.clf()
	plt.plot(data['BytesCopied'], data['SleepTimeMs'], label='Sleep Time (ms)')
	plt.plot(data['BytesCopied'], data['ChunkSize'], label='Chunk Size (bytes)', linestyle='--')
	plt.xlabel('Bytes Copied')
	plt.ylabel('Sleep Time (ms) / Chunk Size (bytes)')
	plt.legend()
	plt.title('Sleep Time and Chunk Size vs Bytes Copied')
	plt.savefig(f"{graph_directory}/sleep_time_chunk_size_vs_bytes_copied.svg")

if __name__ == "__main__":
	plt.figure(1)
	plt.figure(2)

	anim1 = FuncAnimation(plt.figure(1), update_graphs, interval=1000)
	anim2 = FuncAnimation(plt.figure(2), update_graphs, interval=1000)

	plt.show()
