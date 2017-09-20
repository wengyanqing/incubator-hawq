--@author guz4
--@description TPC-DS tpcds_query1
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query1.tpl
--modified to speed up the query
with customer_total_return as
 (select sr_customer_sk as ctr_customer_sk
        ,sr_store_sk as ctr_store_sk 
 	,sum(sr_return_amt) as ctr_total_return
 from store_returns_TABLESUFFIX
     ,date_dim_TABLESUFFIX
 where sr_returned_date_sk = d_date_sk 
   and d_year =2000 
 group by sr_customer_sk
         ,sr_store_sk
 -- adding the following qual to speed up the query
 HAVING sum(sr_return_amt) > 6000)
  select  c_customer_id
 from customer_total_return_TABLESUFFIX ctr1
     ,store_TABLESUFFIX
     ,customer_TABLESUFFIX
 where ctr1.ctr_total_return > (select avg(ctr_total_return)*1.2
 			              from customer_total_return_TABLESUFFIX ctr2 
                  	        where ctr1.ctr_store_sk = ctr2.ctr_store_sk)
       and s_store_sk = ctr1.ctr_store_sk
       and s_state = 'TN'
       and ctr1.ctr_customer_sk = c_customer_sk
 order by c_customer_id
 limit 100;

-- end query 1 in stream 0 using template query1.tpl
