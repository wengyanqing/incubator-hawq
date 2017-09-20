select
	n_name,
	sum(l_extendedprice * (1 - l_discount)) as revenue
from
	customer_TABLESUFFIX,
	orders_TABLESUFFIX,
	lineitem_TABLESUFFIX,
	supplier_TABLESUFFIX,
	nation_TABLESUFFIX,
	region_TABLESUFFIX
where
	c_custkey = o_custkey
	and l_orderkey = o_orderkey
	and l_suppkey = s_suppkey
	and c_nationkey = s_nationkey
	and s_nationkey = n_nationkey
	and n_regionkey = r_regionkey
	and r_name = 'ASIA'
	and o_orderdate >= '1997-01-01'
	and o_orderdate < '1998-01-01'
group by
	n_name
order by
	revenue desc;
