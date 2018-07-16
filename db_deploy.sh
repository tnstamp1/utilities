#!/bin/ksh
# @(#)$Revision$
#
#
# $Log$
#
#
#===============================================================================
#
# FUNCTIONS
#-------------------------------------------------------------------------------
# LOGMESSAGE function
#-------------------------------------------------------------------------------
logmessage()
{
while getopts DIWE OPTION
do      case "$OPTION" in
        D)      MESSLEV="DEBUG: ";;
        I)      MESSLEV="INF: ";;
        W)      MESSLEV="WRN: ";;
        E)      MESSLEV="ERR: ";;
        esac
done
shift $OPTIND-1
DATESTR=`date "+%b %e %T "`
echo "${DATESTR}: ${MESSLEV}$*"| tee -a ${MasterLogFile}
}

#-------------------------------------------------------------------------------
# RUN_SQL function
#-------------------------------------------------------------------------------
run_sql()
{
   # Get options
   while getopts c:s: OPTION
   do      case "$OPTION" in
           c)      ConnectStr="${OPTARG}";;
           s)      Statement="${OPTARG}";;
           esac
   done
   shift $OPTIND-1
   #
   #logmessage -I "Running SQL statement ${Statement}"
   #
   # Run sql script
   sqlplus -s /nolog 1>>${WorkingDir}/${MasterLogFile} 2>&1 <<EOF!
      CONNECT ${ConnectStr}
      @${Statement};
      EXIT SUCCESS
EOF!
   ExitStatus=${?}
   #if [ ${ExitStatus} -eq 0 ]
   #then
   #   logmessage -I "${Statement} completed successfully."
   #else
   #   logmessage -E "${Statement} exited with status ${ExitStatus}"
   #fi
}

#-------------------------------------------------------------------------------
# TEST_USER function
#-------------------------------------------------------------------------------
test_user ()
{
   # Get options
   while getopts c: OPTION
   do      case "$OPTION" in
           c)      ConnectStr="${OPTARG}";;
           esac
   done
   shift $OPTIND-1
   #
   sqlplus /nolog <<EOF |grep -v "ORA-28002" |grep -v "ORA-03134" |grep -i "ORA-" >/dev/null 2>&1
   CONNECT ${ConnectStr}
   EXIT
EOF
   if [ $? -ne 0 ]
   then
       logmessage -I "Connection credentials validated"
   else
       logmessage -E "User credentials error.  Please amend the parameter file and rerun the script."
       exit 1
   fi
}


#-------------------------------------------------------------------------------
# MAIN script
#-------------------------------------------------------------------------------

#
# Set defaults

SysConnectStr="/ as sysdba"
#paramfile=parameter.file

if [ "$1"  = "" ]; then
      paramfile=parameter.file
else
      paramfile=$1
fi

logmessage -I  " parameter  file to use is:" $paramfile

MasterLogFile=db_deploy.`date "+%d%m%Y_%H%M%S"`.log
typeset -i stepcount
myInput=''
WorkingDir=$PWD
stepcount=1

logmessage -I "Starting deployment script"

# Validate the parameter file before executing each step

for i in `cat ${paramfile} |grep -v ^#`
do
   username=`echo $i | cut -d"|" -f1`
   password=`echo $i | cut -d"|" -f2`
   database=`echo $i | cut -d"|" -f3`
   dir_location=`echo $i | cut -d"|" -f4`
   sqlfile=`echo $i | cut -d"|" -f5` 
   parameter=`echo $i | cut -d"|" -f6`
   #echo Parameter: ${parameter}
   run_status=`echo $i | cut -d"|" -f7`
   #echo Run Status: ${run_status}
   scriptfile=$WorkingDir$dir_location$sqlfile
   #echo 'SQL File:' + $sqlfile
   #echo 'Scipt File:' + $scriptfile 
   #echo 'Dir Location: '+ $dir_location 
   # Check script file exists
   if [ ! -f ${scriptfile} ]; then
      logmessage -E "Parameter file error.  Script ${scriptfile} does not exist.  Please rectify and rerun the script."
      exit 1
   fi

   # Run each command in parameter file
   sql_command=${scriptfile}

   if [ ${username} = 'SYS' -o ${username} = 'sys' ]; then
	ConnectStr="${username}/${password}@${database} as sysdba"

   else
        ConnectStr="${username}/${password}@${database}"
   
   fi
   
   if [ ! -n ${parameter} ]; then
    echo No  Run Time Parameter
   else
    OLDIFS=$IFS
    IFS=','
    set -A myarray $parameter
    j=0
    parametertopass=" "
    while (( j < ${#myarray[*]} ))
    do
     parametertopass="${parametertopass} ${myarray[$j]}"
     (( j=j+1 ))
    done
    OFS=$OLDIFS
    IFS=' '
 
    #echo Passing Run Time Parameters for script ${scriptfile} : ${parametertopass}
    scriptfile="${WorkingDir}${dir_location}${sqlfile}${parametertopass}"
   fi
#  Has the script been run already?
   if [ ${run_status} = 'N' -o ${run_status} = 'n' ]; then

       test_user -c "${ConnectStr}"

       if [ $? -gt 0 ]; then
           logmessage -E "User credentials error.  Please amend the parameter file and rerun the script."
           exit 1
       fi
      
       logmessage -I "Step: ${stepcount} Executing script ${scriptfile}"
       cd $WorkingDir$dir_location
       run_sql -c "${ConnectStr}" -s "${scriptfile}"
       cd - 
#  Mark step as completed
       #echo $i
       #echo $i | sed 's/|N$/|Y/g'
       newline=`echo $i | sed 's/|N$/|Y/g'`
       sed "s;${i};${newline};g" ${paramfile} > /tmp/parm.txt
       mv /tmp/parm.txt ${paramfile}


   elif [ ${run_status} = 'Y' -o ${run_status} = 'y' ]; then

       logmessage -I "Script has already been run, missing step ${stepcount}"

   else

       logmessage -I "Run status should be either Y or N.  Please amend the parameter file and rerun the script."
       exit 1

   fi  

   echo "Press A to abort, or any other key to continue..."
   read myInput

   if [[ ${myInput} = "A" || ${myInput} = "a" ]]; then
      logmessage -W "Aborting the script."
      exit 0
   fi

   stepcount=stepcount+1

done
logmessage -I "Database deployment script completed. Please check the log file at the location:" $WorkingDir/$MasterLogFile
exit 0

