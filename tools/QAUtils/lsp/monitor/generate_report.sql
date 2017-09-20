mx------------------
Schema Creation
---------------------
DROP TABLE IF EXISTS test_result_info;
CREATE TABLE test_result_info 
(wl_name varchar(512),
 action_type varchar(50),
 action_target varchar(128),
 wl_concurrency int,
 stream int,
 start_time  timestamp with time zone,
 end_time timestamp with time zone,
 con_id int);

DROP TABLE IF EXISTS test_result_info_stat;
CREATE TABLE test_result_info_stat
(wl_name varchar(512),
 query_name  varchar(128),
 start_time  timestamp with time zone,
 end_time timestamp with time zone);


DROP TABLE IF EXISTS query_seg_stat_info;
DROP TABLE IF EXISTS query_master_stat_info;
CREATE TABLE query_seg_stat_info (
        workload_name varchar(512),
        query_name varchar(512),
        stream int,
        segnum int,
        pmem_max  decimal(8,2),
        pmem_avg   decimal(8,2),
        pmem_min   decimal(8,2), 
        pmemratio    decimal(8,2),
        pcpu_max    decimal(8,2),
        pcpu_avg    decimal(8,2),
        pcpu_min    decimal(8,2),
        pcpuratio     decimal(8,2),
        rss_max      decimal(8,2),
        rss_avg       decimal(8,2),
        rss_min      decimal(8,2),
        rssratio      decimal(8,2));
 
CREATE TABLE query_master_stat_info (
        workload_name varchar(512),
        query_name varchar(512),
        stream int,
        pmem_max  decimal(8,2),
        pcpu_max    decimal(8,2),
        rss_max      decimal(8,2)
        );
        

-------------------
Data Preparion
1. Generate Time slot for each query
2. Generate cpu and memory data for each QE per connection
3. Generate cpu and memory data for each QD  per connection
4. Generate qd&qe nodes level information
5. Generate QD/QE for query base 

---------------------
DROP FUNCTION if exists hst.f_monitordata_transform(idlist varchar(100));
CREATE OR REPLACE FUNCTION hst.f_monitordata_transform(idlist varchar(100))
RETURNS INTEGER
AS $$
BEGIN
  set search_path = hst;
   
  TRUNCATE test_result_info;
  INSERT INTO test_result_info
    SELECT
      CASE WHEN w.wl_concurrency > 1 THEN (w.wl_name || '_CONCURRENT')::VARCHAR(512)
      ELSE w.wl_name END wl_name,
      ts.action_type, ts.action_target,
      w.wl_concurrency, ts.stream, ts.start_time, ts.end_time, con_id
    FROM hst.test_result AS ts, scenario s, workload w
    WHERE ts.s_id= s.s_id and w.wl_id = s.wl_id
          AND ts.status != 'SKIP'
          AND ts.tr_id in (idlist) ;

   TRUNCATE test_result_info_stat;
   INSERT INTO test_result_info_stat
       SELECT  wl_name,
               CASE WHEN ts.action_type = 'Loading' THEN ts.action_type  ELSE action_target END AS action_target,
               MIN(ts.start_time) as start_time, MAX(ts.end_time) AS end_time
       FROM test_result_info TS
       WHERE wl_name not like '%_CONCURRENT%'
       GROUP BY wl_name, CASE WHEN ts.action_type = 'Loading' THEN ts.action_type  ELSE action_target END
       UNION
       SELECT wl_name,'CONCURRENT',
             MIN(ts.start_time) as start_time, MAX(ts.end_time) AS end_time
      FROM test_result_info ts
      WHERE wl_name like '%_CONCURRENT%'
      GROUP BY wl_name;

  TRUNCATE qe_mem_cpu_per_seg_con;
  INSERT INTO qe_mem_cpu_per_seg_con
    SELECT run_id, hostname, timeslot,
      min(real_time) as begintime,con_id, seg_id,
      SUM(rss) AS rss, SUM(pmem) AS pmem, SUM(pcpu) AS pcpu
    FROM qe_mem_cpu
    WHERE run_id in (idlist) 
    GROUP BY run_id, hostname, timeslot, con_id, seg_id ;

  TRUNCATE qd_mem_cpu_per_con;
  INSERT INTO qd_mem_cpu_per_con
    SELECT run_id, hostname, timeslot,
      min(real_time) as begintime, con_id,
      SUM(rss) AS rss, SUM(pmem) AS pmem, SUM(pcpu) AS pcpu
    FROM qd_mem_cpu
    WHERE run_id in (idlist) 
    GROUP BY run_id, hostname, timeslot, con_id;

  TRUNCATE qde_mem_cpu_per_node;
  INSERT INTO qde_mem_cpu_per_node
    SELECT hostname, 'QE' as role, timeslot, begintime,
      SUM(rss) AS rss, SUM(pmem) AS pmem, SUM(pcpu) AS pcpu,
      COUNT(*) AS segnum
    FROM qe_mem_cpu_per_seg_con
    GROUP BY hostname,timeslot, begintime
    UNION
    SELECT hostname, 'QD' as role, timeslot, begintime,
      sum(rss), sum(pmem), sum(pcpu),
      COUNT(*) AS segnum
    FROM qd_mem_cpu_per_con
    GROUP BY hostname, timeslot, begintime;

RETURN 0;
END
$$ LANGUAGE PLPGSQL;



--------
DATA Analysis Per Query and Node
1. Get query start time and end time
2. Get stat info between start time and end time
3. Get info 
    For Segment:1) get segment count 2) get max/avg/min usage for those segments 
    For Master 1) get useage for master
----------------
DROP FUNCTION IF EXISTS f_generate_query_stat();
CREATE OR REPLACE FUNCTION f_generate_query_stat()
RETURNS INTEGER
AS $$
DECLARE 
      qe_cur REFCURSOR;
      v_count int;
      v_i int;
      v_con_id int;
      v_wl_name varchar(512);
      v_query_name varchar(512);
      v_stream int;
      v_start_time timestamp with time zone;
      v_end_time timestamp with time zone;
BEGIN
      v_i := 1;
      TRUNCATE query_seg_stat_info;
      TRUNCATE query_master_stat_info;
      SELECT COUNT(*) INTO v_count FROM test_result_info;
      OPEN qe_cur FOR SELECT wl_name, case when action_type = 'Loading' then action_type || '_' || action_target else action_target end, stream, start_time, end_time, con_id FROM test_result_info;
      WHILE v_i <= v_count loop
         FETCH qe_cur INTO v_wl_name, v_query_name, v_stream, v_start_time, v_end_time, v_con_id;
         INSERT INTO query_seg_stat_info 
         SELECT v_wl_name, v_query_name, v_stream,
                COUNT(*) AS segnum,
                max(qes.pmem)::decimal(8,2) as pmem_max, 
                avg(qes.pmem)::decimal(8,2) as pmem_avg, 
                min(qes.pmem)::decimal(8,2) as pmem_min, 
                CASE WHEN min(qes.pmem) = 0 THEN 0 ELSE (max(qes.pmem) / min(qes.pmem))::decimal(8,2) END as pmemratio,
                max(qes.pcpu)::decimal(8,2) as pcpu_max,
                avg(qes.pcpu)::decimal(8,2) as pcpu_avg,
                min(qes.pcpu)::decimal(8,2) as pcpu_min,  
                CASE WHEN min(qes.pcpu) = 0 THEN 0 ELSE (max(qes.pcpu) / min(qes.pcpu))::decimal(8,2) END as pcpuratio,
                max(qes.rss)::decimal(8,2)  as rss_max,
                avg(qes.rss)::decimal(8,2)  as rss_avg,
                min(qes.rss)::decimal(8,2) as rss_min, 
                CASE WHEN min(qes.rss) = 0 THEN 0 ELSE  (max(qes.rss) / min(qes.rss))::decimal(8,2)  END as rssratio
             FROM ( SELECT qe.hostname||'-' ||qe.seg_id, 
                           max(qe.pmem) as pmem, 
                           max(qe.pcpu) as pcpu, 
                           max(qe.rss) as rss 
                    FROM qe_mem_cpu_per_seg_con AS qe
                    WHERE  qe.begintime >=  v_start_time AND qe.begintime <  v_end_time 
                       and qe.con_id = v_con_id
                    GROUP BY qe.hostname||'-'||qe.seg_id) AS qes;
             INSERT INTO query_master_stat_info 
             SELECT  v_wl_name, v_query_name, v_stream,
                     max(qd.pmem) as pmem, 
                     max(qd.pcpu) as pcpu, 
                     max(qd.rss) as rss 
             FROM qd_mem_cpu_per_con as qd
             WHERE  qd.begintime >=  v_start_time AND qd.begintime <  v_end_time  and qd.con_id = v_con_id;
             v_i = v_i + 1;
      END LOOP;
      CLOSE qe_cur;
RETURN v_i;
END
$$ LANGUAGE PLPGSQL;
SELECT f_generate_query_stat();
SELECT * FROM query_seg_stat_info;
SELECT * FROM query_master_stat_info;



DROP FUNCTION IF EXISTS f_get_host_monitor_info();
CREATE OR REPLACE FUNCTION f_get_host_monitor_info()
RETURNS INTEGER
AS $$
DECLARE 
	    qe_cur REFCURSOR;
	    v_count int;
	    v_i int;
            v_wl_name varchar(512);
            v_query_name varchar(512);
            v_start_time timestamp with time zone;
            v_end_time timestamp with time zone;
            v_timebound int;
BEGIN
        TRUNCATE qde_monitorinfo;
        SELECT COUNT(*) INTO v_count FROM test_result_info_stat;
      	v_i := 1;
        OPEN qe_cur FOR SELECT * FROM test_result_info_stat ts order by start_time;
      	WHILE v_i <= v_count loop
	        FETCH qe_cur INTO v_wl_name, v_query_name, v_start_time, v_end_time;
                 SELECT MIN(timeslot) INTO v_timebound from qde_mem_cpu_per_node qde where qde.begintime BETWEEN v_start_time AND v_end_time;
                 INSERT INTO 	qde_monitorinfo 
                 SELECT v_wl_name, v_query_name, 'memory',   
                               qde.timeslot, 
                                MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.rss ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.rss ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.rss ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.rss ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.rss ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.rss ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.rss ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.rss ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.rss ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.rss ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.rss ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.rss ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.rss ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.rss ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.rss ELSE 0 END) as w14, 
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.rss ELSE 0 END) as w15, 
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.rss ELSE 0 END) as w16, 
                              min(qde.begintime), 
                              max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 0 END) as maxrss,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 0 END)/16 as avgrss,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 9999999 END) as minrss,
                               32000
	             FROM qde_mem_cpu_per_node as qde
                 WHERE qde.timeslot = v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time 
                 GROUP BY qde.timeslot;

                 INSERT INTO 	qde_monitorinfo 
                 SELECT v_wl_name, v_query_name, 'memory',   
                               qde.timeslot, 
                                MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.rss ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.rss ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.rss ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.rss ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.rss ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.rss ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.rss ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.rss ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.rss ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.rss ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.rss ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.rss ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.rss ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.rss ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.rss ELSE 0 END) as w14, 
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.rss ELSE 0 END) as w15, 
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.rss ELSE 0 END) as w16, 
                              min(qde.begintime),
                            max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 0 END) as maxrss,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 0 END)/16 as avgrss,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.rss ELSE 9999999 END) as minrss ,
                               0
	         FROM qde_mem_cpu_per_node as qde
	         WHERE qde.timeslot != v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time 
                 GROUP BY qde.timeslot;


                 INSERT INTO 	qde_monitorinfo 
                 SELECT v_wl_name, v_query_name, 'cpu',   
                               qde.timeslot, 
                                  MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.pcpu ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.pcpu ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.pcpu ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.pcpu ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.pcpu ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.pcpu ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.pcpu ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.pcpu ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.pcpu ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.pcpu ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.pcpu ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.pcpu ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.pcpu ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.pcpu ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.pcpu ELSE 0 END) as w14, 
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.pcpu ELSE 0 END) as w15, 
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.pcpu ELSE 0 END) as w16, 
                              min(qde.begintime),
                            max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 0 END) as maxcpu,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 0 END)/16 as avgcpu,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 9999999 END) as mincpu,
                              32000
	         FROM qde_mem_cpu_per_node as qde
	         WHERE qde.timeslot = v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time
                 GROUP BY qde.timeslot;

                 INSERT INTO 	qde_monitorinfo 
                 SELECT v_wl_name, v_query_name, 'cpu',   
                               qde.timeslot, 
                                  MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.pcpu ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.pcpu ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.pcpu ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.pcpu ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.pcpu ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.pcpu ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.pcpu ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.pcpu ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.pcpu ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.pcpu ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.pcpu ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.pcpu ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.pcpu ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.pcpu ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.pcpu ELSE 0 END) as w14, 
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.pcpu ELSE 0 END) as w15, 
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.pcpu ELSE 0 END) as w16, 
                              min(qde.begintime),
                            max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 0 END) as maxcpu,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 0 END)/16 as avgcpu,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.pcpu ELSE 9999999 END) as mincpu ,
                              0
	         FROM qde_mem_cpu_per_node as qde
	         WHERE qde.timeslot != v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time
                 GROUP BY qde.timeslot;
                          INSERT INTO    qde_monitorinfo
                 SELECT v_wl_name, v_query_name, 'segnum',
                               qde.timeslot,
                                MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.segnum ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.segnum ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.segnum ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.segnum ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.segnum ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.segnum ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.segnum ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.segnum ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.segnum ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.segnum ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.segnum ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.segnum ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.segnum ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.segnum ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.segnum ELSE 0 END) as w14,
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.segnum ELSE 0 END) as w15,
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.segnum ELSE 0 END) as w16,
                              min(qde.begintime),
                            max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 0 END) as maxsegnum,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 0 END)/16 as avgsegnum,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 9999999 END) as minsegnum,
                               32000
                 FROM qde_mem_cpu_per_node as qde
                 WHERE qde.timeslot = v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time
                 GROUP BY qde.timeslot;

                 INSERT INTO    qde_monitorinfo
                 SELECT v_wl_name, v_query_name, 'segnum',
                               qde.timeslot,
                                MAX(CASE WHEN qde.hostname = 'gva-mst1' THEN qde.segnum ELSE 0 END) as mst1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w1' THEN qde.segnum ELSE 0 END) as w1,
                                 MAX(CASE WHEN qde.hostname = 'gva-w2' THEN qde.segnum ELSE 0 END) as w2,
                                MAX(CASE WHEN qde.hostname = 'gva-w3' THEN qde.segnum ELSE 0 END) as w3,
                                MAX(CASE WHEN qde.hostname = 'gva-w4' THEN qde.segnum ELSE 0 END) as w4,
                                MAX(CASE WHEN qde.hostname = 'gva-w5' THEN qde.segnum ELSE 0 END) as w5,
                                MAX(CASE WHEN qde.hostname = 'gva-w6' THEN qde.segnum ELSE 0 END) as w6,
                               MAX(CASE WHEN qde.hostname = 'gva-w7' THEN qde.segnum ELSE 0 END) as w7,
                              MAX(CASE WHEN qde.hostname = 'gva-w8' THEN qde.segnum ELSE 0 END) as w8,
                              MAX(CASE WHEN qde.hostname = 'gva-w9' THEN qde.segnum ELSE 0 END) as w9,
                               MAX(CASE WHEN qde.hostname = 'gva-w10' THEN qde.segnum ELSE 0 END) as w10,
                               MAX(CASE WHEN qde.hostname = 'gva-w11' THEN qde.segnum ELSE 0 END) as w11,
                               MAX(CASE WHEN qde.hostname = 'gva-w12' THEN qde.segnum ELSE 0 END) as w12,
                               MAX(CASE WHEN qde.hostname = 'gva-w13' THEN qde.segnum ELSE 0 END) as w13,
                               MAX(CASE WHEN qde.hostname = 'gva-w14' THEN qde.segnum ELSE 0 END) as w14,
                              MAX(CASE WHEN qde.hostname = 'gva-w15' THEN qde.segnum ELSE 0 END) as w15,
                              MAX(CASE WHEN qde.hostname = 'gva-w16' THEN qde.segnum ELSE 0 END) as w16,
                              min(qde.begintime),
                            max(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 0 END) as maxsegnum,
                            sum(CASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 0 END)/16 as avgsegnum,
                            min(cASE WHEN qde.hostname != 'gva-mst1' THEN qde.segnum ELSE 9999999 END) as minsegnum,
                               0
             FROM qde_mem_cpu_per_node as qde
             WHERE qde.timeslot != v_timebound and qde.begintime BETWEEN v_start_time AND v_end_time
                 GROUP BY qde.timeslot;
            v_i = v_i + 1;
      END LOOP;
      CLOSE qe_cur;
      RETURN v_i;
END
$$ LANGUAGE PLPGSQL;

select  f_get_host_monitor_info();
select * from qde_monitorinfo order by workload, timeslot;
select workload, query_name, timeslot, mst1, w1,w2,w3,timebound from qde_monitorinfo where type = 'cpu' order by begintime, timeslot limit 200;


DROP FUNCTION if exists hst.f_generate_monitor_report(varchar(100), boolean);
CREATE OR REPLACE FUNCTION hst.f_generate_monitor_report(idlist varchar(100), isclear boolean)
RETURNS INTEGER
AS $$
BEGIN
  set search_path = hst;
  PERFORM f_monitordata_transform(idlist);
  PERFORM f_generate_query_stat();
  PERFORM f_get_host_monitor_info();
  IF isclear THEN
    INSERT INTO hst.qd_info_history select * from hst.qd_info WHERE run_id between start_id and end_id;
    TRUNCATE TABLE hst.qd_info;

    INSERT INTO hst.qd_mem_cpu_history select * from hst.qd_mem_cpu WHERE run_id between start_id and end_id;
    TRUNCATE TABLE hst.qd_mem_cpu;

    INSERT INTO hst.qe_mem_cpu_history select * from hst.qe_mem_cpu WHERE run_id between start_id and end_id;
    TRUNCATE TABLE hst.qe_mem_cpu;
  END IF;

RETURN 0;
END
$$ LANGUAGE PLPGSQL;


grant all on  qde_mem_cpu_per_node to hawq_cov;


---------------------------------------------------------------------------------------------------------------
INSERT INTO hst.qd_info select * from hst.qd_info_history WHERE run_id in (116,117,118,119);
TRUNCATE TABLE hst.qd_info_history;

INSERT INTO hst.qd_mem_cpu select * from hst.qd_mem_cpu_history WHERE run_id in (116,117,118,119);
TRUNCATE TABLE hst.qd_mem_cpu_history;

INSERT INTO hst.qe_mem_cpu select * from hst.qe_mem_cpu_history WHERE run_id in (116,117,118,119);
TRUNCATE TABLE hst.qe_mem_cpu_history;

create table hawq1212_query_master_stat_info_v1 as select * from hawq1212_query_master_stat_info;
create table hawq1212_query_seg_stat_info_v1 as select * from hawq1212_query_seg_stat_info;
create table hawq1212_qde_monitorinfo_v1 as select * from hawq1212_qde_monitorinfo;
create table hawq1212_test_result_info_v1 as select * from hawq1212_test_result_info;




drop table if exists hawq1212_query_master_stat_info;
drop table if exists hawq1212_query_seg_stat_info;
drop table if exists hawq1212_qde_monitorinfo;
drop table if exists hawq1212_test_result_info;

create table hawq1212_query_master_stat_info as select * from query_master_stat_info;
create table hawq1212_query_seg_stat_info as select * from query_seg_stat_info;
create table hawq1212_qde_monitorinfo as select * from qde_monitorinfo;
create table hawq1212_test_result_info as select * from test_result_info;

grant all on hawq1212_query_master_stat_info to hawq_cov;
grant all on hawq1212_query_seg_stat_info to hawq_cov;
grant all on hawq1212_qde_monitorinfo to hawq_cov;
grant all on hawq1212_test_result_info to hawq_cov;

DROP FUNCTION IF EXISTS f_get_scenario_info(test_run_id INT);
CREATE OR REPLACE FUNCTION f_get_scenario_info(test_run_id INT)
RETURNS TEXT
AS $$
DECLARE
        qe_cur REFCURSOR;
        v_count int;
        v_i int;
        v_sid varchar(10);
        v_query_str varchar(1000);
        v_ctl_string varchar(1000);
BEGIN
    DROP TABLE if exists hst.parameter_tuning;
        v_ctl_string = 'CREATE TABLE hst.parameter_tuning (wl_name varchar(512), action_type varchar(128), action_target varchar(512), ';
        v_query_str = 'INSERT INTO hst.parameter_tuning SELECT action_type, action_target,';
        v_i = 1;
        SELECT count(DISTINCT s_id) into v_count from test_result where tr_id = 156;
        OPEN qe_cur FOR SELECT DISTINCT s_id::varchar(10) FROM  test_result where tr_id = 156;
        WHILE v_i <= v_count loop
            FETCH qe_cur INTO v_sid;
            v_ctl_string = v_ctl_string ||'P'|| v_i::char(1) || ' int' ;
            v_query_str = v_query_str || 'MAX(CASE WHEN ts.s_id =' || v_sid || ' THEN ts.duration ELSE 0 END) ' ;
            IF (v_i <> v_count) THEN
                  v_query_str = v_query_str || ',';
                  v_ctl_string = v_ctl_string || ',';
            END IF;

            v_i = v_i + 1;
        END LOOP;
        CLOSE qe_cur;
        v_query_str = v_query_str  || ' FROM hst.f_precompute_test_result(156) AS ts GROUP BY action_type, action_target order by action_type, action_target ;';
        v_ctl_string = v_ctl_string || ');';
        EXECUTE v_ctl_string;
        EXECUTE v_query_str;
        RETURN v_ctl_string;
END
$$ LANGUAGE PLPGSQL;


select  f_get_scenario_info(1);   



drop table parameters;
CREATE TABLE parameters(param_value varchar(20), run_id int, param_name varchar(64));

INSERT INTO parameters VALUES('SEG4', 233), ('SEG4', 234),('SEG4', 235), ('SEG4', 236), ('SEG4', 237);
INSERT INTO parameters VALUES('SEG8', 242), ('SEG8', 243),('SEG8', 244);
INSERT INTO parameters VALUES('SEG12', 236);
INSERT INTO parameters VALUES('SEG10', 236);

DROP FUNCTION IF EXISTS f_get_parameter_tuning_report();
CREATE OR REPLACE FUNCTION f_get_parameter_tuning_report()
RETURNS TEXT
AS $$
DECLARE
        qe_cur REFCURSOR;
        v_pcount int;
        v_i int;
        v_pname varchar(20);
        v_crt_string varchar(1000);
        v_ctl_string varchar(1000);
        v_from_list varchar(500);
        v_minrid INT;
        v_maxrid int; 
        v_tmp_tbl varchar(20);
        v_alias_tbl varchar(5);
        v_cnt int;
BEGIN
       DROP TABLE if exists hst.parameter_tuning;
        v_ctl_string = 'CREATE TABLE HST.parameter_tuning  AS SELECT p1.s_id,  p1.action_type, p1.action_target';
        v_i = 1;
        SELECT count(DISTINCT param_name) into v_pcount from parameters;         
        OPEN qe_cur FOR SELECT param_name, count(*) as cnt FROM  parameters GROUP BY PARAM_NAME order by cnt desc;
        WHILE v_i <= v_pcount loop 
            FETCH qe_cur INTO v_pname, v_cnt;
            SELECT MIN(run_id) into v_minrid FROM parameters WHERE param_name = v_pname;
            SELECT MAX(run_id) into v_maxrid FROM parameters WHERE param_name = v_pname;
            v_tmp_tbl = 'tmp_param_' || v_i::varchar(2);
            v_alias_tbl = 'p' || v_i::varchar(2);
            v_crt_string = 'CREATE TEMP TABLE ' || v_tmp_tbl ||  ' ON COMMIT DROP AS SELECT s_id, action_type, action_target , duration ';
            v_crt_string  = v_crt_string || 'FROM hst.f_precompute_test_result(' || v_minrid::varchar(4) ||','  || v_maxrid::varchar(4) || ');';
            EXECUTE v_crt_string;
            v_ctl_string = v_ctl_string || ' ,p' || v_i::varchar(2) ||'.duration as ' || v_pname;
            IF v_i = 1 THEN
                v_from_list = ' FROM ' ||  v_tmp_tbl || ' AS '|| v_alias_tbl;
            ELSE 
                 v_from_list = v_from_list || ' LEFT JOIN ' ||  v_tmp_tbl || ' AS '|| v_alias_tbl || ' ON p1.s_id = ' || v_alias_tbl || '.s_id' || ' AND p1.action_target = ' || v_alias_tbl || '.action_target';
            END IF;
             v_i = v_i + 1;
        END LOOP;
        CLOSE qe_cur;
        v_ctl_string = v_ctl_string || v_from_list || ';';
        EXECUTE v_ctl_string;
        RETURN v_ctl_string;
END
$$ LANGUAGE PLPGSQL;

select f_get_parameter_tuning_report();


DROP FUNCTION IF EXISTS hst.f_get_parameter_tuning_report(p_name varchar(64));
CREATE OR REPLACE FUNCTION hst.f_get_parameter_tuning_report(p_name varchar(64))
RETURNS TEXT
AS $$
DECLARE
        qe_cur REFCURSOR;
        v_pcount int;
        v_i int;
        v_pvalue varchar(20);
        v_crt_string varchar(1000);
        v_ctl_string varchar(1000);
        v_from_list varchar(500);
        v_minrid INT;
        v_maxrid int; 
        v_tmp_tbl varchar(20);
        v_alias_tbl varchar(5);
        v_cnt int;
BEGIN
       DROP TABLE if exists hst.parameter_tuning;
        v_ctl_string = 'CREATE TABLE HST.parameter_tuning  AS SELECT p1.s_id,  p1.action_type, p1.action_target';
        v_i = 1;
        SELECT count(DISTINCT param_value) into v_pcount from parameters where param_name = p_name;         
        OPEN qe_cur FOR SELECT param_value, count(*) as cnt FROM  parameters where param_name = p_name GROUP BY param_value order by cnt desc;
        WHILE v_i <= v_pcount loop 
            FETCH qe_cur INTO v_pvalue, v_cnt;
            SELECT MIN(run_id) into v_minrid FROM parameters WHERE param_value = v_pvalue;
            SELECT MAX(run_id) into v_maxrid FROM parameters WHERE param_value = v_pvalue;
            v_tmp_tbl = 'tmp_param_' || v_i::varchar(2);
            v_alias_tbl = 'p' || v_i::varchar(2);
            v_crt_string = 'CREATE TEMP TABLE ' || v_tmp_tbl ||  ' ON COMMIT DROP AS SELECT s_id, action_type, action_target , duration ';
            v_crt_string  = v_crt_string || 'FROM hst.f_precompute_test_result(' || v_minrid::varchar(4) ||','  || v_maxrid::varchar(4) || ');';
            EXECUTE v_crt_string;
            v_ctl_string = v_ctl_string || ' ,p' || v_i::varchar(2) ||'.duration as ' || '"' || v_pvalue || '"';
            IF v_i = 1 THEN
                v_from_list = ' FROM ' ||  v_tmp_tbl || ' AS '|| v_alias_tbl;
            ELSE 
                 v_from_list = v_from_list || ' LEFT JOIN ' ||  v_tmp_tbl || ' AS '|| v_alias_tbl || ' ON p1.s_id = ' || v_alias_tbl || '.s_id' || ' AND p1.action_target = ' || v_alias_tbl || '.action_target';
            END IF;
             v_i = v_i + 1;
        END LOOP;
        CLOSE qe_cur;
        v_ctl_string = v_ctl_string || v_from_list || ';';
        EXECUTE v_ctl_string;
        RETURN v_ctl_string;
END
$$ LANGUAGE PLPGSQL;

select f_get_parameter_tuning_report('SEG_NUM');
select f_get_parameter_tuning_report('RESOURCE_UPPER_FACTOR');
select f_get_parameter_tuning_report('MEMORY_LIMIT_CLUSTER');
