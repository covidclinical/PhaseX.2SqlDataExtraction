#!/bin/sh 
PSWD=`cat pwd.sql`
echo $PSWD
sqlplus -s tm_cz/$PSWD<<EOF

@gen_file_ver2.sql;
exit; 
EOF
#./process_files_ver2.sh
#./mv_files2_rstudio_ver2.sh


