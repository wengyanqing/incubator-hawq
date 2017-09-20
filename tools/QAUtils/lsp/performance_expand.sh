#!/bin/sh

source ~/.bashrc
source ~/qa.sh

export HADOOP_PATH_VAR=/usr/phd/current/

function nodeconfig_fun() {
   if [ $1 != 'stop' ] && [ $1 != 'start' ] ; then
       echo "Please use options: start/stop."   
       exit 1
   fi
   hostlist=$3
   option=$1
   echo "hostlist is " $hostlist
   echo "option is " $option
   if [ "$2" = "HDFS" ]  || [ "$2" = "BOTH" ]; then
       for datanode in $hostlist; do
           echo "datanode is " $datanode
           ssh $datanode sudo $HADOOP_PATH_VAR/hadoop-client/sbin/hadoop-daemon.sh  $option  datanode
       done
   fi

   if [ "$2" = "HAWQ" ] || [ "$2" = "BOTH" ]; then
       for hawqnode in $hostlist; do
           ssh $hawqnode "source $GPHOME/greenplum_path.sh;hawq $option segment -a"
       done
   fi

   if [ "$2" = "NAMENODE" ]; then
       for namenode in $hostlist; do
           ssh $namenode sudo -u hdfs $HADOOP_PATH_VAR/hadoop-client/sbin/hadoop-daemon.sh  $option  namenode
       done
       if [ $1 = 'start' ] ; then
           sleep 180
           $HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -safemode leave
           sleep 180
           $HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -safemode get
       fi
   fi
}

### $1 schedule $2 log name
function runworkload() {
    echo $3
    if [ "$3" = "HAWQ" ] || [ "$3" = "BOTH" ]; then   
        sleep 120
    fi
    psql -d postgres -c "select * from gp_segment_configuration;"  >> $2 2>&1
    if [ "$3" = "HDFS" ] || [ "$3" = "BOTH" ]; then  
        for((i=1;i<20;i++))
        do
            a=`sudo -u hdfs $HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -report -dead | grep "Dead datanodes" | cut -d '(' -f 2 |cut -d ')' -f 1`
            echo "No $i Fetch dead node is $a" >>$2      
            if [[ $? != 0 ]];
            then
                echo "Hdfs error, Please check HDFS seting"
                exit
            fi
            if [[ "$a" > 0 ]];
            then
                echo "Report the dead node $a"
                break
            fi
            python -u lsp.py -s $1  >> $2 2>&1
            sleep 30
        done
    fi
    for i in bcn-mst1 bcn-mst2 bcn-w{1..16}; do ssh ${i} "hostname; ps -ef | grep [j]ava|wc"; done >> $2 2>&1 
    python -u lsp.py -s $1  >> $2 2>&1
}

SUCCESS="The cluster is balanced"
SIGN="CONTINUE"
### $1 find success in the logfile, $2 log file to log
function check_successed_or_failed() {
    if grep -Fq "$SUCCESS" $1
    then
        date >> $2 2>&1
        echo "Find success: \"The cluster is balanced.\"" >> $2 2>&1
        SIGN="SUCCESS"
    else
        date >> $2 2>&1
        echo "Not found success or fail signal yet." >> $2 2>&1
        SIGN="CONTINUE"
        sleep 600
    fi
}
## each check, if continue, sleep 600s (10 mins) . so check times 144 means the timeout is 24 hours.
## $1 log name
function check_balancer_finished(){
    TOTAL_CHECK=144
    COUNT=144
    while [ $SIGN = "CONTINUE" ]
    do
        check_successed_or_failed $1 $1
        COUNT=`expr $COUNT - 1`
        date >> $1 2>&1
        echo "This is the `expr $TOTAL_CHECK - $COUNT` times check." >> $1 2>&1
        if [ $COUNT = 0 ]
        then
            SIGN="TIMEOUT"
        fi
    done
}


######### make hawq 8 nodes and restart all ##########################################
hawq config -c default_segment_num -v 64 --skipvalidation
hawq stop cluster -a
cp ./expand/slaves_8 $GPHOME/etc/slaves
hawq start cluster -a
localhdfs stop HA
localhdfs start HA

echo "echo GPHOME"
echo $GPHOME
##########Current There are 8 Nodes. Load Data into them##############################
gpssh -f ~/hostfile -e "sudo chmod 666 /usr/phd/current/hadoop-client/etc/hadoop/slaves"
echo "=================configured to 8 Nodes with HAWQ and HDFS========================="   > ./performance_tpch_nodechange_8node.log 2>&1
gpscp -f ~/hostfile ./expand/slaves_8 =:$HADOOP_PATH_VAR/hadoop-client/etc/hadoop/slaves   >> ./performance_tpch_nodechange_8node.log 2>&1
nodeconfig_fun stop  BOTH "bcn-w16 bcn-w15 bcn-w14 bcn-w13 bcn-w12 bcn-w11 bcn-w10 bcn-w9" >> ./performance_tpch_nodechange_8node.log 2>&1
nodeconfig_fun stop  NAMENODE "bcn-mst2 bcn-mst1"                                          >> ./performance_tpch_nodechange_8node.log 2>&1
nodeconfig_fun start NAMENODE "bcn-mst2 bcn-mst1"                                          >> ./performance_tpch_nodechange_8node.log 2>&1
sleep 300 

$HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -report -live                             >> ./performance_tpch_nodechange_8node.log 2>&1
psql -d postgres -c "select * from gp_segment_configuration;"                              >> ./performance_tpch_nodechange_8node.log 2>&1
psql -d postgres -c "drop table if exists test;"                                           >> ./performance_tpch_nodechange_8node.log 2>&1
psql -d postgres -c "create table test(a int); insert into test values (1);"               >> ./performance_tpch_nodechange_8node.log 2>&1
echo "================= run workload in 8 hawq and 8 hdfs=============================="   >> ./performance_tpch_nodechange_8node.log 2>&1
python -u lsp.py -s performance_tpch_nodechange                                            >> ./performance_tpch_nodechange_8node.log 2>&1
$HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -report -live                             >> ./performance_tpch_nodechange_8node.log 2>&1

##########without load data again, without balanced, expand to 16 hawq and 16 hdfs###
echo "================expand to 16 hawq and 16 hdfs ==================================="      > ./performance_tpch_nodechange_16node.log 2>&1
gpscp -f ~/hostfile ./expand/slaves_16 =:$HADOOP_PATH_VAR/hadoop-client/etc/hadoop/slaves    >> ./performance_tpch_nodechange_16node.log 2>&1
cp expand/slaves_16 $GPHOME/etc/slaves
nodeconfig_fun start HAWQ "bcn-w16 bcn-w15 bcn-w14 bcn-w13 bcn-w12 bcn-w11 bcn-w10 bcn-w9"   >> ./performance_tpch_nodechange_16node.log 2>&1
localhdfs stop  HA  >> ./performance_tpch_nodechange_16node.log 2>&1
localhdfs start HA  >> ./performance_tpch_nodechange_16node.log 2>&1
sleep 120
$HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -report -live               >> ./performance_tpch_nodechange_16node.log 2>&1
psql -d postgres -c "select * from gp_segment_configuration;"                >> ./performance_tpch_nodechange_16node.log 2>&1
psql -d postgres -c "drop table if exists test;"                             >> ./performance_tpch_nodechange_16node.log 2>&1
psql -d postgres -c "create table test(a int); insert into test values (1);" >> ./performance_tpch_nodechange_16node.log 2>&1
echo "=========run workload in 16 hawq and 16 hdfs without balance========"  >> ./performance_tpch_nodechange_16node.log 2>&1
python -u lsp.py -s performance_tpch_nodechange_noload                       >> ./performance_tpch_nodechange_16node.log 2>&1

########### do data balance and run workload ########################################
## It is for temporary disable the bug
date  > ./performance_tpch_nodechange_16node_dobalance.log 2>&1
$HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -setBalancerBandwidth 4294967296 >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
$HADOOP_PATH_VAR/hadoop-client/bin/hdfs balancer -threshold 1                     >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
echo "============================= do balancer ================================" >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
date >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
sleep 300

## check balancer finished or not. it will check every 600s(10mins) and timeout is 24h(144times)
check_balancer_finished ./performance_tpch_nodechange_16node_dobalance.log
## if balancer finished then run workload, if timeout then exit.    
if [ $SIGN = "SUCCESS" ]
then
    date                                              > ./performance_tpch_nodechange_16node_balance.log 2>&1
    echo "Balancer finished. Starting run workloads" >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    ### run workload
    $HADOOP_PATH_VAR/hadoop-client/bin/hdfs dfsadmin -report -live               >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    psql -d postgres -c "select * from gp_segment_configuration;"                >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    psql -d postgres -c "drop table if exists test;"                             >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    psql -d postgres -c "create table test(a int); insert into test values (1);" >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    echo "=====run workload in 16 hawq and 16 hdfs after balance with cache==="  >> ./performance_tpch_nodechange_16node_balance.log 2>&1
    python -u lsp.py -s performance_tpch_nodechange_noload                       >> ./performance_tpch_nodechange_16node_balance.log 2>&1

    psql -d postgres -c "select gp_metadata_cache_clear();"                       > ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
    psql -d postgres -c "select * from gp_segment_configuration;"                >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
    psql -d postgres -c "drop table if exists test;"                             >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
    psql -d postgres -c "create table test(a int); insert into test values (1);" >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1 
    echo "== run workload in 16 hawq and 16 hdfs after balance without cache=="  >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
    python -u lsp.py -s performance_tpch_nodechange_noload                       >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
    echo "Ending run workloads"                                                  >> ./performance_tpch_nodechange_16node_balance_withoutcache.log 2>&1
else
    if [ $SIGN = "TIMEOUT" ]
    then
        date                        >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
        echo "Exit due to timeout." >> ./performance_tpch_nodechange_16node_dobalance.log 2>&1
    fi
fi
