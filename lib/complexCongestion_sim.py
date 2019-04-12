#!/usr/bin/env python

"""
Controls the NS-2 simulation runs
"""

import os, sys, re
import numpy as np
import argparse
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
#from matplotlib.backends.backend_pdf import PdfPages

sys.path.append(os.path.expandvars('$BENCHMARK_NS2/bin/'))
import benchmark_tools

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--timely', action='store_true', help="Simulates Timely in the 2-level congestion scenario")
    args = parser.parse_args()
    
    num_clients = 10
    num_leafs = 2
    if (num_clients % num_leafs != 0):
	print('ERROR: Please provide number of clients that is multiple of number of leafs.')
	return

    out_dir = './complexCongestion_out/'

    if (args.timely):
	congestion_alg = 'timely'
        os.system('ns ./lib/complexCongestion.tcl {0} {1} {2} {3}'.format(congestion_alg, out_dir, num_clients, num_leafs))
	print("Timely Simulation Done!")
        benchmark_tools.plot_rtt(congestion_alg, out_dir)
	benchmark_tools.plot_throughput(congestion_alg, num_clients, out_dir, num_leafs)
	benchmark_tools.plot_queue(congestion_alg, out_dir)

if __name__ == "__main__":
    main()
