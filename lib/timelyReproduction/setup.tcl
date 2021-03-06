
# March, 2019
# Author: Serhat Arslan, Stanford University

#  This script simulates the DCTCP behavior with the setup given
# in "TIMELY: RTT-based Congestion Control for the Datacenter"
# paper by Radhika Mittal et. al.

if {$argc != 4} {
    puts "wrong number of arguments, expected 4, got $argc"
    exit 0
}

set congestion_alg [lindex $argv 0]
set repro_dir [lindex $argv 1]

set out_rtt_file $repro_dir$congestion_alg.rtt.out
set rtt_file [open $out_rtt_file w]
set out_rate_file $repro_dir$congestion_alg.rate.out
set rate_file [open $out_rate_file w]
set out_q_file $repro_dir$congestion_alg.queue.out

set num_clients [lindex $argv 2]
set num_conn_per_client [lindex $argv 3]
# set patched_timely [lindex $argv 4]

# samp_int (sec)
set samp_int 0.0001
# q_size (pkts)
set q_size 200
# link_cap (Mbps)
set link_cap 20Gb
# link_delay (ms)
set link_delay 5us
# tcp_window (pkts)
set tcp_window 10000000
# run_time (sec)
set run_time 1.1

# pktSize (bytes)
set pktSize 1460

#### DCTCP Parameters ####
# DCTCP_K (pkts)
set DCTCP_K 80
# DCTCP_g (0 < g < 1)
set DCTCP_g 0.0625
# ackRatio
set ackRatio 1

##### Switch Parameters ####
set drop_prio_ false
set deque_prio_ false

#Create a simulator object
set ns [new Simulator]

#Open the Trace files
set tracefile [open $repro_dir$congestion_alg.tr w]
$ns trace-all $tracefile

#Open the NAM trace file
set nf [open $repro_dir$congestion_alg.nam w]
$ns namtrace-all $nf

# Create TOR_switch, server, and client nodes
for {set i 0} {$i < $num_clients} {incr i} {
    set client($i) [$ns node]
}

set TOR_switch_node [$ns node]
$ns at 0 "$TOR_switch_node label \"TOR\""
set server_node [$ns node]
$ns at 0 "$server_node label \"Server\""

# Queue options
Queue set limit_ $q_size

Queue/DropTail set mean_pktsize_ [expr $pktSize+40]
Queue/DropTail set drop_prio_ $drop_prio_
Queue/DropTail set deque_prio_ $deque_prio_

#Queue/RED set bytes_ false
#Queue/RED set queue_in_bytes_ true
Queue/RED set mean_pktsize_ $pktSize
Queue/RED set setbit_ true
Queue/RED set gentle_ false
Queue/RED set q_weight_ 1.0
Queue/RED set mark_p_ 1.0
Queue/RED set thresh_ $DCTCP_K
Queue/RED set maxthresh_ $DCTCP_K
Queue/RED set drop_prio_ $drop_prio_
Queue/RED set deque_prio_ $deque_prio_

if {[string compare $congestion_alg "dctcp"] == 0} { 
    set queue_type RED
} else {
    set queue_type DropTail
}

# Create links between the nodes
$ns duplex-link $TOR_switch_node $server_node $link_cap $link_delay $queue_type

# Create a Star topology to simulate a rack environment
for {set i 0} {$i < $num_clients} {incr i} {
    $ns duplex-link $client($i) $TOR_switch_node $link_cap $link_delay $queue_type
}

# Monitor the queue for link (s1-h3). (for NAM)
$ns duplex-link-op $TOR_switch_node $server_node queuePos 0.5

##Set error model on link n3 to n2
#set loss_module [new ErrorModel]
#$loss_module set rate_ 0.01
#$loss_module ranvar [new RandomVariable/Uniform]
#$loss_module drop-target [new Agent/Null]
#$ns lossmodel $loss_module $TOR_switch_node $server_node

# HOST options
Agent/TCP set window_ $tcp_window
Agent/TCP set windowInit_ 2
Agent/TCP set packetSize_ $pktSize
Agent/TCP/FullTcp set segsize_ $pktSize

# DCTCP settings
if {[string compare $congestion_alg "dctcp"] == 0} {
    Agent/TCP set ecn_ 1
    Agent/TCP set old_ecn_ 1
    Agent/TCP/FullTcp set spa_thresh_ 0
    Agent/TCP set slow_start_restart_ true
    Agent/TCP set windowOption_ 0
    Agent/TCP set tcpTick_ 0.000001
    #Agent/TCP set minrto_ $min_rto
    #Agent/TCP set maxrto_ 2

    Agent/TCP/FullTcp set nodelay_ true; # disable Nagle
    Agent/TCP/FullTcp set segsperack_ $ackRatio;
    Agent/TCP/FullTcp set interval_ 0.000006

    Agent/TCP set ecnhat_ true
    Agent/TCPSink set ecnhat_ true
    Agent/TCP set ecnhat_g_ $DCTCP_g;

    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]        
    
            set tcp($conn_idx) [new Agent/TCP/FullTcp]
            set sink($conn_idx) [new Agent/TCP/FullTcp]
            $ns attach-agent $client($i) $tcp($conn_idx)
            $ns attach-agent $server_node $sink($conn_idx)
            $tcp($conn_idx) set fid_ [expr $conn_idx]
            $sink($conn_idx) set fid_ [expr $conn_idx]
            $ns connect $tcp($conn_idx) $sink($conn_idx)
            # set up TCP-level connections
            $sink($conn_idx) listen
        }
    }
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]

            # set up FTP connections
            set ftp($conn_idx) [$tcp($conn_idx) attach-source FTP]
            $ftp($conn_idx) set type_ FTP 

        }
    }
    # The following procedure is called when ever a packet is received 
    Agent/TCP/FullTcp instproc recv {rtt_t} {
        global ns rtt_file 
        $self instvar fid_
        
        set now [$ns now]
        set rtt [$self set rtt_]
        puts $rtt_file "$now $fid_ $rtt"
    }

} elseif {[string compare $congestion_alg "vegas"] == 0} {    
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]        
        
            set tcp($conn_idx) [new Agent/TCP/Vegas]
                set sink($conn_idx) [new Agent/TCPSink]
                $ns attach-agent $client($i) $tcp($conn_idx)
                $ns attach-agent $server_node $sink($conn_idx)
                $tcp($conn_idx) set fid_ [expr $conn_idx]
                $sink($conn_idx) set fid_ [expr $conn_idx]
                $ns connect $tcp($conn_idx) $sink($conn_idx)
                ## set up TCP-level connections
                #$sink($conn_idx) listen

            $tcp($conn_idx) set timely_ 0

        }
    }
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]

            # set up FTP connections
            set ftp($conn_idx) [new Application/FTP]
            $ftp($conn_idx) set packet_Size_ $pktSize
            $ftp($conn_idx) set interval_ 0.000001
            $ftp($conn_idx) set type_ FTP 
            $ftp($conn_idx) attach-agent $tcp($conn_idx)
        }
    }
    # In vegas, timely_rate_ is just ignored. Hack hack hack.
    Agent/TCP/Vegas instproc recv {rtt_t cong_signal_t hopCnt_t timely_rate_t} {
        global ns rtt_file
        $self instvar fid_
        
        set now [$ns now]
        set rtt [$self set rtt_]
        puts $rtt_file "$now $fid_ $rtt"
    }

} elseif {[string compare $congestion_alg "timely"] == 0} {    
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]        
        
            set tcp($conn_idx) [new Agent/TCP/Vegas]
            set sink($conn_idx) [new Agent/TCPSink]
            $ns attach-agent $client($i) $tcp($conn_idx)
            $ns attach-agent $server_node $sink($conn_idx)
            $tcp($conn_idx) set fid_ [expr $conn_idx]
            $sink($conn_idx) set fid_ [expr $conn_idx]
            $ns connect $tcp($conn_idx) $sink($conn_idx)
            ## set up TCP-level connections
            #$sink($conn_idx) listen

            $tcp($conn_idx) set timely_ 1
            $tcp($conn_idx) set hope_ 0
            $tcp($conn_idx) set timely_packetSize_ $pktSize
            $tcp($conn_idx) set timely_ewma_alpha_ 0.3
            $tcp($conn_idx) set timely_t_low_ 0
            $tcp($conn_idx) set timely_t_high_ 0.0001
            $tcp($conn_idx) set timely_additiveInc_ 20000000.0
            $tcp($conn_idx) set timely_decreaseFac_ 0.8
            $tcp($conn_idx) set timely_HAI_thresh_ 5
            $tcp($conn_idx) set timely_rate_ 500000000
            $tcp($conn_idx) set timely_patched_ 0
            # 0, 50, 100, 150, 200 micro-seconds in the timely paper
            $tcp($conn_idx) set rttNoise_ 0.000025
            # 0.00005
        }
    }
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]

            # set up FTP connections
            set ftp($conn_idx) [new Application/FTP]
            $ftp($conn_idx) set packet_Size_ $pktSize
            $ftp($conn_idx) set interval_ 0.000001
                $ftp($conn_idx) set type_ FTP 
            $ftp($conn_idx) attach-agent $tcp($conn_idx)
        }
    }
    # Timely implementation is also contained in vegas.cc
    Agent/TCP/Vegas instproc recv {rtt_t cong_signal_t hopCnt_t timely_rate_t} {
        global ns rtt_file rate_file pktSize
        $self instvar fid_

        set now [$ns now]
        set rtt [expr $rtt_t * 1000000.0]
        puts $rtt_file "$now $fid_ $rtt"

        # Write current timely send rate, in bits per second!
        puts $rate_file "$now $fid_ $timely_rate_t"
    }

} else {
    puts "Unknown TCP Protocol! Tahao is used instead..."
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
        set conn_idx [expr $i*$num_conn_per_client+$j]        
    
        set tcp($conn_idx) [new Agent/TCP]
            set sink($conn_idx) [new Agent/TCPSink]
            $ns attach-agent $client($i) $tcp($conn_idx)
            $ns attach-agent $server_node $sink($conn_idx)
            $tcp($conn_idx) set fid_ [expr $conn_idx]
            $sink($conn_idx) set fid_ [expr $conn_idx]
            $ns connect $tcp($conn_idx) $sink($conn_idx)
            ## set up TCP-level connections
            #$sink($conn_idx) listen
        }
    }
    for {set i 0} {$i < $num_clients} {incr i} {
        for {set j 0} {$j < $num_conn_per_client} {incr j} {
            set conn_idx [expr $i*$num_conn_per_client+$j]

            # set up FTP connections
            set ftp($conn_idx) [new Application/FTP]
            $ftp($conn_idx) set packet_Size_ $pktSize
            $ftp($conn_idx) set interval_ 0.0001
                $ftp($conn_idx) set type_ FTP 
            $ftp($conn_idx) attach-agent $tcp($conn_idx)
        }
    }
}

# queue monitoring
set qf_size [open $out_q_file w]
set qmon_size [$ns monitor-queue $TOR_switch_node $server_node $qf_size $samp_int]
[$ns link $TOR_switch_node $server_node] queue-sample-timeout

# Create random generator for starting the ftp connections
set rng [new RNG]
$rng seed 0

# Parameters for random variables to ftp start times
set RVstart [new RandomVariable/Uniform]
$RVstart set min_ 0.0001
$RVstart set max_ 0.0020
$RVstart use-rng $rng

# Schedule events for the FTP agents
for {set i 0} {$i < $num_clients} {incr i} {
    for {set j 0} {$j < $num_conn_per_client} {incr j} {
    set conn_idx [expr $i*$num_conn_per_client+$j]        
    
    #set startT($conn_idx) [expr [$RVstart value]]
    #$ns at $startT($conn_idx) "$ftp($conn_idx) start"
    $ns at 0.0001 "$ftp($conn_idx) start"
        $ns at [expr $run_time - 0.01] "$ftp($conn_idx) stop"
    }
}

# Call the finish procedure after run_time seconds of simulation time
$ns at $run_time "finish"

# Define a 'finish' procedure
proc finish {} {
    global congestion_alg ns nf tracefile rtt_file qf_size repro_dir rate_file
    $ns flush-trace
    # Close the NAM trace file
    close $nf
    close $tracefile
    close $rtt_file
    close $rate_file
    close $qf_size
    # Execute NAM on the trace file
    exec nam $repro_dir$congestion_alg.nam &
    exit 0
}

#Run the simulation
$ns run
