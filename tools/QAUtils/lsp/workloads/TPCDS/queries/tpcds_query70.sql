--@author guz4
--@description TPC-DS tpcds_query70
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query70.tpl
select  
    sum(ss_net_profit) as total_sum
   ,s_state
   ,s_county
   ,rank() over (
 	partition by s_state,s_county
 	order by sum(ss_net_profit) desc) as rank_within_parent
 from
    store_sales_TABLESUFFIX
   ,date_dim_TABLESUFFIX       d1
   ,store_TABLESUFFIX
 where
    d1.d_year = 2000
 and d1.d_date_sk = ss_sold_date_sk
 and s_store_sk  = ss_store_sk
 and s_state in
             ( select s_state
               from  (select s_state as s_state,
 			    rank() over ( partition by s_state order by sum(ss_net_profit) desc) as ranking
                      from   store_sales_TABLESUFFIX, store_TABLESUFFIX, date_dim_TABLESUFFIX
                      where  d_year =2000 
 			    and d_date_sk = ss_sold_date_sk
 			    and s_store_sk  = ss_store_sk
                      group by s_state
                     ) tmp1 
               where ranking <= 5
             )
 group by s_state,s_county
 order by
  rank_within_parent
 limit 100;

-- end query 1 in stream 0 using template query70.tpl
