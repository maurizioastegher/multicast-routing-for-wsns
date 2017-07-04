from TOSSIM import *
import sys, StringIO
import random
import os

test = open("test.txt","w")
time = open("time.txt","w")

max_noise_lines = 100

def load_topology(r, topology_file):
    f = open(topology_file, "r")
    nodes_count = 0
    lines = f.readlines()
    for line in lines: 
        s = line.split() 
        if (len(s) > 0): 
            r.add(int(s[0]), int(s[1]), float(s[2].replace(',', '.')))
            if (int(s[0]) > nodes_count):
                nodes_count = int(s[0])
            if (int(s[1]) > nodes_count):
                nodes_count = int(s[1])
    f.close()
    nodes_count += 1
    return nodes_count

def load_noise(t, nodes_count):
    noiseFile = os.environ["TOSROOT"] + "/tos/lib/tossim/noise/meyer-heavy.txt"
    noise = open(noiseFile, "r")
    lines = noise.readlines()
    lines_cnt = 0
    for line in lines:
        lines_cnt += 1
        if (lines_cnt > max_noise_lines):
            break
        str = line.strip()
        if (str!= ""):
            val = int(str)
            for i in range(0, nodes_count):
                t.getNode(i).addNoiseTraceReading(val)
    for i in range(0, nodes_count):
        t.getNode(i).createNoiseModel()

def config_boot(t, nodes_count):
    for i in range(0, nodes_count):
        bootTime = random.randint(1000000000, 10000000000)
        t.getNode(i).bootAtTime(0)

def simulation_loop(t, sim_time):
    t.runNextEvent()
    startup_time = t.time()
    while (t.time() < startup_time + sim_time * 10000000):
        t.runNextEvent()

def run_simulation(sim_time, topology_file):
    t = Tossim([])
    r = t.radio()
    nodes_count = load_topology(r, topology_file)
    load_noise(t, nodes_count)
    config_boot(t, nodes_count)
    t.addChannel("color", test)
    t.addChannel("data", test)
    t.addChannel("reset", test)
    t.addChannel("time", time)
    simulation_loop(t, sim_time)

run_simulation(1000*60*60, "topology.out")
