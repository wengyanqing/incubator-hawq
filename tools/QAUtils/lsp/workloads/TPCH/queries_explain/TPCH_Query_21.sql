explain analyze 
select
 s_name,
 count(*) as numwait
from
 supplier_TABLESUFFIX,
 lineitem_TABLESUFFIX l1,
 orders_TABLESUFFIX,
 nation_TABLESUFFIX
where
 s_suppkey = l1.l_suppkey
 and o_orderkey = l1.l_orderkey
 and o_orderstatus = 'F'
 and l1.l_receiptdate > l1.l_commitdate
 and exists (
 select
 *
 from
 lineitem_TABLESUFFIX l2
 where
 l2.l_orderkey = l1.l_orderkey
 and l2.l_suppkey <> l1.l_suppkey
 )
 and not exists (
 select
 *
 from
 lineitem_TABLESUFFIX l3
 where
 l3.l_orderkey = l1.l_orderkey
 and l3.l_suppkey <> l1.l_suppkey
 and l3.l_receiptdate > l3.l_commitdate
 )
 and s_nationkey = n_nationkey
 and n_name = 'RUSSIA'
group by
 s_name
order by
 numwait desc,
 s_name
LIMIT 100;