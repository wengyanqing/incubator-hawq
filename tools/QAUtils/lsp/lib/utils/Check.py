import sys
import commands

try:
    from lib.RemoteCommand import remotecmd
except ImportError:
    sys.stderr.write('Check needs remotecmd in lib/RemoteCommand.py \n')
    sys.exit(2)

def file(filename, msg):
    fp = open(filename, 'w')
    fp.write(msg)
    fp.flush()
    fp.close()

def remote_psql_file(sql, user, host, password, local_file = '/tmp/temp.sql', remote_file = '/tmp/temp.sql'):
    cmd = 'PGHOST=perfpipelinedb.csknn2zpm8tp.us-west-2.rds.amazonaws.com PGPORT=5432 PGUSER=postgres PGDATABASE=hawq PGPASSWORD=atomiccomingcoatheat psql -t -c "%s"' % (sql)
    (status, result) = commands.getstatusoutput(cmd)
    """
    file(filename = local_file, msg = sql)
    remotecmd.scp_command(from_user = '', from_host = '', from_file = local_file,
        to_user = 'gpadmin@', to_host = 'gpdb63.qa.dh.greenplum.com', to_file = ':' + remote_file, password = 'changeme')
    cmd = 'source psql.sh && psql -d hawq_cov -t -f %s' % (remote_file)
    result = remotecmd.ssh_command(user = user, host = host, password = password, command = cmd)
    """
    if str(result).find('ERROR:') != -1 or str(result).find('FATAL:') != -1:
        print(sql)
        print(str(result))
        #sys.exit(2)
    return result


class Check:
    def __init__(self, user = 'gpadmin', host = 'gpdb63.qa.dh.greenplum.com', password = 'changeme'):
        self.user = user
        self.host = host
        self.password = password

    def check_id(self, result_id, table_name, search_condition):
        sql = 'select %s from %s where %s;' % (result_id, table_name, search_condition)
        print sql, '\n'
        result = remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)
        result = str(result).strip()
        if result.isdigit():
            return int(result)
        else:
            return None

    def get_max_id(self, result_id, table_name):
        sql = 'select max(%s) from %s ;' % (result_id, table_name)
        print sql, '\n'
        result = remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)
        result = str(result).strip()
        if result.isdigit():
            return int(result)
        else:
            return 0

    def insert_new_record(self, table_name, col_list = None, values = ''):
        if col_list is None:
            sql = "Insert into %s values (%s);" % (table_name, values)
        else:
            sql = "Insert into %s (%s) values (%s);" % (table_name, col_list, values)
        print sql, '\n'
        remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)

    def update_record(self, table_name, set_content = '', search_condition = ''):
        sql = "update %s set %s where %s;" % (table_name, set_content, search_condition)
        print sql, '\n'
        remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)
        
    def get_result(self, col_list = '',table_list = '', search_condition = ''):
        sql = "select %s from %s %s;" % (col_list, table_list, search_condition)
        print sql, '\n'
        return remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)

    def get_result_by_sql(self, sql = ''):
        print sql, '\n'
        return remote_psql_file(sql = sql, user = self.user, host = self.host, password = self.password)

check = Check()
