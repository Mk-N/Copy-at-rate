import sys
import os  # Import os module for path operations
import pandas as pd
import matplotlib.pyplot as plt
import time
from matplotlib.animation import FuncAnimation

def update_graphs(frame):
    data = pd.read_csv(CSVLogFilePath)

    # First Graph: Bytes copied vs Data rate and Target data rate
    plt.figure(1)
    plt.clf()
    plt.plot(data['BytesCopied'], data['DataRateKBps'], label='Data Rate KBps')
    plt.plot(data['BytesCopied'], data['TargetDataRateKBps'], label='Target Data Rate KBps', linestyle='--')
    plt.xlabel('Bytes Copied')
    plt.ylabel('Data Rate (KBps)')
    plt.legend()
    plt.title('Data Rate vs Bytes Copied')
    plt.savefig(os.path.join(graph_directory, f"{dataRateGraphName}.svg"))  # Use os.path.join for safe path construction

    # Second Graph: Bytes copied vs Sleep time and Chunk size
    plt.figure(2)
    plt.clf()
    plt.plot(data['BytesCopied'], data['SleepTimeMs'], label='Sleep Time (ms)')
    plt.plot(data['BytesCopied'], data['ChunkSize'], label='Chunk Size (bytes)', linestyle='--')
    plt.xlabel('Bytes Copied')
    plt.ylabel('Sleep Time (ms) / Chunk Size (bytes)')
    plt.legend()
    plt.title('Sleep Time and Chunk Size vs Bytes Copied')
    plt.savefig(os.path.join(graph_directory2, f"{sleepChunkGraphName}.svg"))  # Use os.path.join for safe path construction

if __name__ == "__main__":
    time.sleep(1)

    if len(sys.argv) < 6:
        print("Usage: python script.py CSVLogFilePath graph_directory graph_directory2 dataRateGraphName sleepChunkGraphName")
        sys.exit(1)

    CSVLogFilePath = sys.argv[1]
    graph_directory = sys.argv[2]
    graph_directory2 = sys.argv[3] if sys.argv[3] != "" else graph_directory
    dataRateGraphName = sys.argv[4]
    sleepChunkGraphName = sys.argv[5]

    anim1 = FuncAnimation(plt.figure(1), update_graphs, interval=1000)
    anim2 = FuncAnimation(plt.figure(2), update_graphs, interval=1000)

    plt.show()