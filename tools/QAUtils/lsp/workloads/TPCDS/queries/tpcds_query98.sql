--@author guz4
--@description TPC-DS tpcds_query98
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query98.tpl
select i_item_desc 
      ,i_category 
      ,i_class 
      ,i_current_price
      ,sum(ss_ext_sales_price) as itemrevenue 
      ,sum(ss_ext_sales_price)*100/sum(sum(ss_ext_sales_price)) over
          (partition by i_class) as revenueratio
from	
	store_sales_TABLESUFFIX
    	,item_TABLESUFFIX 
    	,date_dim_TABLESUFFIX
where 
	ss_item_sk = i_item_sk 
  	and i_category in ('Sports', 'Books', 'Home')
  	and ss_sold_date_sk = d_date_sk
	and d_date between cast('1999-02-22' as date) 
				and (cast('1999-02-22' as date) + 30 )
group by 
	i_item_id
        ,i_item_desc 
        ,i_category
        ,i_class
        ,i_current_price
order by 
	i_category
        ,i_class
        ,i_item_id
        ,i_item_desc
        ,revenueratio;

-- end query 1 in stream 0 using template query98.tpl
