#!/bin/sh 
PSWD=`cat pwd.sql`
echo $PSWD
sqlplus -s tm_cz/$PSWD<<EOF

@gen_file_ver1.sql;
exit; 
EOF
#./process_files_ver1.sh
#./mv_files2_rstudio_ver1.sh

