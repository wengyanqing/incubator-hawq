select
	sum(l_extendedprice * l_discount) as revenue
from
	lineitem_TABLESUFFIX
where
	l_shipdate >= '1997-01-01'
	and l_shipdate < '1998-01-01'
	and l_discount between 0.06 - 0.01 and 0.06 + 0.01
	and l_quantity < 24;
