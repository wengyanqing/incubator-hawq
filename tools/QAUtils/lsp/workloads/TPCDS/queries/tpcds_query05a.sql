--@author guz4
--@description TPC-DS tpcds_query5a-modified
--@created 2013-03-06 18:02:02
--@created 2013-03-06 18:02:02
--@tags tpcds orca

-- start query 1 in stream 0 using template query5a.tpl
with ssr as
 (select s_store_id,
        sum(sales_price) as sales,
        sum(profit) as profit,
        sum(return_amt) as returns,
        sum(net_loss) as profit_loss
 from
  ( select  ss_store_sk as store_sk,
            ss_sold_date_sk  as date_sk,
            ss_ext_sales_price as sales_price,
            ss_net_profit as profit,
            cast(0 as decimal(7,2)) as return_amt,
            cast(0 as decimal(7,2)) as net_loss
    from store_sales_TABLESUFFIX
    union all
    select sr_store_sk as store_sk,
           sr_returned_date_sk as date_sk,
           cast(0 as decimal(7,2)) as sales_price,
           cast(0 as decimal(7,2)) as profit,
           sr_return_amt as return_amt,
           sr_net_loss as net_loss
    from store_returns_TABLESUFFIX
   ) salesreturns,
     date_dim_TABLESUFFIX,
     store_TABLESUFFIX
 where date_sk = d_date_sk
       and d_date between cast('2000-08-23' as date) 
                  and (cast('2000-08-23' as date) +  14 )
       and store_sk = s_store_sk
 group by s_store_id)
 ,
 csr as
 (select cp_catalog_page_id,
        sum(sales_price) as sales,
        sum(profit) as profit,
        sum(return_amt) as returns,
        sum(net_loss) as profit_loss
 from
  ( select  cs_catalog_page_sk as page_sk,
            cs_sold_date_sk  as date_sk,
            cs_ext_sales_price as sales_price,
            cs_net_profit as profit,
            cast(0 as decimal(7,2)) as return_amt,
            cast(0 as decimal(7,2)) as net_loss
    from catalog_sales_TABLESUFFIX
    union all
    select cr_catalog_page_sk as page_sk,
           cr_returned_date_sk as date_sk,
           cast(0 as decimal(7,2)) as sales_price,
           cast(0 as decimal(7,2)) as profit,
           cr_return_amount as return_amt,
           cr_net_loss as net_loss
    from catalog_returns_TABLESUFFIX
   ) salesreturns,
     date_dim_TABLESUFFIX,
     catalog_page_TABLESUFFIX
 where date_sk = d_date_sk
       and d_date between cast('2000-08-23' as date)
                  and (cast('2000-08-23' as date) +  14 )
       and page_sk = cp_catalog_page_sk
 group by cp_catalog_page_id)
 ,
 wsr as
 (select web_site_id,
        sum(sales_price) as sales,
        sum(profit) as profit,
        sum(return_amt) as returns,
        sum(net_loss) as profit_loss
 from
  ( select  ws_web_site_sk as wsr_web_site_sk,
            ws_sold_date_sk  as date_sk,
            ws_ext_sales_price as sales_price,
            ws_net_profit as profit,
            cast(0 as decimal(7,2)) as return_amt,
            cast(0 as decimal(7,2)) as net_loss
    from web_sales_TABLESUFFIX
    union all
    select ws_web_site_sk as wsr_web_site_sk,
           wr_returned_date_sk as date_sk,
           cast(0 as decimal(7,2)) as sales_price,
           cast(0 as decimal(7,2)) as profit,
           wr_return_amt as return_amt,
           wr_net_loss as net_loss
    from web_returns_TABLESUFFIX left outer join web_sales_TABLESUFFIX on
         ( wr_item_sk = ws_item_sk
           and wr_order_number = ws_order_number)
   ) salesreturns,
     date_dim_TABLESUFFIX,
     web_site_TABLESUFFIX
 where date_sk = d_date_sk
       and d_date between cast('2000-08-23' as date)
                  and (cast('2000-08-23' as date) +  14 )
       and wsr_web_site_sk = web_site_sk
 group by web_site_id)
 ,
 results as
 (select channel
        , id
        , sum(sales) as sales
        , sum(returns) as returns
        , sum(profit) as profit
 from 
-- added casting ::text
 (select 'store channel'::text as channel
-- added casting ::text
        , ('store' || s_store_id)::text as id
        , sales
        , returns
        , (profit - profit_loss) as profit
 from   ssr
 union all
-- added casting ::text
 select 'catalog channel'::text as channel
-- added casting ::text
        , ('catalog_page' || cp_catalog_page_id)::text as id
        , sales
        , returns
        , (profit - profit_loss) as profit
 from  csr
 union all
-- added casting ::text
 select 'web channel'::text as channel
-- added casting ::text
        , ('web_site' || web_site_id)::text as id
        , sales
        , returns
        , (profit - profit_loss) as profit
 from   wsr
 ) x
 group by channel, id)
 select  channel, id, sales, returns, profit from ( 
  select channel, id, sales, returns, profit from results
  union
-- added casting ::text
  select channel, null::text as id, sum(sales), sum(returns), sum(profit) from results group by channel
  union
-- added casting ::text
  select null::text as channel, null::text as id, sum(sales), sum(returns), sum(profit) from results) foo
order by channel, id
limit 100;
-- end query 1 in stream 0 using template query5a.tpl
