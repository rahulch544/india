# #########################################################################
# This are only important after intial setup
setenv GRID_ID APF_OEL7_PBUILD_GRID ;
setenv ISD_DEFAULT_DEVDB rchamant
setdb rchamant
# #########################################################################



setenv FORMS_SERVER_NAME rchamant.auto.susengdev2phx.oraclevcn.com
setenv SERVER_NAME rchamant.auto.susengdev2phx.oraclevcn.com
setenv CLI_PERL /arudev/tech-stack/oel6new/portable/bin/perl

rm -rf $HOME/.isd/conf/serverctl-rchamant-options.pl --Open time operation

setenv ORACLE_HOME /arudev/oracle/12.1.0.2.0

ps -eaf| grep -i apf; --Remove if any apf process is running already

setdb rchamant
restart_pbuild;


setenv FORMS_SERVER_NAME slc15zdx.us.oracle.com
setenv SERVER_NAME slc15zdx.us.oracle.com
setenv ORACLE_HOME /arudev/oracle/12.1.0.2.0
setenv GRID_ID APF_OEL7_PBUILD_GRID ;
setenv ISD_DEFAULT_DEVDB rchamant
setdb rchamant
setenv CONFIGLOADER_RUNTIME "development slc15zdx"
setenv PBUILD_FORMS_SERVER "slc15zdx.us.oracle.com:20855"
setenv BUGAU_OCI "( DESCRIPTION = ( ADDRESS_LIST = ( LOAD_BALANCE = ON ) ( FAILOVER = ON )(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin01.comsiiad.prodappiadsiv1.oraclevcn.com) (PORT=1610) )(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin02.comsiiad.prodappiadsiv1.oraclevcn.com)(PORT=1610) )(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin03.comsiiad.prodappiadsiv1.oraclevcn.com)(PORT=1610) ))( CONNECT_DATA = ( SERVICE_NAME = ldap_bugau.us.oracle.com )))"
setenv ADE_USE_ALT_BUGDB "(DESCRIPTION=(ADDRESS_LIST=(LOAD_BALANCE=ON)(FAILOVER=ON)(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin01.comsiiad.prodappiadsiv1.oraclevcn.com)(PORT=1610))(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin02.comsiiad.prodappiadsiv1.oraclevcn.com)(PORT=1610))(ADDRESS=(PROTOCOL=tcp)(HOST=iadpaocmprin03.comsiiad.prodappiadsiv1.oraclevcn.com)(PORT=1610)))(CONNECT_DATA=(SERVICE_NAME=aru_bugau.us.oracle.com)))"
setenv ADE_USE_BUGAU 1;
setenv JAVA_HOME "/ade_autofs/gd29_3rdparty/JDK8_MAIN_LINUX.X64.rdd/LATEST/jdk8"
setenv PATH "/ade_autofs/gd29_3rdparty/JDK8_MAIN_LINUX.X64.rdd/LATEST/jdk8/bin:$PATH"
setenv TWO_TASK rchamant
setenv ADE_ALT_BUGDB_CREDENTIALS aru/aru;
setenv ADE_USE_ALT_ARU "(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = slc15epa.us.oracle.com) (PORT = 1611)) (CONNECT_DATA = (SID = DBSPRINT)))"
setenv APF_DEBUG "on skip_make_apply_dbdrv test_rules mail skip_installtest bugdb"; 
setenv WEBAPP_DEBUG "stderr truncate_cgi OraDB BUGAU BUGDB"
setenv PATH ${PATH}:/arudev/tech-stack/oel6/linux/bin
set path=( /arudev/bin \
/arudev/tech-stack/dev/portable/bin \
/arudev/tech-stack/dev/linux/bin \
/arudev/tools/bin \
$path )
setenv PATH /usr/sbin:${PATH}
setenv FORMS_SERVER_NAME  "rchamant.auto.susengdev2phx.oraclevcn.com"
setenv SERVER_NAME "rchamant.auto.susengdev2phx.oraclevcn.com"
setenv CLI_PERL "/arudev/tech-stack/oel7/portable/bin/perl"