
setenv FORMS_SERVER_NAME rchamant.auto.susengdev2phx.oraclevcn.com
setenv SERVER_NAME rchamant.auto.susengdev2phx.oraclevcn.com
setenv CLI_PERL /arudev/tech-stack/oel6new/portable/bin/perl
setenv PERL5LIB "/arudev/tech-stack/16.12.16.01/portable/lib/perl5"
setenv CONFIGLOADER_RUNTIME "development rchamant"
setenv PBUILD_FORMS_SERVER "rchamant.auto.susengdev2phx.oraclevcn.com:20855"
rm -rf $HOME/.isd/conf/serverctl-rchamant-options.pl --Open time operation

setenv ORACLE_HOME /arudev/oracle/12.1.0.2.0

ps -eaf| grep -i apf; --Remove if any apf process is running already

setenv GRID_ID APF_OEL7_PBUILD_GRID ;
setenv ISD_DEFAULT_DEVDB rchamant
setdb rchamant
restart_pbuild




setenv GRID_ID APF_OEL7_PBUILD_GRID ;
setenv ISD_DEFAULT_DEVDB rchamant
setdb rchamant
apfcli --label SPB_WLS_GENERIC_220207.131009 --cpm_series_name 'WLS Stack Patch Bundle 12.2.1.4.0' --type stackpatch --force


