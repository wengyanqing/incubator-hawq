select
    o_orderpriority,
    count(*) as order_count
from
    orders_TABLESUFFIX as o
where
    o_orderdate >= '1996-05-01'
    and o_orderdate < '1996-08-01'
    and exists (
        select
            *
        from
            lineitem_TABLESUFFIX
        where
            l_orderkey = o.o_orderkey
            and l_commitdate < l_receiptdate
    )
group by
    o_orderpriority
order by
    o_orderpriority;
