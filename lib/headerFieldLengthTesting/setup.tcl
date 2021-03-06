
# May, 2019
# Author: Serhat Arslan, Stanford University

#  This script simulates a multi-Level topology where
# congestion takes place in multiple hops.

if {$argc != 6} {
    puts "wrong number of arguments, expected 6, got $argc"
    exit 0
}

set congestion_alg [lindex $argv 0]
set hope_bits [lindex $argv 1]
set out_dir [lindex $argv 2]

set out_rtt_file $out_dir$congestion_alg.rtt.out
set rtt_file [open $out_rtt_file w]
set out_q_file $out_dir$congestion_alg.queue.out

set num_clients [lindex $argv 3]
set num_TORs [lindex $argv 4]
set num_leafs [lindex $argv 5]
set num_conn_per_client 1

set clientPerTOR [expr $num_clients/$num_TORs]
set TORperLeaf [expr $num_TORs/$num_leafs]

# samp_int (sec)
set samp_int 0.0001
# q_size (pkts)
set q_size 200
# link_cap (Mbps)
set client_link_cap 1Gb
set link_cap 10Gb
set spine_link_cap 40Gb
# link_delay (ms)
set link_delay 5us
# tcp_window (pkts)
set tcp_window 10000000
# run_time (sec)
set run_time 0.1
# pktSize (bytes)
set pktSize 1460

#### Timely/Hope Parameters ####
set timely_ewma_alpha 0.3
set timely_t_low 0
set timely_t_high 0.001
set timely_additiveInc 30000000.0
set timely_decreaseFac 0.8
set timely_HAI_thresh 5
set timely_rate 750000000.0

##### Switch Parameters ####
set drop_prio_ false
set deque_prio_ false

#Create a simulator object
set ns [new Simulator]

#Open the Trace files
set tracefile [open $out_dir$congestion_alg.tr w]
$ns trace-all $tracefile

##Open the NAM trace file
#set nf [open $out_dir$congestion_alg.nam w]
#$ns namtrace-all $nf

# Create TOR_switch, server, and client nodes
for {set i 0} {$i < $num_clients} {incr i} {
    set client($i) [$ns node]
}

for {set i 0} {$i < $num_TORs} {incr i} {
    set TOR_switch($i) [$ns node]
}

for {set i 0} {$i < $num_leafs} {incr i} {
    set leaf_switch($i) [$ns node]
}

set spine_switch [$ns node]
$ns at 0.001 "$spine_switch label \"Spine\""

# Queue options
Queue set limit_ $q_size

Queue/DropTail set mean_pktsize_ [expr $pktSize+40]
Queue/DropTail set drop_prio_ $drop_prio_
Queue/DropTail set deque_prio_ $deque_prio_

set queue_type DropTail

# Create links between the nodes
# Create links spine-leafs and leafs-TORs
for {set i 0} {$i < $num_leafs} {incr i} {
    $ns duplex-link $leaf_switch($i) $spine_switch $spine_link_cap $link_delay $queue_type

    for {set j 0} {$j < $TORperLeaf} {incr j} {
    set conn_idx [expr $i*$TORperLeaf+$j]
    $ns duplex-link $TOR_switch($conn_idx) $leaf_switch($i) $link_cap $link_delay $queue_type
    }
}

# Create links between the clients and the TORs
for {set i 0} {$i < $num_TORs} {incr i} {
    for {set j 0} {$j < $clientPerTOR} {incr j} {
    set conn_idx [expr $i*$clientPerTOR+$j]

        $ns duplex-link $client($conn_idx) $TOR_switch($i) $client_link_cap $link_delay $queue_type
    }
}

##Monitor the queue for link. (for NAM)
#for {set i 0} {$i < $num_TORs} {incr i} {
#    for {set j 0} {$j < $clientPerTOR} {incr j} {
#   set conn_idx [expr $i*$clientPerTOR+$j]
#
#        $ns duplex-link-op $client($conn_idx) $TOR_switch($i) queuePos 0.5
#    }
#}

# Create random generator for TCP connections
set rng1 [new RNG]
$rng1 seed 1

# Parameters for random variables to ftp start times
set RV_host [new RandomVariable/Uniform]
$RV_host set min_ 0
$RV_host set max_ [expr $num_clients-0.000001]
$RV_host use-rng $rng1

# HOST options
Agent/TCP set window_ $tcp_window
Agent/TCP set windowInit_ 2
Agent/TCP set packetSize_ $pktSize
Agent/TCP/FullTcp set segsize_ $pktSize

# DCTCP settings
for {set i 0} {$i < $num_clients} {incr i} {
    for {set j 0} {$j < $num_conn_per_client} {incr j} {
    	set conn_idx [expr $i*$num_conn_per_client+$j]
        set dst($conn_idx) [expr (int(floor([$RV_host value])))]  

        if {$i == $dst($conn_idx)} {
        	if {$i == 0} {
            	set dst($conn_idx) [expr $dst($conn_idx)+1]
        	} else {
            	set dst($conn_idx) [expr $dst($conn_idx)-1]
        	}
        }      
    
        set tcp($conn_idx) [new Agent/TCP/Vegas]
        set sink($conn_idx) [new Agent/TCPSink]
        $ns attach-agent $client($i) $tcp($conn_idx)
        $ns attach-agent $client($dst($conn_idx)) $sink($conn_idx)
        $tcp($conn_idx) set fid_ [expr $conn_idx]
        $sink($conn_idx) set fid_ [expr $conn_idx]
        $ns connect $tcp($conn_idx) $sink($conn_idx)

        $tcp($conn_idx) set timely_packetSize_ [expr $pktSize+40]
        $tcp($conn_idx) set timely_ewma_alpha_ $timely_ewma_alpha
        $tcp($conn_idx) set timely_t_low_ $timely_t_low
        $tcp($conn_idx) set timely_t_high_ $timely_t_high
        $tcp($conn_idx) set timely_additiveInc_ $timely_additiveInc
        $tcp($conn_idx) set timely_decreaseFac_ $timely_decreaseFac
        $tcp($conn_idx) set timely_HAI_thresh_ $timely_HAI_thresh
        $tcp($conn_idx) set timely_rate_ $timely_rate
        $tcp($conn_idx) set rttNoise_ 0
        $tcp($conn_idx) set hope_type_ 1
        $tcp($conn_idx) set hope_collector_ 1
        $tcp($conn_idx) set hope_bits_ $hope_bits
        
        set ftp($conn_idx) [$tcp($conn_idx) attach-source FTP]
        $ftp($conn_idx) set type_ FTP 
    }
}

Agent/TCP/Vegas instproc recv {rtt_t cong_signal_t hopCnt_t timely_rate_t} {
    global ns rtt_file pktSize
    $self instvar fid_

    set now [$ns now]
    set rtt [expr $rtt_t * 1000000.0]
    puts $rtt_file "$now $fid_ $rtt"
}


# queue monitoring for TOR links of leafs
set qf_size [open $out_q_file w]
for {set i 0} {$i < $num_leafs} {incr i} {
    for {set j 0} {$j < $TORperLeaf} {incr j} {
        set node_idx [expr $i*$TORperLeaf+$j]
        set qmon_size [$ns monitor-queue $leaf_switch($i) $TOR_switch($node_idx) $qf_size $samp_int]
        [$ns link $leaf_switch($i) $TOR_switch($node_idx)] queue-sample-timeout
    }
}

# Create random generator for starting the ftp connections
set rng2 [new RNG]
$rng2 seed 2

# Parameters for random variables to ftp start times
set RV_beg_fin [new RandomVariable/Uniform]
$RV_beg_fin set min_ 0.0001
$RV_beg_fin set max_ [expr $run_time/5]
$RV_beg_fin use-rng $rng2

#Schedule events for the FTP agents
for {set i 0} {$i < $num_clients} {incr i} {
    for {set j 0} {$j < $num_conn_per_client} {incr j} {
    	set conn_idx [expr $i*$num_conn_per_client+$j]        
    
    	set startT($conn_idx) [expr [$RV_beg_fin value]]
    	$ns at $startT($conn_idx) "$ftp($conn_idx) start"
    	#$ns at 0.0001 "$ftp($conn_idx) start"
    	set finT($conn_idx) [expr [$RV_beg_fin value]]
    	$ns at [expr $run_time - $finT($conn_idx)] "$ftp($conn_idx) stop"
        #$ns at [expr $run_time - 0.001] "$ftp($conn_idx) stop"
    }
}

#Call the finish procedure after run_time seconds of simulation time
$ns at $run_time "finish"

#Define a 'finish' procedure
proc finish {} {
    global congestion_alg ns tracefile rtt_file qf_size out_dir
    $ns flush-trace
    # Close the NAM trace file
#    close $nf
    close $tracefile
    close $rtt_file 
    close $qf_size
    # Execute NAM on the trace file
#    exec nam $out_dir$congestion_alg.nam &
    exit 0
}

#Run the simulation
$ns run
