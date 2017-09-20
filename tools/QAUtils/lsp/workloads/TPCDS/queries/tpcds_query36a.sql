--@author guz4
--@description TPC-DS tpcds_query34
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query36a.tpl
with results as
 (select 
    sum(ss_net_profit) as ss_net_profit, sum(ss_ext_sales_price) as ss_ext_sales_price,
    sum(ss_net_profit)/sum(ss_ext_sales_price) as gross_margin
   ,i_category
   ,i_class
   ,0 as g_category, 0 as g_class
 from
    store_sales_TABLESUFFIX
   ,date_dim_TABLESUFFIX       d1
   ,item_TABLESUFFIX
   ,store_TABLESUFFIX
 where
    d1.d_year = 2001 
    and d1.d_date_sk = ss_sold_date_sk
    and i_item_sk  = ss_item_sk 
    and s_store_sk  = ss_store_sk
    and s_state in ('TN','TN','TN','TN',
                 'TN','TN','TN','TN')
 group by i_category,i_class)
 ,
 results_rollup as
 (select gross_margin ,i_category ,i_class,0 as t_category, 0 as t_class, 0 as lochierarchy from results
 union
 select sum(ss_net_profit)/sum(ss_ext_sales_price) as gross_margin,
   i_category, NULL AS i_class, 0 as t_category, 1 as t_class, 1 as lochierarchy from results group by i_category
 union
 select sum(ss_net_profit)/sum(ss_ext_sales_price) as gross_margin,
   NULL AS i_category ,NULL AS i_class, 1 as t_category, 1 as t_class, 2 as lochierarchy from results)
  select 
  gross_margin ,i_category ,i_class, lochierarchy,rank() over (
 	partition by lochierarchy, case when t_class = 0 then i_category end 
 	order by gross_margin asc) as rank_within_parent
 from results_rollup
 order by
   lochierarchy desc
  ,case when lochierarchy = 0 then i_category end
  ,rank_within_parent
  limit 100;

-- end query 1 in stream 0 using template query36a.tpl
