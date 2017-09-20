--@author guz4
--@description TPC-DS tpcds_query78
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query78.tpl
with ws as
  (select d_year AS ws_sold_year, ws_item_sk,
    ws_bill_customer_sk ws_customer_sk,
    sum(ws_quantity) ws_qty,
    sum(ws_wholesale_cost) ws_wc,
    sum(ws_sales_price) ws_sp
   from web_sales_TABLESUFFIX
   left join web_returns_TABLESUFFIX on wr_order_number=ws_order_number and ws_item_sk=wr_item_sk
   join date_dim_TABLESUFFIX on ws_sold_date_sk = d_date_sk
   where wr_order_number is null and d_year = 2001 and ws_quantity = 10
   group by d_year, ws_item_sk, ws_bill_customer_sk
   ),
cs as
  (select d_year AS cs_sold_year, cs_item_sk,
    cs_bill_customer_sk cs_customer_sk,
    sum(cs_quantity) cs_qty,
    sum(cs_wholesale_cost) cs_wc,
    sum(cs_sales_price) cs_sp
   from catalog_sales_TABLESUFFIX
   left join catalog_returns_TABLESUFFIX on cr_order_number=cs_order_number and cs_item_sk=cr_item_sk
   join date_dim_TABLESUFFIX on cs_sold_date_sk = d_date_sk
   where cr_order_number is null and d_year = 2001 and cs_quantity = 10
   group by d_year, cs_item_sk, cs_bill_customer_sk
   ),
ss as
  (select d_year AS ss_sold_year, ss_item_sk,
    ss_customer_sk,
    sum(ss_quantity) ss_qty,
    sum(ss_wholesale_cost) ss_wc,
    sum(ss_sales_price) ss_sp
   from store_sales_TABLESUFFIX
   left join store_returns_TABLESUFFIX on sr_ticket_number=ss_ticket_number and ss_item_sk=sr_item_sk
   join date_dim_TABLESUFFIX on ss_sold_date_sk = d_date_sk
   where sr_ticket_number is null and d_year = 2001 and ss_quantity = 10
   group by d_year, ss_item_sk, ss_customer_sk
   )
 select 
 ss_sold_year, ss_item_sk, ss_customer_sk, round(ss_qty/(coalesce(ws_qty+cs_qty,1)),2) ratio,
 ss_qty store_qty, ss_wc store_wholesale_cost, ss_sp store_sales_price,
 coalesce(ws_qty,0)+coalesce(cs_qty,0) other_chan_qty,
 coalesce(ws_wc,0)+coalesce(cs_wc,0) other_chan_wholesale_cost,
 coalesce(ws_sp,0)+coalesce(cs_sp,0) other_chan_sales_price
from ss
left join ws on (ws_sold_year=ss_sold_year and ws_item_sk=ss_item_sk and ws_customer_sk=ss_customer_sk)
left join cs on (cs_sold_year=ss_sold_year and cs_item_sk=ss_item_sk and cs_customer_sk=ss_customer_sk)
order by 
 ss_sold_year, ss_item_sk, ss_customer_sk,
 ss_qty desc, ss_wc desc, ss_sp desc,
 coalesce(ws_qty,0)+coalesce(cs_qty,0),
 coalesce(ws_wc,0)+coalesce(cs_wc,0),
 coalesce(ws_sp,0)+coalesce(cs_sp,0),
 round(ss_qty/(coalesce(ws_qty+cs_qty,1)),2)
limit 100;

-- end query 1 in stream 0 using template query78.tpl
