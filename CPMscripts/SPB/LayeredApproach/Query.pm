#
# Copyright (c) 2013, 2015 by Oracle Corporation. All Rights Reserved.
#
#
package APF::PBuild::Query;
use     strict;
use     ARUDB;
use     ARU::Const;
use     APF::Const;
use     EMS::Const;
use     ISD::Const;

use ConfigLoader "PB::Config" => "$ENV{ISD_HOME}/conf/pbuild.pl";

my $initialized = 0;

#
# The method intialize all db queries
#
sub setup
{

return if ($initialized == 1);

ARUDB::add_query(
                 GET_BUGFIX_REQ_INFO =>
"select bugfix_request_id, bugfix_id
   from aru_bugfix_requests
  where bug_number = :1 and
        product_id = :2 and
        release_id = :3 and
        platform_id = :4",

                 USER_NAME =>
                 "select    user_id
 from      aru_users
 where     user_name=upper(:1)",

                 "GET_ARCHIVE_DOS" =>
"select distinct ao.object_name, ao.object_location
   from aru_objects ao, aru_product_releases apr
  where ao.product_release_id = apr.product_release_id
    and ao.filetype_id = :1
    and apr.release_id = :2
    and apr.product_id = :3",

                 "GET_LABEL_PRODUCT_INFO" =>
"select distinct ap.product_abbreviation, ar.release_long_name,
                 ar.release_name
   from aru_product_releases apr, aru_product_release_labels aprl,
        aru_products ap, aru_releases ar
  where aprl.label_id = :1
    and apr.product_release_id = aprl.product_release_id
    and ap.product_id = apr.product_id
    and ar.release_id = apr.release_id",

                 "GET_BUGFIX_ID_FROM_PATCH" =>
"select  distinct abr.bugfix_id, abr.bugfix_request_id, abr.bug_number
from aru_files af, aru_patch_files apf, aru_bugfix_requests abr
where af.file_id = apf.file_id
and apf.bugfix_request_id = abr.bugfix_request_id
and af.file_state = '" . ARU::Const::file_state_exists . "'
and af.file_name = :1",

                 "REQUESTS_IN_PSEREP" =>
                 "select status, count(rptno)
from bugdb_rpthead_v
where status < 55
and programmer = :1
and upd_date > (sysdate - 1)
group by status",


                 "IS_SIM_LABEL" =>
                 "select substr(COMMENTS,(instr(COMMENTS, '-')+1),
((instr(COMMENTS, '-',1,2)) - (instr(COMMENTS, '-')+1)))
from aru_bugfix_request_history where
     bugfix_request_history_id = (select max(bugfix_request_history_id)
                                  from aru_bugfix_request_history
                                  where bugfix_request_id = :1
                                  and comments like '%req_id%--%')",

                 "GET_DEP_CHECKINS" =>
                 "select distinct abr.related_bugfix_id, related_bug_number,
abr.relation_type
from aru_bugfix_relationships abr, aru_bugfixes ab, aru_products ap
where abr.bugfix_id = :1
and abr.relation_type in
           (" . ARU::Const::prereq_direct . ","
              . ARU::Const::included_direct . ","
              . ARU::Const::build_only_prereq_direct . ") and
ab.bugfix_id  = abr.related_bugfix_id and
ab.release_id = :2 and
ab.product_id = ap.product_id
order by abr.relation_type desc, related_bug_number",

                 "GET_PREREQ_FILES" =>
"select ao.object_id, ao.object_name, ao.object_location, abov.rcs_version,
        ao.filetype_id, af.filetype_name, af.requires_porting,
        af.source_extension
 from   aru_bugfix_relationships abrel,
        aru_bugfix_object_versions abov,
        aru_objects ao,
        aru_filetypes af,
        aru_object_versions aov
 where  abrel.relation_type in
           (" . ARU::Const::prereq_direct . ","
              . ARU::Const::prereq_indirect . ","
              . ARU::Const::prereq_cross_direct . ","
              . ARU::Const::prereq_cross_indirect . ","
              . ARU::Const::build_only_prereq_direct . ","
              . ARU::Const::build_only_prereq_indirect . ") and
        abov.bugfix_id = abrel.related_bugfix_id and
        aov.object_version_id = abov.object_version_id and
        ao.object_id = abov.object_id and
        af.filetype_id = ao.filetype_id and
        abrel.bugfix_id = :1",

                 "GET_BUGFIX_OBJECT_VERSIONS" =>
"select ao.object_id, ao.object_name, ao.object_location, abov.rcs_version,
        ao.filetype_id, af.filetype_name, af.requires_porting,
        af.source_extension
   from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af
  where abov.bugfix_id = :1
    and (abov.source like 'D%' or abov.source like '%I%')
    and af.filetype_id = ao.filetype_id
    and ao.object_id = abov.object_id");

ARUDB::add_query(GET_PORTING_BUGFIX_OBJECT_VERSIONS =>
"select distinct ao.object_id, ao.object_name, ao.object_location,
        abov.rcs_version, ao.filetype_id, af.filetype_name
from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af,
     aru_label_dependencies ald, aru_objects ao2, aru_filetypes af2
where abov.bugfix_id = :1
and (abov.source like 'D%' or abov.source like '%I%')
and ao.object_id = abov.object_id
and af.filetype_id = ao.filetype_id
and (ao.filetype_id = '" . ARU::Const::filetype_id_st_c . "'" . "
     or ao.filetype_id = '" . ARU::Const::filetype_id_st_cpp . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_lc . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_stmk . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_dat . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_txt . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pc . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pl . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pm . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_xml . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_sql . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_generic . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_stexe . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pls . "'" . ")
and ao.object_id = ald.b_used_by_a
and ao2.object_id = ald.a_uses_b
and ao2.filetype_id = af2.filetype_id
and af2.requires_porting = 'Y'
UNION
select distinct ao.object_id, ao.object_name, ao.object_location,
        abov.rcs_version, ao.filetype_id, af.filetype_name
from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af
where abov.bugfix_id = :1
and  (abov.source like 'D%' or abov.source like '%I%')
and ao.object_id = abov.object_id
and af.filetype_id = ao.filetype_id
and (ao.object_name like '%.h'
     or ao.object_name like '%.inc'
     or ao.object_name like 'kupus.txt'
     or ao.object_name like 'rmanus.txt')");

ARUDB::add_query(GET_PORTING_BUGFIX_OBJECT_VERSIONS_PSU =>
"select ao.object_id, ao.object_name, ao.object_location, abov.rcs_version,
        ao.filetype_id, af.filetype_name
from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af
where abov.bugfix_id = :1
and (abov.source like 'D%' or abov.source like '%I%')
and ao.object_id = abov.object_id
and af.filetype_id = ao.filetype_id
and (ao.filetype_id = '" . ARU::Const::filetype_id_st_c . "'" . "
     or ao.filetype_id = '" . ARU::Const::filetype_id_st_cpp . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_lc . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_stmk . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_dat . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_txt . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pc . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pl . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pm . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_xml . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_sql . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_generic . "'" . "
     or af.filetype_name = '" . ARU::Const::filetype_name_st_pls . "'" . "
     or ao.object_name like '%.h'
     or ao.object_name like '%.inc')");

ARUDB::add_query(CHECK_REQUIRES_PORTING =>
"select distinct af.requires_porting
 from   aru_objects ao1
 ,      aru_objects ao2
 ,      aru_label_dependencies ald
 ,      aru_filetypes af
 where  ao1.object_id = :1
 and    ald.b_used_by_a = ao1.object_id
 and    ald.a_uses_b = ao2.object_id
 and    ao2.filetype_id = af.filetype_id
 and    af.requires_porting = 'Y'");

ARUDB::add_query(CHECK_PORTING_FILE_TYPE =>
"select af.requires_porting
from   aru_objects ao
,      aru_filetypes af
where  ao.object_id = :1
and    ao.filetype_id = af.filetype_id
and    ao.object_id not in
       (
select ao1.object_id
from   aru_objects ao1
,      aru_filetypes af1
where  ao1.object_id = :1
and    ao1.object_location like '%/test/%'
and    ao1.filetype_id = af1.filetype_id
and    (af.filetype_name = '" . ARU::Const::filetype_name_st_pl . "'" . "
        or af.filetype_name = '" . ARU::Const::filetype_name_st_pm . "'" . "
        or af.filetype_name = '" . ARU::Const::filetype_name_st_xml . "'" . ")
        )");

ARUDB::add_query(GET_LABEL_DETAILS =>
"select aprl.label_id, aprl.label_name
 from aru_product_release_labels aprl, aru_product_releases apr
 where aprl.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id = :2
    and aprl.platform_id = :3
    and aprl.label_name like :4 escape '\\'
 order by aprl.label_id desc");

ARUDB::add_query(GET_VALID_FILES =>
"select ao.object_id, ao.object_name, ao.object_location
from aru_objects ao, aru_label_dependencies ald
where
(ald.a_uses_b = :1 and ao.object_id = ald.a_uses_b)
or
(ald.b_used_by_a = :1 and ao.object_id = ald.b_used_by_a)
and label_id = :2
and label_dependency in ('BASE','BMIN')
union
select ao.object_id, ao.object_name, ao.object_location
from aru_objects ao, aru_label_dependencies ald
where
(ald.a_uses_b = :1 and ao.object_id = ald.a_uses_b)
or
(ald.b_used_by_a = :1 and ao.object_id = ald.b_used_by_a)
and label_id = :3
and label_dependency in ('BMIN','BPLUS')");

ARUDB::add_query(GET_BPLUS_VALID_FILES =>
"select ao.object_id, ao.object_name, ao.object_location
from aru_objects ao, aru_label_dependencies ald
where
(ald.a_uses_b = :1 and ao.object_id = ald.a_uses_b)
or
(ald.b_used_by_a = :1 and ao.object_id = ald.b_used_by_a)
and label_id in (:2,:3)
and label_dependency = 'BPLUS'");

ARUDB::add_query(GET_LABEL_NAME =>
"select aprl.label_id, aprl.label_name
   from aru_product_release_labels aprl, aru_product_releases apr
  where aprl.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id = :2
    and aprl.platform_id = :3
    and hybrid_label_id is null");

ARUDB::add_query(GET_ALT_FMW_LABEL_NAME =>
"select aprl.label_id, aprl.label_name
   from aru_product_release_labels aprl, aru_product_releases apr
  where aprl.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id = :2
    and aprl.platform_id = :3
    and aprl.label_name not like 'FMW%-GA'
    and hybrid_label_id is null");

ARUDB::add_query(GET_LABEL_NAME_FROM_APG =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl
, aru_product_releases apr
, aru_product_groups apg
where aprl.product_release_id = apr.product_release_id
and apg.child_product_id = :1
and apr.product_id = apg.parent_product_id
and apr.release_id = :2
and aprl.platform_id = :3
and hybrid_label_id is null");

ARUDB::add_query(GET_LABEL_NAME_FROM_APG_23 =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl
, aru_product_releases apr
, aru_product_groups apg
, aru_products ap
where aprl.product_release_id = apr.product_release_id
and apg.child_product_id = :1
and apr.product_id = apg.parent_product_id
and apg.child_product_id = ap.product_id
and aprl.label_name like
decode(ap.product_abbreviation, 'webcach', 'CALYPSO%',
                                'forms', 'FORMS%',
                                'reports', 'REPORTS%',
                                'oid', 'LDAP%')
and apr.release_id = :2
and aprl.platform_id = :3
and hybrid_label_id is null");

ARUDB::add_query(GET_SERIES_DETAILS_FROM_RELEASE =>
"select distinct acps.series_name, acpr.release_name
  from aru_cum_patch_releases acpr, aru_cum_patch_series acps
  where acpr.series_id=acps.series_id
    and acpr.release_version  = :1");

ARUDB::add_query(GET_CPM_SERIES_FROM_REL =>
"select release_id,release_name,release_version
         ,series_id,status_id,release_label,aru_release_id
   from  aru_cum_patch_releases
   where release_version = :1");

ARUDB::add_query(GET_CHILD_WKR_HOST_DETAILS =>
"select ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_PARENT_WKR_HOST_DETAILS =>
"select ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl, aru_release_label_groups arlg
  where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id = :1
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_INSTALLTEST_WKR_HOST_DETAILS =>
"select ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'
  order by ah.host_account");

ARUDB::add_query(GET_HYBRIDS =>
"select ao.object_name, ao.object_location, ao.object_id, ald.build_dependency
from aru_objects ao, aru_label_dependencies ald, aru_filetypes af
where ald.b_used_by_a = :1
and ald.label_id = :2
and af.filetype_name = :4
and ald.label_dependency = '" . ARU::Const::dependency_hybrid . "'" .
" and af.filetype_id = ao.filetype_id
and ald.a_uses_b = ao.object_id
and ald.build_dependency != 'NO-SHIP'
UNION
select ao.object_name, ao.object_location, ao.object_id, ald.build_dependency
from aru_objects ao, aru_label_dependencies ald, aru_filetypes af
where ald.b_used_by_a = :1
and ald.label_id = :3
and af.filetype_name = :4
and ald.label_dependency = '" . ARU::Const::dependency_hybrid . "'" .
" and af.filetype_id = ao.filetype_id
and ald.a_uses_b = ao.object_id
and ald.build_dependency != 'NO-SHIP'");

ARUDB::add_query(GET_BASE_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" ."
and ald.a_uses_b = ao1.object_id
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and ald.label_id        = :2
and ald.build_dependency != 'NO-SHIP'");

ARUDB::add_query(GET_NONBASE_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a = :1
and   ald.label_dependency = '" . ARU::Const::dependency_bmin . "'" ."
and ald.a_uses_b = ao1.object_id
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and ald.label_id = :2
and ald.build_dependency != 'NO-SHIP'");

ARUDB::add_query(GET_MKFILE_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
        ald.build_dependency
from  aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a= :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" ."
and   ald.a_uses_b= ao1.object_id
and   af1.filetype_id = ao1.filetype_id
and   af1.filetype_id = :3
and   ald.label_id = :2
and   ald.build_dependency = :4
order by 1");


ARUDB::add_query(GET_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" .
" and ald.a_uses_b = ao1.object_id
and ald.build_dependency != 'NO-SHIP'
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and not exists (select 1
                from aru_label_dependencies ald_minus
                where ald_minus.a_uses_b        = ald.a_uses_b
                and   ald_minus.b_used_by_a     = ald.b_used_by_a
                and   ald_minus.label_dependency = '" .
                                ARU::Const::dependency_bmin . "'" .
"               and   ald_minus.label_id        = :4)
UNION
select ao2.object_name, ao2.object_location, ao2.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_filetypes af2, aru_objects ao2
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_bplus . "'" .
" and   ald.label_id        = :2
and ald.build_dependency != 'NO-SHIP'
and ald.a_uses_b = ao2.object_id
and af2.filetype_id = ao2.filetype_id
and af2.filetype_name = :3
order by 1");

ARUDB::add_query(GET_PLS_TARGET =>
"select ao.object_name, ao1.object_location, ao1.object_id
  from  aru_objects ao1, aru_objects ao, aru_label_dependencies ald
 where  ao.object_id = ald.a_uses_b
   and  ao1.object_id = ald.b_used_by_a
   and  ao1.object_id = :1");

ARUDB::add_query(GET_SPL_PLS_TARGET =>
"select ao.object_name, ao.object_location, ao1.object_id
  from  aru_objects ao1, aru_objects ao, aru_label_dependencies ald
 where  ao.object_id = ald.a_uses_b
   and  ao1.object_id = ald.b_used_by_a
   and  ao1.object_id = :1");

ARUDB::add_query(GET_APF_PLATFORM_ID =>
"select platform_id
   from aru_platforms
  where bugdb_platform_id = :1
    and obsolete <> 'Y'");

ARUDB::add_query(GET_BUGDB_PLATFORM_ID =>
"select bugdb_platform_id, platform_name
   from aru_platforms
  where platform_id = :1
    and obsolete <> 'Y'");

ARUDB::add_query(GET_ARU_TRANSACTION_NAME =>
"select at.transaction_name
 from   aru_transactions at
 where  at.bugfix_request_id = :1");

ARUDB::add_query(GET_BUGFIX_TRANSACTION_NAME =>
"select at.transaction_name
 from   aru_transactions at, aru_bugfix_requests abr
 where  abr.bugfix_request_id = :1
   and  abr.bugfix_id = at.bugfix_id");

ARUDB::add_query(REQUEST_ENABLED =>
"select 'enabled'
from  aru_product_releases apr, aru_product_release_labels aprl
where aprl.platform_id = :1
and   apr.product_release_id = aprl.product_release_id
and   apr.release_id = :2
and   apr.product_id = :3");

ARUDB::add_query(GET_INSTALL_STATUS =>
"select status_code, request_id
    from  isd_requests
    where reference_id = :1
    and  request_type_code = 80040");

ARUDB::add_query(GET_MIN_TRANS_ID  =>
"select min(at1.transaction_id)
    from aru_transactions at1
    where at1.bugfix_id = :1");

 ARUDB::add_query(GET_PATCH_ADE_DETAILS =>
"select ata.attribute_name, ata.attribute_value
    from   aru_transactions at, aru_transaction_attributes ata
    where  ata.transaction_id = at.transaction_id
    and    at.bugfix_request_id = :2
UNION
select ata.attribute_name,  ata.attribute_value
    from   aru_transactions at, aru_transaction_attributes ata
    where  ata.transaction_id = at.transaction_id
    and    at.bugfix_id = :1
    and    at.transaction_id = :3
    and    ata.attribute_name not in
    (select ata.attribute_name
from   aru_transactions at, aru_transaction_attributes ata
where  ata.transaction_id = at.transaction_id
and    at.bugfix_request_id = :2)");

ARUDB::add_query(GET_AUTO_PORT_LIST =>
"select distinct aprl.platform_id
    from aru_product_release_labels aprl,
    aru_bugfix_requests abr,aru_product_releases apr
    where abr.bugfix_request_id = :1
    and apr.product_id= :2
    and apr.release_id = abr.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id <>2000
minus
select  distinct aprl.platform_id
    from aru_product_release_labels aprl,
    aru_bugfix_requests abr,aru_product_releases apr, aru_bugfix_requests abr1
    where abr.bugfix_request_id = :1
    and apr.product_id  = :2
    and apr.release_id  = abr.release_id
    and aprl.product_release_id = apr.product_release_id
    and abr1.product_id = abr.product_id
    and abr1.release_id = abr.release_id
    and abr1.bug_number = abr.bug_number
    and aprl.platform_id in (abr1.platform_id)");

ARUDB::add_query(GET_ACTIVE_BP_PSES =>
"select distinct a.request_id, a.reference_id, a.status_code,
    a.request_type_code,br.portid
    from isd_Requests a, bugdb_rpthead_v br
    where a.last_updated_date in (
                                  (select max(ir.last_updated_date)
                                   from isd_requests ir, bugdb_rpthead_v b
                                   where  b.base_rptno  = :1
                                   and b.generic_or_port_specific = 'O'
                                   and ir.reference_id = b.rptno
                                   group by (b.portid)))
    and a.status_code not in  (". ISD::Const::isd_request_stat_succ . "," .
                                  ISD::Const::isd_request_stat_fail . "," .
                                  ISD::Const::isd_request_stat_susp . "," .
                                  ISD::Const::isd_request_stat_abtd . ")"."
    and a.request_type_code <> 80040
    and a.reference_id = br.rptno");

ARUDB::add_query(GET_ISDREQUEST_STATUS =>
"select status_code
    from
    isd_requests
    where request_id =
    (
     select max(ir.request_id)
     from isd_requests ir, isd_request_parameters irp
     where ir.reference_id=:1
     and ir.request_id = irp.request_id
     and irp.param_value like :2)");

ARUDB::add_query(GET_PROACTIVE_TESTFLOWS =>
                     "select testflow_name
    from apf_testflows
    where testflow_name like 'Patch Validations for %'");

ARUDB::add_query(GET_SPECIFIED_PROACTIVE_TESTFLOWS =>
                     "select testflow_name
    from apf_testflows
    where testflow_name like 'Patch Validations for ' || :1");

ARUDB::add_query(GET_CPM_PROD_NAME =>
"select distinct upper(product_name)
from aru_cum_patch_series
where series_id = :1");

ARUDB::add_query(GET_CPM_REL_PREV_BUG =>
"select parameter_name, datestamp, parameter_value
      from (
      select acprr.parameter_name,
            regexp_substr(acprr.parameter_name, '(\\d{6,})(\\.)?(\\d{1,})?') datestamp,
            acprr.parameter_value
      from   aru_cum_patch_release_params acprr, aru_bugfix_requests abr
      where  acprr.release_id  =  :1
      and acprr.parameter_name like :2 || '%' ".
     "  and abr.bug_number = to_number(acprr.parameter_value)
      and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")".
     "  order by datestamp desc)
      where to_char(datestamp) < to_char(:3)
      and rownum = 1");

ARUDB::add_query(GET_LATEST_SQL_DIFF_BUGS =>
"select distinct accr.base_bug
    from aru_cum_codeline_requests accr, aru_cum_codeline_req_attrs acra
    where acra.attribute_name = 'ADE Merged Timestamp'
    and acra.codeline_request_id = accr.codeline_request_id
    and accr.release_id = :1
    and accr.status_id in (34588, 34597, 34610,96302)
    and acra.attribute_value is not null
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    >= to_char(:2)
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    <= to_char(:3)");

ARUDB::add_query(GET_CPM_REL_ID =>
"select distinct acpr.release_id  from aru_cum_patch_releases acpr,
        aru_bugfixes ab where
	ab.bugfix_id = :1 and
	acpr.tracking_bug =  ab.bugfix_rptno");    

ARUDB::add_query(GET_BUG_REVIEW_BUGS =>
                     "select accr.base_bug
    from aru_cum_codeline_requests accr,
    aru_cum_patch_series acps,
    bugdb_rpthead_v brv
    where acps.series_name = :1
    and acps.series_id = accr.series_id
    and accr.status_id in (:2)
    and brv.rptno = accr.base_bug
    and brv.status in (35,74,75,80,90,98)");

ARUDB::add_query(GET_CI_MERGED_BUGS =>
                     "select accr.base_bug, acra.attribute_value
    from aru_cum_codeline_requests accr,
    aru_cum_codeline_req_attrs acra,
    aru_cum_patch_series acps,
    aru_cum_patch_releases acpr
    where acps.series_name = :1
    and acps.series_id = acpr.series_id
    and acpr.release_id = accr.release_id
    and accr.status_id in (34588)
    and acra.codeline_request_id = accr.codeline_request_id
    and acra.attribute_name = 'ADE Transaction Name'
    and acra.attribute_value is not null");

ARUDB::add_query(GET_WORKFLOW_STATUS =>
                     "select workflow, tasks_status
    from checklist_testruns
    where unique_id = :1
    and stage = :2
    and unique_value =:4
    and unique_name = :3");


ARUDB::add_query(GET_AUTOPORT_PSES =>
"select count(b.rptno)
    from bugdb_rpthead_v b,aru_bugfix_requests abr,aru_releases ar
    where abr.bugfix_request_id = :1
    and abr.bug_number = b.base_rptno
    and b.generic_or_port_specific= :2
    and ar.release_id = abr.release_id
    and aru_backport_util.pad_version(b.utility_version) =
    aru_backport_util.pad_version(ar.release_name)");

ARUDB::add_query(GET_AUTOPORT_PATCHES =>
"select distinct abr.platform_id, abr.bugfix_request_id
from aru_bugfix_requests abr,aru_bugfix_request_history abrh,
     aru_bugfix_requests abr1
where abr1.bugfix_request_id = :1
and abr1.release_id = abr.release_id
and abr1.bug_number = abr.bug_number
and abr1.product_id = abr.product_id
and abr.bugfix_request_id = abrh.bugfix_request_id
and abr.status_id  not in (".ARU::Const::patch_deleted.",".
                             ARU::Const::patch_on_hold.",".
                             ARU::Const::patch_replaced.",".
                             ARU::Const::patch_deleting.",".
                             ARU::Const::patch_q_delete .")
and abr.platform_id <> abr1.platform_id
and abrh.comments like :2 ");

ARUDB::add_query(IS_AUTOPORT_REQUEST =>
"select count(distinct ir.request_id)
from isd_requests ir, isd_request_history irh
where ir.request_id = :1
and ir.request_type_code in (". ISD::Const::st_apf_request_task .",".
                                ISD::Const::st_apf_build_type .",".
                                ISD::Const::st_apf_install_type .")".
" and ir.status_code = ". ISD::Const::st_apf_preproc .
" and irh.request_id = ir.request_id
and irh.status_code = ".ISD::Const::isd_request_stat_qued .
" and irh.error_message = 'Auto Port Request'");

ARUDB::add_query(GET_AUTOPORT_DB_REQS =>
"select distinct ir.request_id
from isd_requests ir, isd_request_history irh
where ir.reference_id = :1
and ir.request_type_code in (". ISD::Const::st_apf_request_task .",".
                                ISD::Const::st_apf_build_type .",".
                                ISD::Const::st_apf_install_type .")".
" and ir.status_code in (". ISD::Const::isd_request_stat_proc . ",".
                          ISD::Const::isd_request_stat_qued . ",".
                          ISD::Const::st_apf_preproc .")" .
" and irh.request_id = ir.request_id
and irh.status_code = ".ISD::Const::isd_request_stat_qued .
" and irh.error_message = 'Auto Port Request'
union
select distinct ir.request_id
from isd_requests ir
where ir.reference_id = :1
and ir.request_type_code in (". ISD::Const::st_apf_request_task .")".
" and ir.status_code = ".ISD::Const::isd_request_stat_qued .
" and ir.error_message = 'Auto Port Request'");

ARUDB::add_query(GET_AUTOPORT_DB_ISD_REQS =>
"select distinct ir.request_id
from isd_requests ir, isd_request_history irh
where ir.reference_id = :1
and ir.request_type_code in (". ISD::Const::st_apf_request_task .")".
" and ir.status_code in (". ISD::Const::isd_request_stat_proc . ",".
                          ISD::Const::isd_request_stat_qued . ",".
                          ISD::Const::st_apf_preproc .")" .
" and irh.request_id = ir.request_id
and irh.status_code = ".ISD::Const::isd_request_stat_qued .
" and irh.error_message = 'Auto Port Request'
union
select distinct ir.request_id
from isd_requests ir
where ir.reference_id = :1
and ir.request_type_code in (". ISD::Const::st_apf_request_task .")".
" and ir.status_code = ".ISD::Const::isd_request_stat_qued .
" and ir.error_message = 'Auto Port Request'
 union
 select distinct ir.request_id
from isd_requests ir, isd_request_parameters irp
where ir.reference_id = :1
and ir.request_type_code in (".ISD::Const::st_apf_build_type.")".
" and ir.status_code in (". ISD::Const::isd_request_stat_proc . ",".
                          ISD::Const::isd_request_stat_qued . ",".
                          ISD::Const::st_apf_preproc .")" .
" and irp.request_id = ir.request_id
 and irp.param_name = 'st_apf_build'
 and irp.param_value like '%' || :3 || '%'".
" union
 select distinct ir.request_id
from isd_requests ir
where ir.reference_id = :2
and ir.request_type_code in (".ISD::Const::st_apf_install_type .")".
" and ir.status_code in (". ISD::Const::isd_request_stat_proc . ",".
                          ISD::Const::isd_request_stat_qued . ",".
                          ISD::Const::st_apf_preproc .")");

ARUDB::add_query(IS_VALID_ARU_PSE =>
"select count(1)
from aru_backport_bugs
where bugfix_request_id = :1
and backport_bug_type = ".ISD::Const::st_pse .
" and backport_bug = :2");

ARUDB::add_query(GET_AUTOPORT_PBUILD_REQS =>
"select distinct request_id
    from isd_requests
    where reference_id = :1
    and status_code not in (". ISD::Const::isd_request_stat_succ . "," .
                           ISD::Const::isd_request_stat_fail . "," .
                           ISD::Const::isd_request_stat_susp . "," .
                           ISD::Const::isd_request_stat_abtd . ")");

ARUDB::add_query("GET_SRC_CTRL_TYPE_FOR_RELEASE" =>
                 "select parameter_value
                  from aru_cum_patch_series_params
                  where parameter_name = 'Series Source Control'
                  and series_id = (select series_id
                                    from aru_cum_patch_releases
                                    where rownum = 1
                                    and release_version=:1)"),

ARUDB::add_query(GET_VALIDATION_RESULTS =>
"select distinct validation_name,validation_result,action, user_name
 from   automation_val_results
 where  validation_key = :1
 and validation_value = :2
 and status = 'Y'");

ARUDB::add_query(GET_FAST_BRANCH_SRC_BUG    =>
"select parameter_value from aru_cum_patch_series_params
where series_id=:1
and parameter_name='Source_Fast_Branch'
and parameter_type=96183");

ARUDB::add_query(GET_FUSION_AUTO_PORT_LIST =>
"select distinct aprl.platform_id
    from aru_product_release_labels aprl,
    aru_bugfix_requests abr,aru_product_releases apr
    where abr.bugfix_request_id = :1
    and apr.product_id= :2
    and apr.release_id = abr.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id not in (" . ARU::Const::platform_generic . "," .
    ARU::Const::platform_linux64_amd . ")
minus
select  distinct aprl.platform_id
    from aru_product_release_labels aprl,
    aru_bugfix_requests abr,aru_product_releases apr, aru_bugfix_requests abr1
    where abr.bugfix_request_id = :1
    and apr.product_id  = :2
    and apr.release_id  = abr.release_id
    and aprl.product_release_id = apr.product_release_id
    and abr1.product_id = abr.product_id
    and abr1.release_id = abr.release_id
    and abr1.bug_number = abr.bug_number
    and aprl.platform_id in (abr1.platform_id)");

ARUDB::add_query(REQUEST_ENABLED_GENERIC =>
"select 'enabled'
from  aru_product_releases apr, aru_product_release_labels aprl
where apr.product_release_id = aprl.product_release_id
and   apr.release_id = :1
and   apr.product_id = :2");

 ARUDB::add_query(GET_HYBRID_LABEL =>
 "select aprl1.label_id, aprl1.label_name,
  aprl2.label_id, aprl2.label_name
 from aru_product_release_labels aprl1,
 aru_product_release_labels aprl2,
 aru_product_releases apr
 where aprl1.product_release_id = apr.product_release_id
 and apr.product_id = :1
 and apr.release_id = :2
 and aprl1.platform_id = :3
 and aprl2.label_id = aprl1.hybrid_label_id
 and aprl1.hybrid_label_id is not null");

ARUDB::add_query(GET_BUGDB_PROD_ID_BY_SERIES_NAME =>
"select distinct ap.product_id
 ,      ap.bugdb_product_id
 from   aru_products ap
 ,      aru_cum_patch_series acps
 where  acps.product_id = ap.product_id
 and    acps.series_name = :1");

ARUDB::add_query(GET_BUGDB_PROD_ID_BY_RELEASE_VER =>
"select distinct ap.product_id
 ,      ap.bugdb_product_id
 from   aru_products ap
 ,      aru_cum_patch_releases acpr
 ,      aru_cum_patch_series acps
 where  acps.product_id = ap.product_id
 and    acpr.series_id = acps.series_id
 and    acpr.release_version = :1");

ARUDB::add_query(GET_BUGDB_PROD_ID_BY_LABEL_PREFIX =>
"select distinct ap.product_id
 ,      ap.bugdb_product_id
 from   aru_products ap
 ,      aru_cum_patch_series acps
 ,      aru_cum_patch_releases acpr
 ,      aru_cum_plat_rel_labels acprl
 where  ap.product_id = acps.product_id
 and    acps.series_id = acpr.series_id
 and    acpr.release_id = acprl.release_id
 and    acprl.platform_release_label like :1 || '%'
 order  by 1");

ARUDB::add_query(GET_UTIL_BUG_ASSIGNMENT =>
"select extractvalue(apbr.xcontent,'/rules/assignee'),
        extractvalue(apbr.xcontent,'/rules/email')
 from   apf_bug_assignment_rules apbr
 where  extractvalue(apbr.xcontent,'/rules/name') like 'BUG_ASSIGNMENT'
 and    extractvalue(apbr.xcontent,'/rules/bugdb_product_id')  in (:2, 'ALL')
 and    upper(extractvalue(apbr.xcontent,'/rules/issue_type'))
        like '%' || upper(:3) || '%'
 and    apbr.patch_type in (:4, 'ALL')
 and    apbr.product_id = :1
 and    apbr.status = 'Y'
 order by rule_id desc");

ARUDB::add_query(GET_P1_UTIL_REASON_TG =>
"select extractvalue(apbr.xcontent,'/rules/assignee'),
        extractvalue(apbr.xcontent,'/rules/p1_reason')
 from   apf_bug_assignment_rules apbr
 where  extractvalue(apbr.xcontent,'/rules/name') like 'BUG_ASSIGNMENT'
 and    extractvalue(apbr.xcontent,'/rules/bugdb_product_id')  in (:2, 'ALL')
 and    upper(extractvalue(apbr.xcontent,'/rules/issue_type'))
        like '%' || upper(:3) || '%'
 and    apbr.patch_type in (:4, 'ALL')
 and    apbr.product_id = :1
 and    apbr.status = 'Y'
 order by rule_id desc");

ARUDB::add_query(GET_PRODUCT_FROM_LABEL =>
                    "select br.product_id, br.category, acpr.tracking_bug
    from aru_cum_patch_releases acpr, bugdb_rpthead_v br
    where acpr.tracking_bug =
    (select distinct tracking_bug from
     aru_cum_patch_releases
     where release_label like
     (select regexp_replace(substr(:1, 0,instr(:1,'_',1,1)-1),
                            '(.*)','\\1%')
      from dual)
     and rownum = 1 )
    and br.rptno  = acpr.tracking_bug");


ARUDB::add_query(FETCH_PROD_NAME =>
"select product_name
 from   aru_products
 where  product_id = :1");


ARUDB::add_query(GET_NOTIFICATION_LIST_BY_SERIES_NAME =>
"select distinct an.email_address, an.dev_value, an.type
 from   aru_cum_patch_series acps
 ,      apf_notifications an
 where  acps.series_id = an.series_id
 and    acps.series_name = :1");

ARUDB::add_query(GET_NOTIFICATION_LIST_BY_REL_VERSION =>
"select distinct an.email_address, an.dev_value, an.type
 from   aru_cum_patch_series acps
 ,      aru_cum_patch_releases acpr
 ,      apf_notifications an
 where  acpr.series_id = acps.series_id
 and    acps.series_id = an.series_id
 and    acpr.release_version = :1");

ARUDB::add_query(GET_NOTIFICATION_LIST_BY_LABEL_NAME =>
"select distinct an.email_address, an.dev_value, an.type
 from   aru_cum_patch_series acps
 ,      aru_cum_patch_releases acpr
 ,      aru_cum_patch_release_params acprp
 ,      apf_notifications an
 where  acps.series_id = acpr.series_id
 and    acps.series_id = an.series_id
 and    acpr.release_id = acprp.release_id
 and    acprp.parameter_value = :1");

ARUDB::add_query(GET_NOTIFICATION_LIST_BY_PROD_ID =>
"select distinct an.email_address, an.dev_value, an.type,acps.series_id
 from   aru_cum_patch_series acps
 ,      apf_notifications an
 where  an.email_address is not null
 and    an.series_id = acps.series_id
 and    acps.product_id = :1
 and    an.type = :2
 order by acps.series_id desc");



ARUDB::add_query(GET_FMW_BASE_LABEL =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl
, aru_product_releases apr
, apf_configurations ac
, aru_product_groups apg
, aru_products ap
where apg.child_product_id = :1
and apr.product_id = apg.parent_product_id
and apr.release_id = :2
and apr.release_id = ac.release_id
and apg.child_product_id = ap.product_id
and aprl.label_name like
decode(ap.product_abbreviation, 'webcach', 'CALYPSO%',
                                'forms', 'FORMS%',
                                'reports', 'REPORTS%',
                                'oid', 'LDAP%')
and aprl.product_release_id = apr.product_release_id
and aprl.platform_id = ac.platform_id
and ac.request_enabled = 'B'
and ac.apf_type = '" . ARU::Const::apf_manager_type . "'
and ac.language_id = " . ARU::Const::language_US);

ARUDB::add_query(GET_BASE_LABEL =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl, aru_product_releases apr,
apf_configurations ac
where apr.product_id = :1
and apr.release_id = :2
and apr.release_id = ac.release_id
and aprl.product_release_id = apr.product_release_id
and aprl.platform_id = ac.platform_id
and ac.request_enabled = '" . ARU::Const::auto_req_base_us . "'
and ac.apf_type = '" . ARU::Const::apf_manager_type . "'
and ac.language_id = " . ARU::Const::language_US);

ARUDB::add_query(GET_OBJECT_ID =>
"select ao.object_id, ao.object_name, ao.object_location,
 'rcs_version', ao.filetype_id, af.filetype_name,
 af.requires_porting
  from aru_objects ao, aru_filetypes af, aru_product_releases apr
 where ao.object_name = :1
  and ao.object_location = :2
  and apr.product_id = :3
  and apr.release_id = :4
  and apr.product_release_id = ao.product_release_id
  and af.filetype_id = ao.filetype_id");

ARUDB::add_query(GET_OBJECT_DETAILS =>
"select ao.object_name, ao.object_location,
 ao.product_release_id, ao.filetype_id,af.filetype_name,
 ao.object_type
  from aru_objects ao, aru_filetypes af
 where ao.object_id = :1
 and af.filetype_id = ao.filetype_id");

ARUDB::add_query(GET_EMS_TEMPLATE_ID_1 =>
"select aprl.template_env_id
   from aru_product_release_labels aprl
where aprl.label_id = :1");

ARUDB::add_query(GET_EMS_TEMPLATE_ID =>
"select aprl.template_env_id
   from aru_product_releases apr,
aru_product_release_labels aprl
where apr.product_id = :1
and apr.release_id = :2
and aprl.platform_id = :3
and apr.product_release_id = aprl.product_release_id");

 ARUDB::add_query(GET_PATCHVALIDATION_RESULT =>
"select distinct validation_id,validation_result,action, user_name
 from   automation_val_results
 where  validation_key = :1
 and validation_value = :2
and validation_name = :3
 and status = 'Y'");

ARUDB::add_query(GET_README_TMPL_REL_SERIES_LIKE =>
"select patch_type, tmpl_id
    from automation_readme_templates
    where product_id = :1
    and  release_id in (:2, 1)
    and  patch_type like :3
    and  series_id  in (:4,1)
    and  enabled = 'Y'
    and  platform  in (:5,'ALL')
        order by tmpl_id desc");


ARUDB::add_query(GET_README_TEMPLATE_ID =>
"select max(tmpl_id)
    from automation_readme_templates
    where product_id = :1
    and  release_id in (:2, 1)
    and  patch_type in (:3,'ALL')
    and  series_id  in (:4,1)
    and  enabled = 'Y'
    and  platform  in (:5,'ALL')");

ARUDB::add_query(GET_README_TEMPLATE_ID_SERIES =>
"select max(tmpl_id)
    from automation_readme_templates
    where series_id  in (:1)
    and  enabled = 'Y'
    and  platform  in (:2,'ALL')");

ARUDB::add_query(GET_README_TEMPLATE_ID_RELEASE =>
"select max(tmpl_id)
    from automation_readme_templates
    where product_id = :1
    and  release_id in (:2, 1)
    and  patch_type in (:3,'ALL')
    and  series_id  in (1)
    and  enabled = 'Y'
    and  platform  in (:4,'ALL')");

ARUDB::add_query(GET_SPB_BUGFIX_ID =>
"select ab.bugfix_id
  from   aru_bugfixes ab
where  ab.bugfix_rptno = :1
  and  ab.release_id   = :2");

ARUDB::add_query(GET_ISD_REQ_BY_REF_ID => 
"select request_id 
  from isd_requests
where  reference_id = :1");      

ARUDB::add_query("GET_SERIES_ATTRIBUTES" =>
"select acpsa.attribute_default, acpsa.attribute_name
      from   aru_cum_patch_series_attrs acpsa
      where  acpsa.series_id      = :1
      and    acpsa.attribute_name like '%' || :2 || '%'");

ARUDB::add_query("GET_SERIES_REQ_ATTRIBUTE" =>
"select acpsa.attribute_default, acpsa.attribute_name
      from   aru_cum_patch_series_attrs acpsa
      where  acpsa.series_id      = :1
      and    regexp_like(acpsa.attribute_name, :2,'i')
      and  acpsa.attribute_required = :3");

ARUDB::add_query("GET_PREVIOUS_SPB_TRACKING_ARU"=>
"select asp.parameter_name,asp.parameter_value
  from aru_cum_patch_releases acpr
      inner join aru_cum_patch_series acps
      on acpr.series_id =acps.series_id
      inner join aru_cum_patch_series_params asp
      on asp.series_id =acps.series_id
  where acps.series_id = :1
      and asp.parameter_type =96505
      and acpr.status_id =34524
      and regexp_like(asp.parameter_name,'^'||:2||acpr.tracking_bug)
      and rownum <2
  order by aru_backport_util.get_numeric_version(acpr.release_version) desc");

ARUDB::add_query(GET_MANUAL_BUG_INFO =>
"select distinct abr.bug_number,
    aru_backport_util.pad_version(bug.utility_version),
    abr.platform_id,bug.product_id,bug.category,bug.sub_component
          from   bugdb_rpthead_v bug,aru_bugfix_requests abr,
                aru_releases ar
          where  abr.bugfix_request_id = :1
          and    ((abr.bug_number = bug.base_rptno
          and    bug.generic_or_port_specific in ('B', 'Z')) or
                  (abr.bug_number = bug.rptno
          and    bug.generic_or_port_specific in ('M')))
          and    ar.release_id = abr.release_id
          and    aru_backport_util.pad_version(bug.utility_version) =
                 aru_backport_util.pad_version(ar.release_name)
          and    bug.status not in (53,55,59,96)
  union
    select distinct abr.bug_number,
    aru_backport_util.pad_version(bug.utility_version),
    abr.platform_id,bug.product_id,bug.category,bug.sub_component
          from   bugdb_rpthead_v bug,aru_bugfix_requests abr,
                aru_cum_patch_releases acpr
          where  abr.bugfix_request_id = :1
          and    ((abr.bug_number = bug.base_rptno
          and    bug.generic_or_port_specific in ('B', 'Z')) or
                  (abr.bug_number = bug.rptno
          and    bug.generic_or_port_specific in ('M')))
          and    acpr.aru_release_id = abr.release_id
          and    aru_backport_util.pad_version(bug.utility_version) =
                 aru_backport_util.pad_version(acpr.release_version)
          and    bug.status not in (53,55,59,96)");

ARUDB::add_query(IS_RDBMS_MANUAL_UPLOAD =>
"select count(1)
  from aru_bugfix_requests abr, aru_bugfix_request_history abrh
 where abr.bugfix_request_id = :1
   and abr.release_id not like '".
    ARU::Const::applications_fusion_rel_exp . "%' ".
" and abrh.bugfix_request_id = abr.bugfix_request_id
  and abrh.status_id = ".ARU::Const::upload_requested);

ARUDB::add_query(GET_BUILD_TRANSACTION_ID_FROM_PSE =>
"select ir.request_id
 from isd_requests ir
 where ir.reference_id = :1
 and ir.request_type_code in (". ISD::Const::st_apf_request_task  .
 "," . ISD::Const::st_apf_req_merge_task . ")" .
 " and last_updated_date = (select max(last_updated_date)
 from isd_requests ir where ir.reference_id = :1
 and ir.request_type_code in (". ISD::Const::st_apf_request_task .
 "," . ISD::Const::st_apf_req_merge_task . "))");

ARUDB::add_query(GET_PREV_REQUEST_LOG =>
"select logfile_name
 from isd_requests where
 reference_id = (select reference_id from
 isd_requests where request_id= :1 )
 and request_id < :1
 order by request_id desc");

ARUDB::add_query(GET_OUI_COMPONENT =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
 from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
 where ald.b_used_by_a     = :1
 and ald.label_dependency = :4" .
 " and ald.a_uses_b = ao1.object_id
 and af1.filetype_id = ao1.filetype_id
 and ald.build_dependency <> 'NO-SHIP'
 and af1.filetype_name = '" . ARU::Const::filetype_name_st_oui . "'" .
 " and ald.label_id = :2
 UNION
 select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
 from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
 where ald.b_used_by_a     = :1
 and ald.label_dependency = :4" .
 " and ald.a_uses_b = ao1.object_id
 and af1.filetype_id = ao1.filetype_id
 and ald.build_dependency <> 'NO-SHIP'
 and af1.filetype_name = '" . ARU::Const::filetype_name_st_oui . "'" .
 " and ald.label_id = :3");


ARUDB::add_query(GET_ONEWAY_OUI_COMPONENT =>
"select DISTINCT object_name
    from aru_objects
    where object_id in (
                        select  a_uses_b
                        from aru_label_dependencies
                        where b_used_by_a = :1
                        and label_dependency = :2)");

ARUDB::add_query(GET_ARU_REQUEST_COMMENT =>
"select  abrh.comments
   from  aru_bugfix_request_history abrh, aru_status_codes sc
  where  abrh.status_id=sc.status_id
    and  abrh.bugfix_request_id = :1
    and  sc.status_id = " . ARU::Const::patch_requested ."
order by abrh.change_date desc, abrh.bugfix_request_history_id desc");

ARUDB::add_query(GET_ARU_DROP_PATCH =>
"select bugfix_request_drop_id
from aru_bugfix_request_drops
where bugfix_request_id = :1
and drop_number = :2 ");

ARUDB::add_query(GET_ST_APF_BUILD=>
"select max(param_value)
from   isd_request_parameters
where  request_id = :1
and param_name = 'st_apf_build' ");


ARUDB::add_query(GET_BASE_RELEASE_INFO =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from bugdb_rpthead_v brv
 , aru_product_releases apr
 , aru_releases ar
 , aru_products ap
 , aru_product_groups apg
 where brv.rptno = :1
 and ap.product_id = :2
 and apr.release_id = ar.release_id
 and ((apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
      or (apr.product_id = ap.product_id))
 and aru_backport_util.pad_version(brv.utility_version) =
     aru_backport_util.pad_version(ar.release_name)
 and ar.release_type like '%B%'
 and apr.product_release_id in (select product_release_id
                                from aru_product_release_labels)");

ARUDB::add_query(GET_RELEASE_INFO =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from bugdb_rpthead_v brv
 , aru_product_releases apr
 , aru_releases ar
 , aru_products ap
 , aru_product_groups apg
 where brv.rptno = :1
 and ap.product_id = :2
 and apr.release_id = ar.release_id
 and ar.release_long_name not like 'Oracle Fusion Middleware 12.2.1.%.0 ONS'
 and ((apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
      or (apr.product_id = ap.product_id))
 and aru_backport_util.pad_version(brv.utility_version) =
     aru_backport_util.pad_version(ar.release_name)
 and apr.product_release_id in (select product_release_id
                                from aru_product_release_labels)");

ARUDB::add_query(GET_RELEASE_LONG_NAME =>
"select release_long_name from
    aru_releases where
    release_id = :1");

ARUDB::add_query(GET_RELEASE_INFO_RFI =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from bugdb_rpthead_v brv
 , aru_product_releases apr
 , aru_releases ar
 , aru_products ap
 , aru_product_groups apg
 where brv.rptno = :1
 and ap.product_id = :2
 and apr.release_id = ar.release_id
 and ((apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
      or (apr.product_id = ap.product_id))
 and aru_backport_util.pad_version(brv.utility_version) =
     aru_backport_util.pad_version(ar.release_name)");

ARUDB::add_query(GET_EM_PLUGIN_RELEASE_DETAILS =>
"select release_name, release_long_name, release_id from
 aru_releases where release_id in
 (select release_id from aru_product_releases
 where product_id = :1 and pset_prefix = :2 )
 and upper(release_long_name) like '%(' || :3 || ')%'");

ARUDB::add_query(GET_DTEJOB_TEMPLATE =>
"select dte.dte_command, dte.dte_command_id
 from apf_dte_commands dte
 where dte.product_release_id = (select apr.product_release_id
                                 from aru_product_releases apr
                                 where apr.product_id= :1 and
                                 apr.release_id= :2)
 and dte.platform_id = :3 and dte.type = :4");

ARUDB::add_query(GET_COMP_DTEJOB_TEMPLATE =>
"select dte.dte_command, dte.dte_command_id, dte.type
from apf_dte_commands dte,
     aru_bugfix_request_objects abro, aru_objects ao
where dte.product_release_id = (select apr.product_release_id
                                from aru_product_releases apr
                                where apr.product_id= :1 and
                                apr.release_id= :2)
 and dte.platform_id = :3
 and abro.bugfix_request_id = :4
 and ao.object_id = abro.object_id
 and ao.filetype_id = " . ARU::Const::filetype_oui . "
 and replace (ao.object_name,dte.type,'') <> ao.object_name");


ARUDB::add_query(GET_DTE_JOBID =>
"select dr.dte_job_id from apf_dte_results dr
 where dr.bugfix_request_id = :1
 and   dr.isd_request_id = :2");

ARUDB::add_query(GET_DTE_ENABLED_PRODUCTS =>
"select dte.product_release_id
 from apf_dte_commands dte, aru_product_releases apr
 where apr.product_id = :1
 and apr.release_id = :2
 and dte.product_release_id = apr.product_release_id
 and dte.platform_id = :3");

ARUDB::add_query(GET_DTE_JOBS_TO_POLL =>
"select dte.dte_job_id
 ,      dte.bugfix_request_id
 ,      dte.isd_request_id
 from   apf_dte_results dte,
        aru_bugfix_requests abr
 where  dte.status in ('" . ARU::Const::dte_job_completed . "' ,
                       '" . ARU::Const::dte_job_running . "',
                       '" . ARU::Const::dte_job_waiting . "' )
 and    dte.bugfix_request_id = abr.bugfix_request_id
 and    dte_command_id <> 2
 and    abr.status_id = " . ARU::Const::patch_ftped_internal);

ARUDB::add_query(GET_TSTFWK_RUNS_TO_POLL =>
"select tr.testrun_id
 ,      tr.bugfix_request_id
, tr.pse_number
, tr.isd_request_id
 from   apf_testruns tr
 where  tr.status_id in (
 select arsc.status_id from aru_status_codes arsc
where  arsc.description in ('" . ARU::Const::tstfwk_job_running . "',
                       '" . ARU::Const::tstfwk_job_waiting . "'))");




ARUDB::add_query(GET_HYBRID_LABEL_DEP =>
"select distinct ao2.object_name, ao2.object_location, ao2.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_filetypes af2, aru_objects ao2
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_hybrid . "'
and   (ald.label_id        = :3 or ald.label_id = :4)
and ald.a_uses_b = ao2.object_id
and af2.filetype_id = ao2.filetype_id
and af2.filetype_name = :2
order by 1");

ARUDB::add_query(GET_PARENT_PRODUCT_ID =>
"select distinct apg.parent_product_id
 from aru_product_groups apg,
    aru_product_releases apr,
     aru_product_release_labels aprl
 where apg.child_product_id = :1
 and   apr.release_id = :2
 and   apr.product_id = apg.parent_product_id
 and   aprl.product_release_id  = apr.product_release_id");

ARUDB::add_query(GET_PARENT_PRODUCT_ID_RFI =>
"select distinct apg.parent_product_id
 from aru_product_groups apg,
    aru_product_releases apr,
     aru_product_release_labels aprl
 where apg.child_product_id = :1
 and   apr.release_id = :2
 and   apr.product_id = apg.parent_product_id
 and apg.parent_product_id in (9480, 9481, 10120)");


ARUDB::add_query(GET_PRODUCT_ABBREVIATION =>
"select ap.product_abbreviation
 from aru_products ap
 where ap.product_id = :1");

ARUDB::add_query(GET_PRODUCT_NAME =>
"select ap.product_name
 from aru_products ap
 where ap.product_id = :1");

ARUDB::add_query(GET_BUGDB_PRODUCT_NAME =>
"select b.description
 from bugdb_product_mv b
 where b.product_id = :1");

ARUDB::add_query(GET_CI_DETAILS=>
  "select request_id
    from apf_build_requests
    where backport_bug = :1
    and request_type = 80297");
  
ARUDB::add_query(GET_GENERIC_OR_PORT_SPECIFIC =>
"with dummy1 as
(
 select  nvl('".PB::Config::apf_grid_id."','APF_PBUILD_GRID') col1
         from dual
 ),
dummy2 as
 (
 select b.generic_or_port_specific
 from bugdb_rpthead_v b, dummy1
 where b.rptno = :1
 and b.status in (11, 51, 52, 35, 74, 75, 80, 90, 93, 98, 37, 10, 38, 88, 40)
 and dummy1.col1<>'APF_FUSION_PBUILD_GRID_NEW'
 and dummy1.col1<>'FUSIONAPPS_US_GRID'
 and dummy1.col1<>'APF_64BIT_PBUILD_GRID'
 and dummy1.col1<>'APF_FUSION_NLS_PBUILD_GRID'
 and dummy1.col1<>'FUSIONAPPS_NLS_GRID'
 UNION
 select b.generic_or_port_specific
 from bugdb_rpthead_v b,dummy1
 where b.rptno = :1
 and dummy1.col1 in ('APF_FUSION_PBUILD_GRID_NEW','FUSIONAPPS_US_GRID',
                     'APF_64BIT_PBUILD_GRID',
                     'APF_FUSION_NLS_PBUILD_GRID','FUSIONAPPS_NLS_GRID')
 )
select generic_or_port_specific from dummy2");

ARUDB::add_query(ST_FILE_TYPES =>
"select filetype_id, filetype_name
   from aru_filetypes
    where description like '% ST Patches%'
    or filetype_id = " . ARU::Const::filetype_id_st_class);

ARUDB::add_query(GET_FIXED_BASE_BUGS =>
"select distinct(abbr.related_bug_number)
    from  aru_bugfix_bug_relationships abbr, aru_bugfixes ab
    where abbr.relation_type = ".ARU::Const::fixed_direct." and
         abbr.bugfix_id = ab.bugfix_id and
         ab.bugfix_rptno = :1 and
         ab.release_id = :2
  order by abbr.related_bug_number");

ARUDB::add_query(GET_ALL_FIXED_BASE_BUGS =>
"select distinct(abbr.related_bug_number)
    from   aru_bugfix_bug_relationships abbr, aru_bugfixes ab,
         isd_bugdb_bugs ibb
  where  abbr.related_bug_number = ibb.bug_number and
         abbr.relation_type in (" . ARU::Const::fixed_direct . ", "
                                  . ARU::Const::fixed_indirect . ") and
         abbr.bugfix_id = ab.bugfix_id and
         ab.bugfix_rptno = :1 and
         ab.release_id = :2
  order by abbr.related_bug_number");

ARUDB::add_query(GET_PARENT_LABEL_NAMES =>
"select distinct aprl2.label_name
 from   aru_release_label_groups arlg
 ,      aru_product_release_labels aprl1
 ,      aru_product_release_labels aprl2
 where  arlg.child_label_id = aprl1.label_id
 and    aprl1.label_name = :1
 and    aprl2.label_id = arlg.parent_label_id");

ARUDB::add_query(GET_CHILD_LABEL_NAMES =>
"select distinct aprl2.label_name
 from   aru_release_label_groups arlg
 ,      aru_product_release_labels aprl1
 ,      aru_product_release_labels aprl2
 where  arlg.parent_label_id = aprl1.label_id
 and    aprl1.label_name = :1
 and    aprl2.label_id = arlg.child_label_id
 and   aprl2.label_name <> 'NO LABEL'");


ARUDB::add_query(GET_CHILD_LABEL_OF_PLATFORM_ID =>
"select distinct aprl2.label_name
 from   aru_release_label_groups arlg
 ,      aru_product_release_labels aprl1
 ,      aru_product_release_labels aprl2
 where  aprl1.label_name = :1
 and    aprl1.label_id = arlg.parent_label_id
 and    aprl2.label_id = arlg.child_label_id
 and    aprl2.platform_id = :2");

ARUDB::add_query(GET_LABEL_PLATFORMS =>
"select distinct platform_id
 from   aru_product_release_labels aprl
 where  label_name = :1");

ARUDB::add_query(GET_ARU =>
"select bugfix_request_id from aru_bugfix_requests
    where bug_number = :1
    and platform_id = :2
    and release_id = :3
    and product_id = :4
    and status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_FA_MPATCH_INCL_ARU =>
"select bugfix_request_id, status_id from aru_bugfix_requests
    where bugfix_id = :1
    and   platform_id = :2
    and   language_id = :3
 order by bugfix_request_id desc");

ARUDB::add_query(GET_SYSTEM_COMBO =>
"select isd_request_id
    from apf_system_patch_details
    where system_tracking_bug = :1
    and subpatch_tracking_bug = :2
    and status = 'Y'");

ARUDB::add_query(GET_SYS_TRK_BUGS =>
"select distinct asp.system_tracking_bug, asp.system_aru
 from apf_system_patch_details asp, aru_bugfix_requests abr
 where asp.subpatch_aru=:1
 and asp.system_aru = abr.bugfix_request_id
 and  abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_SYSTEM_PLATFORM_COMBO =>
"select isd_request_id
    from apf_system_patch_details
    where system_tracking_bug = :1
    and platform_id = :2
    and status = 'Y'");

ARUDB::add_query(GET_SYSTEM_PATCH_ARU =>
"select bugfix_request_id from aru_bugfix_requests
    where bugfix_id = :1
    and platform_id = :2
    and status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_SUBPATCH_PLATFORMS =>
"select distinct abr.platform_id
    from aru_bugfix_requests abr, apf_system_patch_details aspd
    where aspd.system_aru = :1
    and aspd.subpatch_tracking_bug = abr.bug_number
    and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_SUBPATCH_SERIES =>
"select acps.series_name, acps.series_id
from aru_cum_patch_series acps, aru_cum_patch_series_attrs acpsa
where acps.series_id = acpsa.series_id
and acpsa.attribute_name in ('P4FA Series','System Patch Series')
and (upper(acpsa.attribute_value) like :1 or
 upper(acpsa.attribute_default) like :1)");

ARUDB::add_query(GET_CODELINE_OPEN_RELEASE =>
"select distinct
    acr.release_id,
    acr.release_version,
    acr.release_name,
    acs.product_name,
    acs.patch_type,
    acs.product_id,
    acs.series_id,
    acs.base_release_id,
    acr.tracking_bug,
    acr.release_label,
    acs.series_name,
    acs.last_updated_date
    from
    aru.aru_cum_patch_releases acr,
    aru.aru_cum_patch_series acs
    where
    acr.series_id = acs.series_id
    and acs.series_id = :1
    and acr.status_id  = :2
    order by acr.release_id desc");

ARUDB::add_query(GET_ORDERED_CPM_RELEASES =>
"select distinct
    acr.release_id,
    acr.release_version,
    acr.release_name,
    aru.aru_backport_util.get_numeric_version(acr.release_version) numeric_rel_version,
    acs.product_name,
    acs.patch_type,
    acs.product_id,
    acs.series_id,
    acs.base_release_id,
    acr.tracking_bug,
    acr.release_label,
    acs.series_name,
    acs.last_updated_date
    from
    aru.aru_cum_patch_releases acr,
    aru.aru_cum_patch_series acs
    where
    acr.series_id = acs.series_id
    and acs.series_id = :1
    and acr.status_id  = :2
    order by numeric_rel_version desc");

ARUDB::add_query(GET_TRACKING_BUGS =>
"select  tracking_bug
    from aru_cum_patch_Releases
where release_id = :1
union
select to_number(acprp.parameter_value)
from
aru_cum_patch_release_params acprp,
      aru_cum_patch_releases acpra
    WHERE acprp.parameter_type =34593
    and acprp.release_id = acpra.release_id
    and acpra.release_id = :1");
ARUDB::add_query(GET_PSES_IN_SERIES =>
"SELECT brv.rptno pse, bug,  acps.series_id, acps.patch_type, acps.series_name series, release_name, bugs.release_id, release_version, acps.product_name ,
   acps.product_id, tracking_bug
  FROM
    (SELECT acps.series_id,acpr.tracking_bug bug, acps.series_name series, acpr.release_name, acpr.release_id, acpr.release_version, acps. product_name ,      acpr.tracking_bug
      FROM aru_cum_patch_releases acpr, aru_cum_patch_series acps
      WHERE acps.series_id IN
      (
        SELECT DISTINCT acps.series_id
        FROM aru_cum_patch_series acps,
        aru_cum_patch_series_params acpsp
        WHERE acps.series_id       = acpsp.series_id
         AND acpsp.parameter_name   = 'Patch Packaging'
         AND acpsp.parameter_value IN ( 'APF with upload to primary tracking bug','APF with upload to latest tracking bug','Patch Factory')
         AND acps.product_id       IN ( 9480,9481 )
         AND acps.series_name = :1
      )
    AND acps.series_id = acpr.series_id
   UNION
    SELECT acpra.series_id,      to_number(parameter_value) bug ,     acpsa.series_name series,      acpra.release_name,      acpra.release_id,      acpra.release_version,      acpsa. product_name ,      acpra.tracking_bug
    FROM aru_cum_patch_release_params acprp,      aru_cum_patch_releases acpra,      aru_cum_patch_series acpsa
    WHERE acprp.parameter_type =34593
    AND acprp.release_id       = acpra.release_id
    AND acpsa.series_id       IN
      ( SELECT DISTINCT acps.series_id      FROM aru_cum_patch_series acps,       aru_cum_patch_series_params acpsp
      WHERE acps.series_id       = acpsp.series_id
      AND acpsp.parameter_name   = 'Patch Packaging'
      AND acpsp.parameter_value IN ( 'APF with upload to primary tracking bug','APF with upload to latest tracking bug','Patch Factory')
      AND acps.product_id       IN ( 9480,9481 )
      AND acps.series_name = :1
      )
    AND acpsa.series_id = acpra.series_id
    ) bugs,
bugdb_rpthead_v brv,   aru_cum_patch_series acps
  WHERE brv.base_rptno             = bugs.bug
  AND acps.series_name             = bugs.series
  AND brv.generic_or_port_specific = 'O'
  AND brv.portid = :2
  order by bug desc");

ARUDB::add_query(GET_LABEL_FROM_PSE_MULTIARU =>
"select REGEXP_SUBSTR(substr(REGEXP_SUBSTR(param_value, 'LABEL.*!FRO'),7),'.*\\d'), request_id
from isd_request_parameters
where request_id in (select request_id from isd_requests where reference_id= :1   and request_type_code=80020)
and param_value like '%LABEL%' and  param_value not like '%META_DATA_ONLY:1%' order by 1 desc");


ARUDB::add_query(GET_LABEL_FROM_PSE =>
"with maxrel as (
  select ir.reference_id, ir.request_id, irp.param_value
 from isd_Request_parameters irp, isd_requests ir
 where ir.REQUEST_TYPE_CODE = 80020
 and ir.request_id = irp.request_id
 and irp.param_value like '%LABEL:%' and ir.reference_id=:1 and irp.param_value not like '%META_DATA_ONLY:1%')
 select  REGEXP_SUBSTR(substr(REGEXP_SUBSTR(m.param_value, 'LABEL.*!FRO'),7),'.*\\d'), m.request_id
 from maxrel m
 where m.request_id = (
 select max(m2.request_id)
 from maxrel m2)");

 ARUDB::add_query(GET_LABEL_FROM_ARU =>
 "select comments
     from aru_bugfix_request_history
     where bugfix_request_history_id =
     (select max(bugfix_request_history_id)
      from aru_bugfix_request_history
      where bugfix_request_id=:1
      and comments like 'Requested through apfcli%')");

 ARUDB::add_query(GET_ADDL_SERIES_INFO_VALUE =>
 "select info_value
     from aru_cum_series_addl_info
     where series_id = :1
     and info_type = :2
     and info_name = :3");

 ARUDB::add_query(GET_PSE_FROM_ARU =>
   "select backport_bug from aru_backport_bugs
      where bugfix_request_id = :1");

 ARUDB::add_query(GET_ARU_STATUSCODE_ID =>
"select status_id from aru_status_codes where description=:1");

ARUDB::add_query(GET_PSES_IN_SERIES =>
"SELECT brv.rptno pse, bug,  acps.series_id, acps.patch_type, acps.series_name series, release_name, bugs.release_id, release_version, acps.product_name ,
   acps.product_id, tracking_bug
  FROM
    (SELECT acps.series_id,acpr.tracking_bug bug, acps.series_name series, acpr.release_name, acpr.release_id, acpr.release_version, acps. product_name ,      acpr.tracking_bug
      FROM aru_cum_patch_releases acpr, aru_cum_patch_series acps
      WHERE acps.series_id IN
      (
        SELECT DISTINCT acps.series_id
        FROM aru_cum_patch_series acps,
        aru_cum_patch_series_params acpsp
        WHERE acps.series_id       = acpsp.series_id
         AND acpsp.parameter_name   = 'Patch Packaging'
         AND acpsp.parameter_value IN ( 'APF with upload to primary tracking bug','APF with upload to latest tracking bug','Patch Factory')
         AND acps.product_id       IN ( 9480,9481 )
         AND acps.series_name = :1
      )
    AND acps.series_id = acpr.series_id
   UNION
    SELECT acpra.series_id,      to_number(parameter_value) bug ,     acpsa.series_name series,      acpra.release_name,      acpra.release_id,      acpra.release_version,      acpsa. product_name ,      acpra.tracking_bug
    FROM aru_cum_patch_release_params acprp,      aru_cum_patch_releases acpra,      aru_cum_patch_series acpsa
    WHERE acprp.parameter_type =34593
    AND acprp.release_id       = acpra.release_id
    AND acpsa.series_id       IN
      ( SELECT DISTINCT acps.series_id      FROM aru_cum_patch_series acps,       aru_cum_patch_series_params acpsp
      WHERE acps.series_id       = acpsp.series_id
      AND acpsp.parameter_name   = 'Patch Packaging'
      AND acpsp.parameter_value IN ( 'APF with upload to primary tracking bug','APF with upload to latest tracking bug','Patch Factory')
      AND acps.product_id       IN ( 9480,9481 )
      AND acps.series_name = :1
      )
    AND acpsa.series_id = acpra.series_id
    ) bugs,
bugdb_rpthead_v brv,   aru_cum_patch_series acps
  WHERE brv.base_rptno             = bugs.bug
  AND acps.series_name             = bugs.series
  AND brv.generic_or_port_specific = 'O'
  AND brv.portid = :2
  order by bug desc");

ARUDB::add_query(GET_LATEST_SUBPATCH =>
"select RANK() OVER (ORDER BY to_char(abr.last_updated_date,'YYMMDDHHMMSS') DESC) req_rank, abr.bugfix_request_id, abr.bug_number, abr.last_updated_date, abr.requested_date
from aru_bugfix_requests abr , aru_bugfix_request_history abrh
where abr.bug_number in (
select  tracking_bug
from aru_cum_patch_Releases
where release_id = :1
union
select to_number(acprp.parameter_value)
from
aru_cum_patch_release_params acprp,
      aru_cum_patch_releases acpra
    WHERE acprp.parameter_type =34593
    and acprp.release_id = acpra.release_id
    and acpra.release_id = :1)
and abr.platform_id in (2000, :2)
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")
and abr.bugfix_request_id = abrh.bugfix_request_id
and (upper(abrh.comments) like '%APPLIED SUCCESSFULLY%'  or
upper(abrh.comments) like '%INSTALL TEST SUCCEEDED%')");

ARUDB::add_query(GET_LATEST_METADATA_SUBPATCH =>
"select RANK() OVER (ORDER BY to_char(abr.last_updated_date,'YYMMDDHHMMSS') DESC) req_rank, abr.bugfix_request_id, abr.bug_number, abr.last_updated_date, abr.requested_date
from aru_bugfix_requests abr , aru_bugfix_request_history abrh
where abr.bug_number in (
select  tracking_bug
from aru_cum_patch_Releases
where release_id = :1
union
select to_number(acprp.parameter_value)
from
aru_cum_patch_release_params acprp,
      aru_cum_patch_releases acpra
    WHERE acprp.parameter_type =34593
    and acprp.release_id = acpra.release_id
    and acpra.release_id = :1)
and abr.platform_id in (2000, :2)
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")
and abr.bugfix_request_id = abrh.bugfix_request_id");

ARUDB::add_query(IS_DATABASE_METADATA_PATCH_REQUESTED =>
"select ir.request_id from isd_requests ir, isd_request_parameters irp
where ir.request_id=irp.request_id
and irp.PARAM_NAME='metadata_only_request'
and ir.reference_id=:1
");

    ARUDB::add_query(GET_GENERIC_OR_PLATFORM_ARU =>
        "select abr.bugfix_request_id, abr.platform_id, abr.bug_number from aru_bugfix_requests abr, aru_bugfix_requests abr1 where
abr.platform_id in (2000, :2)
and abr1.bugfix_request_id= :1
and abr.release_id = abr1.release_id
and abr.bug_number = abr1.bug_number
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
            ARU::Const::patch_ftped_dev . "," .
            ARU::Const::ready_to_ftp_to_support . "," .
            ARU::Const::ready_to_ftp_to_dev . "," .
            ARU::Const::patch_ftped_internal. ")");


 ARUDB::add_query(GET_ALL_PATCH_PLATFORMS =>
     "select distinct(abr.platform_id) from aru_bugfix_requests abr, aru_bugfix_requests abr1 where
abr1.bugfix_request_id= :1
and abr.release_id = abr1.release_id
and abr.bug_number = abr1.bug_number
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
         ARU::Const::patch_ftped_dev . "," .
         ARU::Const::ready_to_ftp_to_support . "," .
         ARU::Const::ready_to_ftp_to_dev . "," .
         ARU::Const::patch_ftped_internal. ")");

 ARUDB::add_query(GET_LATEST_SPB_COMPONENT_PATCH =>
        "select RANK() OVER (ORDER BY to_char(abr.last_updated_date,'YYMMDDHHMMSS') DESC) req_rank, abr.bugfix_request_id, abr.bug_number, abr.last_updated_date, abr.requested_date
from aru_bugfix_requests abr
where abr.bug_number in (
select  tracking_bug
from aru_cum_patch_Releases
where release_id = :1
union
select to_number(acprp.parameter_value)
from
aru_cum_patch_release_params acprp,
      aru_cum_patch_releases acpra
    WHERE acprp.parameter_type =34593
    and acprp.release_id = acpra.release_id
    and acpra.release_id = :1)
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
            ARU::Const::patch_ftped_dev . "," .
            ARU::Const::ready_to_ftp_to_support . "," .
            ARU::Const::ready_to_ftp_to_dev . "," .
            ARU::Const::patch_ftped_internal. ")");


 ARUDB::add_query(GET_ARU_BUG =>
"select bug_number, platform_id, status_id, last_updated_date
    from aru_bugfix_requests
    where bugfix_request_id = :1");

ARUDB::add_query(GET_SUBPATCH_SYSTEM_PATCH =>
"select acpr.series_name, aspd.subpatch_series_id, aspd.subpatch_tracking_bug, aspd.subpatch_aru
    from aru.apf_system_patch_details aspd, aru_cum_patch_series acpr
    where aspd.system_aru = :1
    and aspd.isd_request_id = :2
    and aspd.status = 'Y'
    and aspd.subpatch_series_id = acpr.series_id
    order by case when upper(acpr.series_name) like 'DATABASE%' then 0 else 1 end");

ARUDB::add_query(GET_SUBPATCHES =>
"select distinct aspd.subpatch_tracking_bug, acps.family_name
    from aru.apf_system_patch_details aspd, aru_cum_patch_series acps
    where aspd.system_tracking_bug = :1
    and aspd.status = 'Y'
    and acps.series_id = aspd.subpatch_series_id");

ARUDB::add_query(GET_SUBPATCHES_DETAILS =>
"select distinct acpr.series_name, aspd.subpatch_series_id, aspd.subpatch_tracking_bug, aspd.subpatch_aru
    from aru.apf_system_patch_details aspd, aru_cum_patch_series acpr
    where aspd.system_aru =:1
    and aspd.status = 'Y'
    and acpr.series_id = aspd.subpatch_series_id");

ARUDB::add_query(GET_LATEST_SUBPATCH_RC =>
"select RANK() OVER (ORDER BY to_char(abr.last_updated_date,'YYMMDDHHMMSS') DESC) req_rank, abr.bugfix_request_id, abr.last_updated_date, abr.requested_date
from aru_bugfix_requests abr
where abr.bug_number in (
select acpra1.tracking_bug
from
aru_cum_patch_release_params acprp,
    aru_cum_patch_releases acpra, aru_cum_patch_releases acpra1
    WHERE acprp.parameter_type =34593
    and acprp.release_id = acpra.release_id
    and acpra.release_id = :1
    and to_number(acprp.parameter_value) = acpra1.tracking_bug
    and acpra1.status_id=34529)
and abr.platform_id in (2000, :2)
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_AUTO_ARU =>
"select bugfix_request_id from aru_bugfix_requests abr
    where abr.bug_number = :1
    and abr.platform_id = :2
    and abr.release_id = :3
    and abr.product_id = :4
    and abr.status_id  not in (".ARU::Const::patch_deleted.",".
                             ARU::Const::patch_on_hold.",".
                             ARU::Const::patch_q_delete .")
    and abr.bugfix_request_id not in
    (select bugfix_request_id
     from aru_backport_bugs
     where bugfix_request_id = abr.bugfix_request_id
     and backport_bug_type in (".ISD::Const::st_blr.",".
                               ISD::Const::st_mlr."))");

ARUDB::add_query(GET_PATCH_RELEASED_DETAILS =>
"select bugfix_request_id from aru_bugfix_requests abr
    where abr.bug_number = :1
    and abr.platform_id = :2
    and abr.release_id = :3
    and abr.product_id = :4
    and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev .")");


#
# order by is required to get oasp_pf as the
# family product if any product was associated with two product families
# like oid(10040)
#
ARUDB::add_query(GET_ANT_PF_XML =>
"select ap.product_abbreviation
 from   aru_products ap
 ,      aru_product_groups apg
 where  apg.child_product_id = :1
 and    apg.parent_product_id = ap.product_id
 and    ap.product_id in (" . ARU::Const::product_oracle_database. "," .
                              ARU::Const::product_smp_pf . "," .
                              ARU::Const::product_oracle_app_server . ")
    order by 1");

ARUDB::add_query(GET_ANT_PF_XML_CNT =>
"select count(ap.product_abbreviation)
 from   aru_products ap
 ,      aru_product_groups apg
 where  apg.child_product_id = :1
 and    apg.parent_product_id = ap.product_id
 and    ap.product_id in (" . ARU::Const::product_oracle_database. "," .
                              ARU::Const::product_smp_pf . "," .
                              ARU::Const::product_oracle_app_server . ")");

ARUDB::add_query(GET_FIXED_MLR_BUGS =>
"select distinct(abbr.related_bug_number)
  from aru_bugfix_bug_relationships abbr, aru_bugfixes ab,
     isd_bugdb_bugs ibb
  where abbr.related_bug_number = ibb.bug_number and
     abbr.relation_type in (" . ARU::Const::fixed_direct . "," .
     ARU::Const::fixed_indirect . "," . ARU::Const::fixed_direct_others .
     ") and abbr.bugfix_id = ab.bugfix_id and
     ab.bugfix_rptno = :1 and
     ab.release_id = :2 and
     abbr.related_bug_number != ab.bugfix_rptno
  order by abbr.related_bug_number");

ARUDB::add_query(GET_GROUP_BASE_LABEL =>
"select label_id, label_name
   from aru_product_release_labels
   where label_id = (
     select parent_label_id
       from aru_release_label_groups
       where child_label_id = :1)");

ARUDB::add_query(GET_BASE_OBJECT_ID =>
"select ao.object_id, ao.object_name, ao.object_location, 'rcs_version',
        ao.filetype_id, af.filetype_name
  from aru_objects ao, aru_filetypes af, aru_product_releases apr
  where ao.object_name = :1
    and ao.object_location = :2
    and apr.release_id = :3
    and apr.product_id = :4
    and apr.product_release_id = ao.product_release_id
    and af.filetype_id = ao.filetype_id");

ARUDB::add_query(GET_FMW_BASE_LABEL_2 =>
"select arlg.parent_label_id, aprl2.label_name
from aru_product_release_labels aprl,
aru_product_release_labels aprl2,
aru_release_label_groups arlg,
 aru_product_releases apr,
 apf_configurations ac,
 aru_product_groups apg,
 aru_products ap
where apg.child_product_id = :1
and apr.product_id = apg.parent_product_id
and apr.release_id = :2
and apr.release_id = ac.release_id
and apg.child_product_id = ap.product_id
and aprl.product_release_id = apr.product_release_id
and aprl.platform_id = ac.platform_id
and ac.request_enabled = 'B'
and ac.apf_type = 'M'
and arlg.child_label_id = aprl.label_id
and aprl2.label_id = arlg.parent_label_id
and ac.language_id = 0");

ARUDB::add_query(GET_DEV_MAKE_DETAILS =>
"select object_name, object_location, object_id, object_type
from aru_objects where object_id in
(select a_uses_b from aru_label_dependencies
where b_used_by_a  = :1
and build_dependency = 'DEV-MAKE')");

ARUDB::add_query(GET_NO_SHIP_DETAILS =>
"select ao.object_id, ao.object_name, ao.object_location,
    alb.a_uses_b
  from aru_objects ao, aru_label_dependencies alb
  where ao.object_id = alb.a_uses_b
    and alb.b_used_by_a = :1
    and alb.build_dependency = :2
    and (select count(distinct ald.build_dependency)
         from aru_label_dependencies ald
         where b_used_by_a = :1) = 1");

ARUDB::add_query(GET_BUILD_DEP_DETAILS =>
"select ao.object_id, ao.object_name, ao.object_location,
    alb.a_uses_b
  from aru_objects ao, aru_label_dependencies alb
  where ao.object_id = alb.a_uses_b
    and alb.b_used_by_a = :1
     and alb.build_dependency = :2
     and alb.label_dependency not like :3");

ARUDB::add_query(GET_LABEL_BUILD_DEP_DETAILS =>
"select ao.object_id, ao.object_name, ao.object_location,
    alb.a_uses_b
  from aru_objects ao, aru_label_dependencies alb
  where ao.object_id = alb.a_uses_b
    and alb.b_used_by_a = :1
    and alb.label_id in (:2,:3)
     and alb.build_dependency = :4
     and alb.label_dependency not like :5");

ARUDB::add_query(GET_DEFAULT_ASSIGNEE =>
"select new_programmer, new_status
  from bugdb_rpthead_history_v
  where rptno = :1 and old_programmer is null");

ARUDB::add_query(GET_TEST_NAME =>
"select substr(rtg.VALUE,10)
    FROM bugdb_tracking_groups_v tg,
    bugdb_rpthead_tracking_gps_v rtg
    where rtg.rptno =  :1
    and rtg.TRACKING_GROUP_ID = tg.ID
    and tg.name = 'Patch Automation Attributes'");

ARUDB::add_query(GET_TEST_NAME_BUGDB =>
"select distinct test_name
    from bugdb_rpthead_v
    where rptno = :1");

ARUDB::add_query(GET_BUG_VERSION =>
"select version
  from bugdb_rpthead_v
  where rptno = :1");

ARUDB::add_query(GET_BUG_REPORTED_DATE =>
"select RPTDATE, trunc(sysdate - rptdate)
  from bugdb_rpthead_v
  where rptno = :1");

ARUDB::add_query(CHECK_BASE_BUG_REGRESSED =>
"select count(1)
  from bugdb_rpthead_v
  where rptno = :1
  and regression_status = 'CONFIRMED'");

ARUDB::add_query (GET_REGRESSED_BLR =>
"select max (a.rptno)
    from bugdb_rpthead_v a, bugdb_rpthead_v b
    where b.rptno = :1
    and a.release_id = b.release_id
    and a.generic_or_port_specific = b.generic_or_port_specific
    and a.base_rptno = b.base_rptno
    and a.status in (55, 59)");

ARUDB::add_query(GET_BUGFIX_BLR_NO =>
"select abr.backport_bug
   from aru_backport_requests abr, bugdb_rpthead_v rpt
  where abr.request_type = " . ARU::Const::backport_blr . "
    and abr.status_id != " . ARU::Const::backport_request_deleted . "
    and abr.bugfix_id = :1
    and abr.backport_bug = rpt.rptno
    and rpt.status not in (53, 55, 59, 36, 32, 92, 96)");

ARUDB::add_query( GET_BUILD_REQUEST_ID =>
 "select request_id, request_type_code, last_updated_date,
         reference_id, creation_date
    from isd_requests
   where reference_id = (select reference_id
                           from isd_requests
                          where request_id= :1 )
     and last_updated_date <= (select last_updated_date
                                 from isd_requests
                                where request_id= :1)
   order by request_id desc");

ARUDB::add_query( GET_FIRST_REQUEST_ID =>
"select request_id  from isd_requests
   where  reference_id = (select reference_id from isd_requests
                       where request_id= :1 )
   and last_updated_date =
                     (select max(last_updated_date) from isd_requests
                      where  reference_id =
                          (select reference_id  from isd_requests
                             where request_id= :1 )
                               and  request_type_code in (".
                                      ISD::Const::st_apf_req_merge_task.",".
                                      ISD::Const::st_apf_request_task.
                               ") and  last_updated_date <
                                   (select last_updated_date  from isd_requests
                                                  where request_id= :1))" );

ARUDB::add_query( GET_BPR_BUILD_REQUEST_ID =>
"select request_id  from isd_requests
  where  reference_id   = :1
     and request_type_code = :2
     and status_code = ". ISD::Const::isd_request_stat_succ .
   " and creation_date =
        (select  max(creation_date) from isd_requests
          where  reference_id   = :1
             and request_type_code = :2
            and status_code = ". ISD::Const::isd_request_stat_succ .")");

ARUDB::add_query( GET_PF_PREPROCESS_REQ_ID =>
"select request_id  from isd_requests
    where  reference_id   = :1
    and request_type_code = :2
    and last_updated_date =
    (select  max(last_updated_date) from isd_requests
     where  reference_id   = :1
     and request_type_code = :2)");

ARUDB::add_query( GET_BP_BASE_TXNS =>
"select attribute_value,attribute_name
    from aru_transaction_attributes
    where transaction_id = :1
    and attribute_name like 'TransList%'");

ARUDB::add_query(GET_ONEWAY_DETAILS =>
"select ao.object_id,ao.object_name, ao.object_location,
    alb.a_uses_b
  from aru_objects ao, aru_label_dependencies alb
  where ao.object_id = alb.a_uses_b
    and alb.b_used_by_a = :1
     and alb.build_dependency = 'ONEWAY-COPY'");

ARUDB::add_query(GET_BRANCHED_FARM_REQUESTS =>
" select request_id from isd_requests
    where  reference_id =
     ( select reference_id from isd_requests where request_id= :1 )
      and request_type_code = " . ISD::Const::st_apf_regress .
      " and  last_updated_date <
             ( select last_updated_date
                  from isd_requests where request_id= :1 )
    order by last_updated_date desc");

ARUDB::add_query(GET_BRANCHED_FARM_AUTO_REQUESTS =>
" select request_id from isd_requests
    where  reference_id = :2
    and request_type_code = " . ISD::Const::st_apf_regress .
      " and  last_updated_date <
             ( select last_updated_date
                  from isd_requests where request_id= :1 )
    order by last_updated_date desc");

ARUDB::add_query(GET_FUSION_OBJECT_INFO =>
"select ao.object_id, ao.object_name, ao.object_location,
        ao.filetype_id, af.filetype_name
   from aru_objects ao, aru_product_releases apr,
        aru_label_dependencies ald, aru_filetypes af
  where ao.object_name = :1
    and ao.object_location = :2
    and apr.product_id = :3
    and apr.release_id = :4
    and apr.product_release_id = ao.product_release_id
    and af.filetype_id = ao.filetype_id
    and ald.label_dependency = '" . ARU::Const::dependency_oui . "'" ."
    and ald.b_used_by_a = ao.object_id
    and ald.a_uses_b <> ald.b_used_by_a");

ARUDB::add_query(GET_PATCH_OBJ_VERSION =>
"select max(object_version_id)
    from aru_patch_obj_versions
    where bugfix_request_id = :1
    and   object_version_id = :2");

ARUDB::add_query(GET_OUI_OBJECT_INFO =>
"select a_uses_b
   from aru_label_dependencies
  where b_used_by_a = :1
    and label_dependency = '" . ARU::Const::dependency_oui . "'" ."
    and label_id = :2");

ARUDB::add_query(GET_OUI_VERSION =>
"select oui_version
    from aru_oui_versions
    where object_id = :1
    and label_id  = :2");

ARUDB::add_query(GET_MIN_OPATCH_VERSION =>
"select opatch_version
    from apf_min_opatch_versions
    where release_id = :1
    and patch_type   = :2");

ARUDB::add_query(GET_OUI_NAME =>
"select distinct ao.object_name
    from aru_objects ao,
    aru_label_dependencies ald,
    aru_product_release_labels aprl
    where aprl.label_id in (:1,:2)
    and ao.object_name like '%.oui'
    and  ao.product_release_id = aprl.product_release_id
    and  ao.object_id = ald.a_uses_b");


ARUDB::add_query(GET_PRODUCT_FAMILY =>
"select
        distinct
        ap1.product_abbreviation
from  aru_product_groups apg,
        aru_products ap1,
        aru_products ap2,
        aru_product_releases apr
where
        apr.release_id = :1 and
        apg.relation_type = :2 and
        ap2.product_abbreviation = :3 and
        ap2.product_id = apr.product_id and
        ap1.product_id = apg.parent_product_id and
        ap2.product_id = apg.child_product_id ");

ARUDB::add_query(GET_PRODUCT_ID =>
"select ap1.product_id from aru_products ap1
 where upper(ap1.product_abbreviation) = upper(:1) ");

ARUDB::add_query(GET_PROD_FAMILY_ID =>
"select ap1.product_id from aru_products ap1
 where upper(ap1.product_abbreviation) = upper(:1)
    and product_type = 'F'");

ARUDB::add_query(GET_PRODUCT_RELEASE =>
"select
    product_id, release_id
 from
    aru_product_releases
 where
    product_release_id = (select product_release_id
                    from aru_product_release_labels
                    where label_id = :1) ");

ARUDB::add_query(GET_CHECKIN_OBJECTS =>
"select ao.object_name, ao.object_location,
max(substr(abov.rcs_version,0,(instr(abov.rcs_version,'/',-1)))) ||
max(to_number(substr(abov.rcs_version,(instr(abov.rcs_version,'/',-1)+1))))
   from aru_objects ao, aru_bugfix_object_versions abov
  where ao.object_id = abov.object_id
    and abov.bugfix_id in (
        (select related_bugfix_id
           from aru_bugfix_relationships
          where bugfix_id = (select bugfix_id from aru_bugfixes
                              where bugfix_rptno = :1
                                and release_id = :2)
            and relation_type = " .
                 ARU::Const::build_only_prereq_direct . ")
          union
        (select bugfix_id
           from aru_bugfixes
          where bugfix_rptno = :1
            and release_id = :2))
group by ao.object_name, ao.object_location");

ARUDB::add_query(GET_FUSION_BUNDLE_OBJECTS =>
"select ao.object_name, ao.object_location,
max(substr(abov.rcs_version,0,(instr(abov.rcs_version,'/',-1)))) ||
max(to_number(substr(abov.rcs_version,(instr(abov.rcs_version,'/',-1)+1))))
   from aru_objects ao, aru_bugfix_object_versions abov
  where ao.object_id = abov.object_id
    and abov.bugfix_id in
        (select related_bugfix_id
           from aru_bugfix_relationships
          where bugfix_id = (select bugfix_id from aru_bugfixes
                              where bugfix_rptno = :1
                                and release_id = :2)
            and relation_type in (" . ARU::Const::included_direct . ", " .
                                      ARU::Const::included_indirect . "))
group by ao.object_name, ao.object_location");

ARUDB::add_query(GET_REMOVED_OBJECTS =>
"select ata.attribute_value
   from aru_bugfixes ab, aru_bugfix_relationships abr,
        aru_transactions at, aru_transaction_attributes ata
  where ab.bugfix_id = abr.bugfix_id
    and abr.related_bugfix_id = at.bugfix_id
    and at.transaction_id = ata.transaction_id
    and ata.attribute_name = '" .
        ARU::Const::trans_attrib_removed_files . "'
    and ab.bugfix_rptno = :1
    and ab.release_id = :2
    and abr.relation_type = " . ARU::Const::build_only_prereq_direct);

ARUDB::add_query(GET_BUNDLE_PATCH_REMOVED_OBJECTS =>
"select ata.attribute_value
   from aru_bugfixes ab, aru_bugfix_relationships abr,
        aru_transactions at, aru_transaction_attributes ata
  where ab.bugfix_id = abr.bugfix_id
    and abr.related_bugfix_id = at.bugfix_id
    and at.transaction_id = ata.transaction_id
    and ata.attribute_name = '" .
        ARU::Const::trans_attrib_removed_files . "'
    and ab.bugfix_rptno = :1
    and ab.release_id = :2
    and abr.relation_type in (" . ARU::Const::included_direct . ", " .
                                  ARU::Const::included_indirect . ")");

ARUDB::add_query(GET_ADE_TRANSACTION_ID =>
"select atr.transaction_id
   from aru_transactions atr
  where atr.bugfix_id =
        (select ab.bugfix_id
           from aru_bugfixes ab
          where ab.bugfix_rptno = :1
            and ab.release_id = :2)");

ARUDB::add_query(GET_PRODUCT_ID_BY_SUBC =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 where  ap.bugdb_product_id = :1
 and    ap.bugdb_component = :2
 and    ap.bugdb_subcomponent = :3");

ARUDB::add_query(GET_PRODUCT_ID_BY_C =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 where  ap.bugdb_product_id = :1
 and    ap.bugdb_component = :2");

ARUDB::add_query(GET_PRODUCT_ID_BY_ANY =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 where  ap.bugdb_product_id = :1
 and    ap.bugdb_subcomponent = 'ANY'");

ARUDB::add_query(GET_PRODUCT_ID_BY_P =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 where  ap.bugdb_product_id = :1
 and    ap.product_type = 'P'");

ARUDB::add_query(GET_PRODUCT_ID_BY_PF =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 where  ap.bugdb_product_id = :1
 and    ap.product_type = 'F'");

ARUDB::add_query(GET_PRODUCT_ID_BY_LABEL =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 ,      aru_product_releases apr
 ,      aru_product_release_labels aprl
 where  ap.product_id = apr.product_id
 and    aprl.product_release_id = apr.product_release_id
 and    ap.bugdb_product_id = :1
 and    aprl.label_name like :2 escape '\\'");

ARUDB::add_query(GET_PRODUCT_FROM_CPM_SERIES =>
"select distinct acps.product_id
 ,      ap.product_abbreviation
 from   aru_cum_patch_series_params acpsp
 ,      aru_cum_patch_series acps
 ,      aru_products ap
 where  acpsp.parameter_name = 'BUGDBID'
 and    acpsp.parameter_value = :1
 and    acps.product_id = ap.product_id
 and    acpsp.series_id = acps.series_id");

ARUDB::add_query(GET_PRODUCT_COUNT_FROM_CPM_SERIES =>
"select count(distinct acps.product_id)
 from   aru_cum_patch_series_params acpsp
 ,      aru_cum_patch_series acps
 where  acpsp.parameter_name = 'BUGDBID'
 and    acpsp.parameter_value = :1
 and    acpsp.series_id = acps.series_id");

ARUDB::add_query(GET_PRODUCT_ID_BY_APG =>
"select distinct p.product_id
 ,      p.product_abbreviation
 from   aru_products c
 ,      aru_products p
 ,      aru_product_groups apg
 where  apg.child_product_id = c.product_id
 and    c.bugdb_product_id = :1
 and    apg.parent_product_id = p.product_id
 and    p.product_type = 'F'");

ARUDB::add_query(GET_ARU_PRODUCT_ID =>
"select   distinct ap.product_id
    ,      ap.product_abbreviation
    from   aru_products ap
    where  ap.bugdb_product_id = :1
    and    ap.product_type = :2");

ARUDB::add_query(GET_ARU_PRODUCT_ID_W_ANY =>
"select   distinct ap.product_id
    ,      ap.product_abbreviation
    from   aru_products ap
    where  ap.bugdb_product_id = :1
    and    ap.product_type = :2
    and    ap.bugdb_subcomponent = 'ANY'");

ARUDB::add_query(GET_ARU_PRODUCT_ID_P =>
"select   distinct ap.product_id
   ,      ap.product_abbreviation
   from   aru_products ap
   ,      aru_product_release_labels aprl
   ,      aru_product_releases apr
   where  ap.product_id = apr.product_id
   and    apr.product_release_id = aprl.product_release_id
   and    ap.bugdb_product_id = :1
   and    apr.release_id = :2
   and    ap.product_type = 'P'
   and    ap.bugdb_subcomponent = 'ANY'");

ARUDB::add_query(GET_ARU_PRODUCT_ID_PF =>
"select distinct ap.product_id
 ,      ap.product_abbreviation
 from   aru_products ap
 ,      aru_products c
 ,      aru_product_groups apg
 ,      aru_product_release_labels aprl
 ,      aru_product_releases apr
 ,      aru_release_label_groups arlg
 where  c.product_id = apg.child_product_id
 and    ap.product_id = apg.parent_product_id
 and    ap.product_id = apr.product_id
 and    apr.product_release_id = aprl.product_release_id
 and    c.bugdb_product_id = :1
 and    apr.release_id = :2
 and    arlg.child_label_id = aprl.label_id");

ARUDB::add_query(GET_LABEL_ID =>
" select distinct label_id
         from aru_product_release_labels aprl
         , aru_product_releases apr
         , aru_release_label_groups arlg
         where aprl.product_release_id = apr.product_release_id
         and  apr.release_id = :1
         and aprl.label_name = :2
         and aprl.platform_id = :3 ");
ARUDB::add_query(GET_PATCH_TYPE =>
"select ab.patch_type
from    aru_bugfixes ab, aru_bugfix_requests abr
where   ab.bugfix_id = abr.bugfix_id
and     abr.bugfix_request_id = :1");

#
# order by is required to get oasp_pf as the
# family product if any product was associated with two product families
# like oid(10040)
#
ARUDB::add_query(GET_DIRECT_PARENT_PRODUCT =>
"select distinct parent_product_id, ap1.product_abbreviation
 from   aru_product_groups apg
    ,   aru_products ap
    ,   aru_products ap1
    ,   aru_product_releases apr
    ,   aru_product_release_labels aprl
 where  apg.child_product_id = ap.product_id
 and    apg.relation_type    = " . ARU::Const::direct_relation . "
 and    apr.product_release_id = aprl.product_release_id
 and    (apr.product_id = apg.parent_product_id or
         apr.product_id = apg.child_product_id)
 and    apr.release_id = :2
 and    ap.product_id = :1
 and    ap1.product_id = apg.parent_product_id
 and    ap.product_type = '" . ARU::Const::product_type_product . "'
 order by 2");

ARUDB::add_query(GET_OBJECT_TYPE =>
"select object_type from aru_objects where object_id = :1");

ARUDB::add_query(GET_ANY_LABEL_DEP =>
"select distinct ao.object_id, ao.object_name, ao.object_location,
        ao.object_type, ald.label_dependency
from    aru_objects ao, aru_label_dependencies ald
where   ald.b_used_by_a = :1
and     ao.object_id  = ald.a_uses_b");

ARUDB::add_query(ARU_BUGFIX_ID =>
"select bugfix_id
 from   aru_bugfixes
 where  release_id = :1
 and    bugfix_name = :2");

ARUDB::add_query(WAS_SERVER_BOUNCED =>
"select count(*) from isd_request_history
    where request_id = :1 and error_message like
    'Daemon process terminated unexpectedly%'");

ARUDB::add_query(GET_TESTRUN_STATUS_DESCRIPTION =>
"select description from aru_status_codes where status_id=(select status_id
from apf_testruns where testrun_id= :1)");

ARUDB::add_query(GET_FUSION_DEPENDENT_CHECKINS =>
"select ab2.bugfix_rptno
 from   aru_bugfix_relationships abr
    ,   aru_bugfixes ab1
    ,   aru_bugfixes ab2
    ,   aru_releases ar
    ,   aru_products ap
 where ab1.bugfix_id = abr.bugfix_id
 and   ab1.bugfix_rptno = :1
 and   ab1.release_id = :2
 and   abr.relation_type = " . ARU::Const::build_only_prereq_direct . "
 and   ab2.bugfix_id = abr.related_bugfix_id
 and   ab2.status_id != " . ARU::Const::checkin_obsoleted . "
 and   ar.release_id = ab2.release_id
 and   ap.product_id = ab2.product_id
order by ab2.bugfix_rptno");

ARUDB::add_query(GET_PREREQ_BUGFIXES =>
"select related_bugfix_id, related_bug_number, relation_type
    from aru_bugfix_relationships
    where bugfix_id = :1
    and relation_type in (" . ARU::Const::prereq_direct . ", " .
                              ARU::Const::prereq_indirect . ", " .
                              ARU::Const::prereq_cross_direct . ", " .
                              ARU::Const::prereq_cross_indirect . ")");

ARUDB::add_query(GET_US_ARU =>
"select max(bugfix_request_id)
 from aru_bugfix_requests
 where bugfix_id = :1 and
 language_id = " . ARU::Const::language_US . " and ".
" platform_id in ( " . ARU::Const::platform_generic . " , " .
ARU::Const::platform_linux64_amd . " ) " .
" and status_id  not in (".ARU::Const::patch_deleted.",".
                             ARU::Const::patch_on_hold.",".
                             ARU::Const::patch_q_delete .")");

ARUDB::add_query(GET_BUGFIX_PATCH_TYPE =>
"select patch_type
from    aru_bugfixes
where   bugfix_id = :1");

ARUDB::add_query(GET_FIXED_BUGS =>
"select related_bug_number bug
 from   aru_bugfix_bug_relationships
 where  bugfix_id = :1
 and    relation_type in (" . ARU::Const::fixed_direct . ", " .
                              ARU::Const::fixed_indirect . ")"."
    minus
    select abbr.RELATED_BUG_NUMBER
    from   aru_bugfix_bug_relationships abbr
    where  bugfix_id = :1
    and    relation_type = ".ARU::Const::fixed_indirect_composite."
    order by 1 asc");

ARUDB::add_query(GET_LABEL_ID_FROM_NAME =>
"select label_id from aru_product_release_labels
   where label_name = :1 and platform_id = :2");
ARUDB::add_query(GET_DIRECT_INCLUDED_BUGS =>
"select related_bugfix_id, related_bug_number
 from   aru_bugfix_relationships
 where  bugfix_id = :1
 and    relation_type = " . ARU::Const::included_direct);

ARUDB::add_query(GET_INCLUDED_BUGS =>
"select related_bugfix_id, related_bug_number
 from   aru_bugfix_relationships
 where  bugfix_id = :1
 and    relation_type in (" . ARU::Const::included_direct . ", " .
                              ARU::Const::included_indirect . ")");

ARUDB::add_query(GET_FA_MPATCH_INCL_BUGS =>
"select related_bugfix_id, related_bug_number
 from   aru_bugfix_relationships abrs
 where  bugfix_id = :1
 and    relation_type in (" . ARU::Const::included_direct . ", " .
                              ARU::Const::included_indirect . ")
 and   related_bugfix_id not in
 (select abrs1.related_bugfix_id
  from aru_bugfix_relationships abrs1
  where abrs1.relation_type in (" . ARU::Const::included_direct . ", " .
                                    ARU::Const::included_indirect . ")
  and abrs1.bugfix_id <> abrs.related_bugfix_id
  and abrs1.bugfix_id in
  (select related_bugfix_id
  from aru_bugfix_relationships abrs2
  where abrs2.bugfix_id = abrs.bugfix_id
  and abrs2.relation_type in (" . ARU::Const::included_direct . ", " .
                                  ARU::Const::included_indirect . ")))");

ARUDB::add_query(GET_FA_MP_UPD_INCL_BUGS =>
"select abr.bugfix_id, abr.bug_number
from
(select abrp.related_bugfix_id related_bugfix_id,
 abrp.related_bug_number related_bug_number,
 max(abr.bugfix_request_id) bugfix_request_id
 from aru_bugfix_relationships abrp , aru_bugfix_requests abr
 where  abrp.bugfix_id = :2
  and abrp.related_bugfix_id = abr.bugfix_id
  and abr.language_id = :3
  and abr.platform_id = :4
  and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                          ARU::Const::patch_ftped_dev . "," .
                          ARU::Const::patch_ftped_internal.")
  and abrp.relation_type in (" . ARU::Const::included_direct . ", " .
                                 ARU::Const::included_indirect . ")
 group by abrp.related_bugfix_id, abrp.related_bug_number) ap1,
     aru_bugfix_requests abr, aru_bugfix_requests abr_mp
     where  ap1.bugfix_request_id = abr.bugfix_request_id
     and    abr_mp.bugfix_request_id = :1
     and    abr_mp.requested_date < abr.requested_date");

ARUDB::add_query(CHECK_FIXED_RELATIONSHIP =>
"select count(*)
 from   aru_bugfix_bug_relationships
 where  bugfix_id = :1
 and    related_bug_number = :2");

ARUDB::add_query(CHECK_IF_CHECKIN_EXIST =>
"select 1
 from   aru_bugfixes
 where  bugfix_name = :1
 and    (release_id <> :2 or product_id <> :3)");

ARUDB::add_query(GET_SNOWBALL_PATCH_TXNS =>
"select distinct a1.transaction_name, a1.trans_merge_time
from (
      select transaction_name, atr.attribute_value trans_merge_time
      from aru_transactions at1, aru_bugfixes ab,
      aru_transaction_attributes atr
      where ab.bugfix_rptno = :1
      and release_id = :2
      and at1.bugfix_id = ab.bugfix_id
      and atr.transaction_id = at1.transaction_id
      and atr.attribute_name = '".ARU::Const::trans_attrib_merge_time."'
      union
      select distinct transaction_name, atr.attribute_value
      from aru_transactions at1, aru_bugfix_relationships abrs,
           aru_bugfixes ab, aru_transaction_attributes atr
      where ab.bugfix_rptno = :1
      and release_id = :2
      and abrs.bugfix_id = ab.bugfix_id
      and abrs.relation_type in (" . ARU::Const::included_direct . ", " .
                            ARU::Const::included_indirect . ")
      and at1.bugfix_id = abrs.related_bugfix_id
      and atr.transaction_id = at1.transaction_id
      and atr.attribute_name = '".ARU::Const::trans_attrib_merge_time."') a1
order by a1.trans_merge_time desc");

ARUDB::add_query(GET_TXN_REQ_FILE_COUNT =>
"select count(distinct ao.object_id)
from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af
where abov.bugfix_id = :1
and (abov.source like 'D%' or abov.source like '%I%')
and ao.object_id = abov.object_id
and af.filetype_id = ao.filetype_id
and af.filetype_name not in
    (select  regexp_substr(:2,'[^,]+', 1, level)  from dual
     connect by regexp_substr(:2,'[^,]+', 1, level) is not null)");

ARUDB::add_query(GET_SNOWBALL_ACTIVE_CHECKINS =>
"select bug_number, status_id
 from   aru_bugfix_requests
 where  release_id  = :3
 and    platform_id = :4
 and    status_id not in (". ARU::Const::patch_ftped_internal .
        "," . ARU::Const::patch_ftped_support .
        "," . ARU::Const::patch_ftped_dev .
        "," . ARU::Const::ready_to_ftp_to_support .
        "," . ARU::Const::ready_to_ftp_to_dev .
        "," . ARU::Const::patch_denied .
        "," . ARU::Const::patch_denied_empty_payload .
        "," . ARU::Const::patch_denied_no_aru_patch .
        "," . ARU::Const::patch_skipped .
        "," . ARU::Const::patch_deleted .
        "," . ARU::Const::upload_requested .
        "," . ARU::Const::upload_queued .
        "," . ARU::Const::uploading_patch .
        "," . ARU::Const::upload_attempt .
        "," . ARU::Const::upload_failure .
        "," . ARU::Const::checkin_obsoleted .")
  and bug_number in
        (select to_number(regexp_replace(ata1.attribute_value,'(\\s+.*)',''))
         from   aru_transaction_attributes ata1
            ,   aru_transaction_attributes ata2
            ,   aru_transaction_attributes ata3
            ,   aru_transactions at
            ,   aru_bugfix_requests abr
         where    abr.release_id = :3
         and abr.status_id not in (". ARU::Const::patch_ftped_internal .
        "," . ARU::Const::patch_ftped_support .
        "," . ARU::Const::patch_ftped_dev .
        "," . ARU::Const::ready_to_ftp_to_support .
        "," . ARU::Const::ready_to_ftp_to_dev .
        "," . ARU::Const::patch_denied .
        "," . ARU::Const::patch_denied_empty_payload .
        "," . ARU::Const::patch_denied_no_aru_patch .
        "," . ARU::Const::patch_skipped .
        "," . ARU::Const::patch_deleted .
        "," . ARU::Const::upload_requested .
        "," . ARU::Const::upload_queued .
        "," . ARU::Const::uploading_patch .
        "," . ARU::Const::upload_attempt .
        "," . ARU::Const::upload_failure .
        "," . ARU::Const::checkin_obsoleted .")
         and    at.bugfix_request_id=abr.bugfix_request_id
         and    ata1.transaction_id=at.transaction_id
         and    ata1.attribute_name = '" .
                ARU::Const::trans_attrib_bug_num . "'
         and    ata2.transaction_id = ata1.transaction_id
         and    ata2.attribute_name = '" .
                ARU::Const::trans_attrib_label_branch . "'
         and    ata2.attribute_value = :1
         and    ata3.transaction_id = ata1.transaction_id
         and    ata3.attribute_name = '" .
                ARU::Const::trans_attrib_merge_time . "'
         and    ata3.attribute_value < :2
             )
order by bug_number");

    #
    # Statuses Considered
    # 5-Requested
    # 22-Fix FTPed to Support
    # 35-Denied
    # 45-On Hold
    # 55-Build Failure
    # 23-Fix FTPed to Development
    # 30-Test Patch Deleted
    # 205-Queued for Delete
    # 206-Deleted
    # 208-Attempting Delete
    # 830-Upload Requested
    # 835-Queued for Upload
    # 840-Uploading
    # 845-Attempting Upload
    # 850-Delete Requested
    # 847-Upload Failure
    # 80120-PBuild Request
    # 80130-Pre Processing
    # 80140-APF Postprocessing
    # 80150-APF Port Processing
    # 24-Fix FTPed to Internal
    # 80160-APF Merge Processing
    # 80170-Test Backport
    #
ARUDB::add_query("GET_ACTIVE_HP_ARU" =>
"select abr.bugfix_request_id
from aru_bugfixes ab, aru_bugfix_requests abr, aru_releases ar
where ab.bugfix_rptno = :1
and ab.release_id = ar.release_id
and aru_backport_util.pad_version(ar.release_name) like :2
and abr.bugfix_id = ab.bugfix_id
and abr.platform_id = :3
and abr.status_id in (5, 22, 23, 24, 30, 35, 45, 55, 205, 206, 208, 830, 835,
                      840, 845, 847, 850, 80120, 80130, 80140,
                      80150, 80160, 80170)");

ARUDB::add_query(GET_FUSION_TRANS_ATTRIBUTE =>
"select max(ata.attribute_value)
 from   aru_bugfix_requests abr
    ,   aru_transactions at
    ,   aru_transaction_attributes ata
 where  abr.bugfix_id = at.bugfix_id
 and    at.transaction_id = ata.transaction_id
 and    ata.attribute_name = :1
 and    abr.bugfix_request_id = :2");

ARUDB::add_query(GET_TRANSACTION_ATTRIBUTE =>
"select ata.attribute_value
 from   aru_transactions at
    ,   aru_transaction_attributes ata
 where  at.transaction_id = ata.transaction_id
 and    ata.attribute_name = :1
 and    at.transaction_name = :2");

ARUDB::add_query(GET_CHECKIN_STATUS =>
"select c.status_id, p.status_id, c.bugfix_id
 from   aru_bugfixes c, aru_bugfix_requests p
 where  c.bugfix_rptno = :1
 and    c.release_id = :2
 and    c.bugfix_id = p.bugfix_id
 and    p.platform_id in(".
 ARU::Const::platform_generic . "," .
 ARU::Const::platform_linux64_amd .
")".
 "and    p.language_id = (select language_id
                         from   aru_languages
                         where  language_code = :3)
 order by p.bugfix_request_id desc");

ARUDB::add_query(GET_BUGFIX_STATUS =>
"select status_id
from aru_bugfixes
where bugfix_rptno = :1
and status_id != " . ARU::Const::checkin_obsoleted . "
and release_id = :2");

ARUDB::add_query(GET_ALL_HOSTS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl
   where aprl.label_id in
         (select label_id from aru_product_release_labels)
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
Union
select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl, aru_release_label_groups arlg
   where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id in
        (select label_id from aru_product_release_labels)
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id");

ARUDB::add_query(CHECK_FUSION_PORTING =>
"select requires_porting from aru_extensions
 where SOURCE_EXTENSION = :1");

ARUDB::add_query(IS_BUGDB_ID_VALID =>
"select count(*) from bugdb_bug_user_mv
 where bug_username = upper(:1) and status = 'A'");

#
# If u want to know why check "mgr is not null" has been
# added, then check the query with 'apsrivas' guid.
#
ARUDB::add_query(GET_MGR_BUGDB_ID =>
"select bug_username from bugdb_bug_user_mv
   where full_email = (select manager_email from
   bugdb_bug_user_mv where upper(global_uid) = upper(:1)
   and manager_email is not null)
   and status = 'A'");

ARUDB::add_query(GET_RESPONSIBILITY_USER =>
"select user_name
  from aru_users au, aru_user_responsibilities aur,
  aru_responsibilities ar
  where au.user_id = aur.user_id
  and aur.responsibility_id = ar.responsibility_id
  and ar.responsibility_name = :1");

ARUDB::add_query(GET_RELEASED_ARUS_WITH_SQL =>
"  select abr.bugfix_request_id,
          abr.platform_id,
          abr.language_id
     from aru_bugfix_requests abr,
          aru_bugfix_requests abr1
    where abr1.bugfix_request_id = :1
      and abr.bug_number = abr1.bug_number
      and abr.release_id = abr1.release_id
      and abr.product_id = abr1.product_id
      and abr.language_id = abr1.language_id
      and abr.status_id = " . ARU::Const::patch_ftped_support . "
      and exists (
         select 'x'
           from aru_bugfix_request_history abrh,
                aru_users au
          where abrh.bugfix_request_id = abr.bugfix_request_id
            and abrh.status_id = " . ARU::Const::patch_ftped_internal . "
            and abrh.user_id = au.user_id
            and au.user_name like  'APF%')");

ARUDB::add_query(GET_ARU_TRANSACTION_ATTRIBUTE =>
"select ata.attribute_value
    from   aru_transactions at, aru_transaction_attributes ata
    where  ata.transaction_id = at.transaction_id
    and    at.bugfix_request_id = :1
    and    ata.attribute_name = :2");

ARUDB::add_query(GET_ALL_ARU_TXN_ATTRIBUTES =>
"select ata.attribute_name, ata.attribute_value
    from   aru_transactions at, aru_transaction_attributes ata
    where  ata.transaction_id = at.transaction_id
    and    at.bugfix_request_id = :1");

ARUDB::add_query(GET_BUGFIX_REQUIRES_PORTING_FLAG =>
"select requires_porting
   from aru_bugfixes ab
  where ab.bugfix_id = :1
    and ab.release_id = :2");

ARUDB::add_query(GET_BUG_INFO =>
"select portid, generic_or_port_specific,
        product_id, category, SUB_COMPONENT, utility_version,BASE_RPTNO
from bugdb_rpthead_v
where rptno = :1");

ARUDB::add_query(FETCH_RELEASE_ID =>
 "select apr.release_id
 from aru_product_releases apr
 where apr.product_id = :1");

ARUDB::add_query(GET_BUG_TRANSACTION_NAME =>
"select at.transaction_name
   from aru_transactions at, aru_bugfixes ab
  where at.bugfix_id = ab.bugfix_id
    and ab.bugfix_rptno = :1
    and ab.release_id = :2
  order by transaction_id desc");

ARUDB::add_query(GET_BACKPORT_TRANSACTION_NAME =>
"select transaction_name
   from aru_backport_transactions
  where backport_bug = :1");

ARUDB::add_query(GET_PARENT_LABEL_PRODUCT_ID =>
 "select product_id from aru_product_releases
    where product_release_id = (select product_release_id
      from aru_product_release_labels
      where label_id = (select parent_label_id from
      aru_release_label_groups where child_label_id =
            (select label_id
            from aru_product_release_labels
            where platform_id = :1 and
               product_release_id =
                (select product_release_id from
                 aru_product_releases
                 where release_id  = :2
                 and product_id = :3))))");

ARUDB::add_query(GET_LABEL_NAME_LIKE =>
"select label_name, label_id from aru_product_release_labels
   where (label_name like :1 or label_name like :2)
   and platform_id = :3");

ARUDB::add_query(SKIP_BRANCHED_FILE_CHECK =>
"select a_uses_b
   from aru_label_dependencies
  where a_uses_b = :1
    and b_used_by_a = :1
    and build_dependency = 'NO-BRANCH'
    and label_id = :2");

ARUDB::add_query(GET_MANDATORY_PATCH_NUMBER =>
"select bugfix_request_id
from aru_bugfix_requests
where status_id in (22,23,24)
and bugfix_id = :1
and (platform_id = 2000 or platform_id = :2)
and language_id = 0");

ARUDB::add_query(GET_ORAREVIEW_REQUESTS_TO_POLL =>
"select request_id, user_id from isd_requests
 where request_type_code  = 50001
 and status_code = " . ISD::Const::isd_request_stat_fail .
 " and creation_date > sysdate - 30 and
 regexp_like(error_message, 'Orareview is not completed', 'i')");

ARUDB::add_query(GET_EMAIL =>
"select bbu1.full_email, bbu2.cnt
 from bugdb_bug_user_mv bbu1,
      (select count(*) as cnt from bugdb_bug_user_mv where
         upper(global_uid) = upper(:1)) bbu2
 where upper(global_uid) = upper(:1) and status = 'A'");

ARUDB::add_query(GET_RECORDS_TO_FLIP_DIST_STATUS =>
   "select   ab.bugfix_rptno,ab.abstract ,ab.patch_type,
             adp.bugfix_request_id,min(adp.download_date),
    ab.release_id , ab.product_id
   from  aru_download_patches adp,
         aru_bugfix_requests abr,
         aru_bugfixes ab
   where adp.bugfix_request_id = abr.bugfix_request_id
     and adp.download_status = '" . ARU::Const::download_complete . "'
     and abr.status_id = '" . ARU::Const::patch_ftped_support . "'
     and ab.bugfix_id = abr.bugfix_id
     and ab.release_id like '". ARU::Const::applications_fusion_rel_exp . "%'
     and ab.classification_id = '" . ARU::Const::class_controlled . "'
     and ab.distribution_status = '" . ARU::Const::dist_support_temp . "'
     and ab.status_id = '" . ARU::Const::checkin_released . "'
         group by ab.bugfix_rptno,ab.abstract,ab.patch_type,
                  adp.bugfix_request_id,
                  ab.release_id,ab.product_id
         having (sysdate - min(adp.download_date)) >  :1
         order by min(adp.download_date) desc");

ARUDB::add_query(GET_RECORDS_TO_FLIP_1 =>
   "select ab.bugfix_rptno,ab.abstract ,ab.patch_type,
       abr.bugfix_request_id,
       ab.release_id , ab.product_id
  from aru_bugfix_requests abr,
       aru_bugfixes ab,
       (select release_id
          from aru_releases
         where to_char(release_id) like '" .
           ARU::Const::applications_fusion_rel_exp . "%') ar
       where ab.release_id = ar.release_id
       and ab.classification_id = " .  ARU::Const::class_controlled . "
       and ab.distribution_status = " . ARU::Const::dist_support_temp . "
       and ab.status_id = " . ARU::Const::checkin_released . "
       and abr.bugfix_id = ab.bugfix_id
       and abr.status_id = " . ARU::Const::patch_ftped_support  );

ARUDB::add_query(GET_RECORDS_TO_FLIP_2 =>
   "select
         adp.bugfix_request_id, min(adp.download_date) download_date
    from
      aru_download_patches adp
  where adp.bugfix_request_id = :1
    and adp.download_status = '" . ARU::Const::download_complete . "'
         group by adp.bugfix_request_id
         having min(adp.download_date) <= (sysdate -  :2)
         order by min(adp.download_date) desc" );

ARUDB::add_query(GET_BUGNUM_FROM_TXN =>
"select ab.bugfix_rptno
    from aru_transactions at, aru_bugfixes ab
   where at.transaction_name = :1
     and ab.bugfix_id = at.bugfix_id ");

ARUDB::add_query(GET_PREV_REL_DETAILS  =>
"select tracking_bug, release_version, release_id, status_id
    from aru_cum_patch_releases
    where release_id= :1");


ARUDB::add_query(GET_PREV_CP_PSU  =>
"select acpr2.tracking_bug, acpr2.release_version,
        acpr2.release_id, acpr2.status_id
 from aru_cum_patch_releases acpr, aru_cum_patch_releases acpr2,
      aru_bugfix_requests abr
 where acpr.release_version = :1
 and acpr.series_id = acpr2.series_id
 and aru_backport_util.get_numeric_version(acpr2.release_version) <
 aru_backport_util.get_numeric_version(acpr.release_version)
 and acpr2.tracking_bug is not null
 and acpr2.status_id not in (34528)
 and abr.bug_number = acpr2.tracking_bug
 and abr.release_id = :2
 and abr.platform_id = :3
 and abr.status_id in (" . ARU::Const::patch_ftped_support . "," .
                           ARU::Const::patch_ftped_dev . "," .
                           ARU::Const::patch_ftped_internal . ") " .
 "order by aru_backport_util.get_numeric_version(acpr2.release_version) desc");

ARUDB::add_query(GET_DESC_PREV_CP_PSU  =>
"select acpr2.tracking_bug, acpr2.release_version,
        acpr2.release_id, acpr2.status_id
 from aru_cum_patch_releases acpr, aru_cum_patch_releases acpr2
 where acpr.release_version = :1
 and acpr.series_id = acpr2.series_id
 and aru_backport_util.get_numeric_version(acpr2.release_version) <=
 aru_backport_util.get_numeric_version(acpr.release_version)
 and acpr2.tracking_bug is not null
 and acpr2.status_id not in (34528)
 order by 1 desc");


ARUDB::add_query(GET_MAX_Q_QUEUE_TYPE =>
"select acq.unique_id, acq.ci_txn, acq.priority, acq.queue_status,
    acq.ci_status
    from apf_cd_patch_details a1,
    automation_request_queues acq
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.pse_id = acq.unique_id
    and   acq.queue_status like :2
    order by acq.priority desc");


ARUDB::add_query(GET_REST_QUEUE =>
"select acq.unique_id, acq.ci_txn, acq.priority, acq.queue_status,
    acq.ci_status
    from apf_cd_patch_details a1,
    automation_request_queues acq
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.pse_id = acq.unique_id
    and   acq.priority > :2
    order by acq.priority asc");

ARUDB::add_query(GET_PSE_CD_CI_Q =>
"select unique_id, priority
    from automation_request_queues
    where ci_txn = :1
    and queue_status in ('WAITQ', 'WAITQRELEASEGAP','WAITQRETRY')");

ARUDB::add_query(GET_CI_PSE_Q =>
"select ci_txn, priority
    from automation_request_queues
    where unique_id = :1
    and queue_status like :2");

ARUDB::add_query(GET_CD_WAITQ =>
"select acq.unique_id, acq.ci_txn, acq.priority, acq.queue_status, acq.ci_status
    from apf_cd_patch_details a1,
    automation_request_queues acq
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.pse_id = acq.unique_id
    and   acq.queue_status in ('WAITQ', 'WAITQRELEASEGAP','WAITQRETRY')
    order by acq.priority desc");

ARUDB::add_query(GET_CD_P1_WAITQ =>
"select acq.unique_id, acq.ci_txn, acq.priority, acq.queue_status
    from apf_cd_patch_details a1,
    automation_request_queues acq
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.pse_id = acq.unique_id
    and   acq.queue_status in ('WAITQ', 'WAITQRELEASEGAP','WAITQRETRY')
    and   acq.ci_status = 1
    order by acq.priority desc");


ARUDB::add_query(GET_CD_PRIRORITY1_REQ =>
"select acq.unique_id, acq.ci_txn, a2.att_value, acq.priority
    from apf_cd_patch_details a1,apf_cd_patch_details a2,
    automation_request_queues acq
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.pse_id = acq.unique_id
    and   acq.queue_status in ('WAITQ', 'WAITQRELEASEGAP','WAITQRETRY')
    and   a2.pse_id  = acq.unique_id
    and   a2.att_name = 'BP_REQUEST_ID'
    order by acq.priority asc");

 ARUDB::add_query(GET_QA_PASSED_TXN =>
    "select distinct a5.pse_id,a1.att_value ,a4.att_value
    from  apf_cd_patch_details a2,
    apf_cd_patch_details a3,apf_cd_patch_details a1,
    apf_cd_patch_details a4,apf_cd_patch_details a5
    where a5.att_name = 'CPM_RELEASE_VERSION'
    and   a5.att_value =  :1
    and   a2.pse_id = a5.pse_id
    and   a2.att_name = 'PATCH_STAGE'
    and   a2.att_value = 'INPROGRESS'
    and   a3.pse_id    = a2.pse_id
    and   a3.att_name  = 'REQUEST_STATUS'
    and   a3.att_value in ('QA_TEST')
    and   a1.pse_id    = a2.pse_id
    and a1.att_name = 'CI_TXN'
    and a4.pse_id    = a2.pse_id
    and a4.att_name = 'STATUS_LOG'
    and a4.pse_id    = a2.pse_id
    union
    select distinct a1.pse_id, a2.att_value, a3.att_value
    from
    apf_cd_patch_details a1,apf_cd_patch_details a2, apf_cd_patch_details a3,
    apf_cd_patch_details a5
    where a5.att_name = 'CPM_RELEASE_VERSION'
    and   a5.att_value =  :1
    and   a1.pse_id = a5.pse_id
    and   a1.att_name = 'RACE_STATUS'
    and   a1.att_value =  'OPTIMIZATIONDONE'
    and a2.pse_id = a5.pse_id
    and a2.att_name = 'CI_TXN'
    and a3.pse_id    = a5.pse_id
    and a3.att_name = 'STATUS_LOG'
    order by 1 desc");

ARUDB::add_query(GET_CD_FINISHED_REQ =>
"select a2.pse_id, a2.att_value
    from apf_cd_patch_details a1,apf_cd_patch_details a2
    where a1.att_name = 'PATCH_STAGE'
    and   a1.att_value = 'FINISHED'
    and   a1.last_updated_date > (sysdate - 4)
    and   a1.pse_id  = a2.pse_id
    and   a2.att_name = 'LABEL'");

ARUDB::add_query(CHECK_CD_FINISHED_REQ =>
"select a2.pse_id, a2.att_value
    from apf_cd_patch_details a1,apf_cd_patch_details a2
    where a1.att_name = 'PATCH_STAGE'
    and   a1.att_value = 'FINISHED'
    and   a1.last_updated_date > (sysdate - 4)
    and   a1.pse_id  = a2.pse_id
    and   a2.att_name = 'LABEL'
    and   a2.att_value = :1");


ARUDB::add_query(GET_CD_RACE_CONDITION =>
"select a2.pse_id
    from apf_cd_patch_details a1, apf_cd_patch_details a2,
    apf_cd_patch_details a3
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.last_updated_date > (sysdate - 5)
    and   a1.pse_id = a2.pse_id
    and   a2.att_name = 'PATCH_STAGE'
    and   a2.att_value = 'INPROGRESS'
    and   a3.pse_id    = a1.pse_id
    and   a3.att_name  = 'REQUEST_STATUS'
    and   a3.att_value = 'PACKAGE'");

ARUDB::add_query(GET_CD_OPT_RACE_CONDITION =>
"select a2.pse_id
    from apf_cd_patch_details a1, apf_cd_patch_details a2,
    apf_cd_patch_details a3
    where a1.att_name = 'CPM_RELEASE_VERSION'
    and   a1.att_value =  :1
    and   a1.last_updated_date > (sysdate - 5)
    and   a1.pse_id = a2.pse_id
    and   a2.att_name = 'PATCH_STAGE'
    and   a2.att_value = 'INPROGRESS'
    and   a3.pse_id    = a1.pse_id
    and   a3.att_name  = 'REQUEST_STATUS'
    and   a3.att_value in ('INSTALL_TEST','QA_TEST')");

ARUDB::add_query(GET_CD_PATCH_DETAILS =>
"select att_name, att_value, cd_status, creation_date,
    LAST_UPDATED_DATE, COMMENTS
    from apf_cd_patch_details
    where pse_id = :1
    and att_name = :2");

ARUDB::add_query("IS_STREAM_RELEASE" =>
"select count(distinct acpr.aru_release_id)
from aru_releases ar1, aru_releases ar2, aru_cum_patch_releases acpr
where acpr.release_id = :1
and ar1.release_id = acpr.aru_release_id
and ar2.release_id = ar1.base_release_id
and ar2.release_name  =
    regexp_replace(acpr.release_version,'[a-zA-Z]+(.*)','')");

ARUDB::add_query(GET_CPCT_RELEASE_LABEL =>
"select acprl.platform_release_label
   from aru_cum_plat_rel_labels acprl
  where acprl.release_id = :1
    and platform_id = :2");

ARUDB::add_query(GET_CPCT_RELEASE_INFO =>
"select acpr.release_id,acpr.release_name,acpr.aru_release_id,
        acpr.release_version
    from aru_cum_patch_releases acpr
    where acpr.tracking_bug = :1");

ARUDB::add_query(GET_CPCT_CP_INFO =>
"select distinct acpr.release_id,acpr.tracking_bug,acprl.platform_release_label
    from aru_cum_patch_releases acpr
    ,    aru_cum_plat_rel_labels acprl
    where aru_backport_util.pad_version(acpr.release_version)
          = aru_backport_util.pad_version(:3)
    and acpr.aru_release_id = :1
    and acpr.release_id = acprl.release_id
    and acprl.platform_id = :2");


ARUDB::add_query(GET_CPM_CI_BACKPORT =>
"select distinct backport_bug, series_id
 from aru_cum_codeline_requests accr
 where backporT_bug is not null
 and series_id in (select series_id from aru_cum_patch_series
 where upper(series_name) like :3
 and base_release_id = :2)
 and base_bug = :1
 order by series_id desc");

ARUDB::add_query(GET_CPCT_FIXED_BUGS_MASKED =>
"select accr.base_bug
 from   aru_cum_codeline_requests accr
 ,      bugdb_rpthead_v br
 where  accr.base_bug = br.rptno
 and    accr.status_id in (:2, :3, :4, :5,:6)
 and    accr.release_id = :1
 and    accr.is_masked != 'Y'");

 ARUDB::add_query(GET_CPCT_FIXED_BUGS =>
"select accr.base_bug
 from   aru_cum_codeline_requests accr
 ,      bugdb_rpthead_v br
 where  accr.base_bug = br.rptno
 and    accr.status_id in (:2, :3, :4, :5,:6)
 and    accr.release_id = :1");
#
# Bug 21089139 - Removed "Approved, in process" status.
# 34583 - Released
# 34588 - Approved, Code Merged
# 34597 - Patch Available for QA
# 34610 - Submitted to Integration Series
#
ARUDB::add_query(GET_CPCT_CURRENT_FIXED_BUGS =>
"select accr.base_bug
 from   aru_cum_codeline_requests accr
 ,      bugdb_rpthead_v br
 where  accr.base_bug = br.rptno
 and    accr.status_id in (34583, 34588, 34597, 34610,96302,96371)
 and    accr.release_id = :1");


ARUDB::add_query(GET_CPCT_FIXED_DROP_BUGS =>
" select  distinct accr.base_bug
    from    aru_cum_codeline_requests accr, aru_cum_codeline_req_attrs accra
    where   accr.release_id           =  :1
    and     accr.status_id            in (34581, 34583, 34588, 34597, 34610,96302,96371)
    and     accr.codeline_request_id  = accra.codeline_request_id
    and     accra.attribute_name      = 'Drop Num'
    and     accra.attribute_value    <= NVL(:2, 0)");

ARUDB::add_query(GET_CPM_ALL_FIXED_BUGS =>
"select distinct basebug, relname, relid, upd_date
 from (select accr.base_bug basebug,
       nvl(acpr1.release_name, acprp.parameter_name) relname,
       nvl(acpr1.release_id, acprp.release_id) relid,
       accr.last_updated_date upd_date
 from   aru_cum_codeline_requests accr,
        aru_cum_patch_releases acpr1, aru_cum_patch_releases acpr,
        aru_cum_patch_release_params acprp
 where  (acpr.tracking_bug = :1 or
         (acprp.parameter_type = 34593 and
          to_number(acprp.parameter_value) = :1 and
          acprp.release_id = acpr.release_id))
 and    acpr.series_id = accr.series_id
 and    accr.status_id in (34583, 34586, 34597, 34588,96302,96371)
 and    acpr1.release_id = accr.release_id
 and    acpr1.tracking_bug is not null
order by acpr.release_id, acpr.release_name, accr.last_updated_date asc)");

ARUDB::add_query(GET_CPM_MERGED_FIXED_BUGS =>
"select distinct basebug, relname, relid, min(upd_date)
 from (select accrs.base_bug basebug,
       nvl(acpr1.release_name, acprp.parameter_name) relname,
       nvl(acpr1.release_id, acprp.release_id) relid,
       accr.last_updated_date upd_date
 from   aru_cum_codeline_requests accrs, aru_cum_codeline_req_hist accr,
        aru_cum_patch_releases acpr1, aru_cum_patch_releases acpr,
        aru_cum_codeline_req_attrs acra, aru_cum_patch_release_params acprp
 where  (acpr.tracking_bug = :1 or
         (acprp.parameter_type = 34593 and
          to_number(acprp.parameter_value) = :1 and
          acprp.release_id = acpr.release_id))
 and    acpr.series_id = accrs.series_id
 and    accrs.status_id in (34583, 34586, 34597, 34588,96302,96371)
 and    accr.status_id in (34583, 34586, 34597, 34588,96302,96371)
 and    accr.codeline_request_id = accrs.codeline_request_id
 and    acra.codeline_request_id = accr.codeline_request_id
 and    ((acra.attribute_name = 'ADE Merged Timestamp' and
          acra.attribute_value is not null and
          to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS') <
               to_date(:2, 'YYYY-MM-DD HH24:MI:SS')) or
         (acra.attribute_name = 'ADE Merged Timestamp' and
          acra.attribute_value is null and
          accr.last_updated_date < to_date(:2, 'YYYY-MM-DD HH24:MI:SS')) or
         (not exists (select 1 from aru_cum_codeline_req_attrs acra1
                      where acra1.codeline_request_id =
                                      accr.codeline_request_id
                      and acra1.attribute_name = 'ADE Merged Timestamp') and
          accr.last_updated_date < to_date(:2, 'YYYY-MM-DD HH24:MI:SS')))
 and    acpr1.release_id = accrs.release_id
 and    acpr1.tracking_bug is not null
union
    select accrs.base_bug basebug,
       nvl(acpr1.release_name, acprp.parameter_name) relname,
       nvl(acpr1.release_id, acprp.release_id) relid,
       accrs.last_updated_date upd_date
 from  aru_cum_codeline_requests accrs, aru_cum_patch_releases acpr1,
       aru_cum_patch_releases acpr, aru_cum_patch_release_params acprp
 where (acpr.tracking_bug = :1 or
         (acprp.parameter_type = 34593 and
          to_number(acprp.parameter_value) = :1 and
          acprp.release_id = acpr.release_id))
 and    acpr.series_id = accrs.series_id
 and    accrs.status_id in (34583, 34586, 34597, 34588,96302,96371)
 and    not exists (select 1 from aru_cum_codeline_req_hist accr
                    where accr.codeline_request_id =
                                  accrs.codeline_request_id)
 and    acpr1.release_id = accrs.release_id
 and    acpr1.tracking_bug is not null)
 group by basebug, relname, relid
 order by 2,3,4 asc");

ARUDB::add_query(GET_CPM_CODELINE_ID =>
"select codeline_request_id
    from aru_cum_codeline_requests
    where backport_bug = :1
    and   rownum = 1");
ARUDB::add_query(GET_CPM_DELTA_CI_BUGS =>
"select accr.backport_bug,accr.base_bug,
    to_char
   (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI'),
    from aru_cum_codeline_requests accr, aru_cum_codeline_req_attrs acra
    where acra.attribute_name = 'ADE Merged Timestamp'
    and acra.codeline_request_id = accr.codeline_request_id
    and accr.release_id = :1
    and accr.status_id in (34588, 34597, 34610,96302)
    and acra.attribute_value is not null
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    <=:2
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    >=:3");
#
# Query to get fixed bugs from CPM filtering out the bugs which are masked. See
# bug 32113436 for more details
#
ARUDB::add_query(GET_CPM_CURRENT_FIXED_BUGS_MASKED =>
"select accr.base_bug,
    to_char
   (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI'),
    accr.backport_bug
    from aru_cum_codeline_requests accr, aru_cum_codeline_req_attrs acra
    where acra.attribute_name = 'ADE Merged Timestamp'
    and acra.codeline_request_id = accr.codeline_request_id
    and accr.release_id = :1
    and accr.status_id in (34588, 34597, 34610,96302)
    and acra.attribute_value is not null
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    <=:2 and
    accr.is_masked != 'Y'
union
select accr.base_bug, to_char (accr.requested_date,'YYMMDD.HH24MI'),accr.backport_bug
    from aru_cum_codeline_requests accr, bugdb_rpthead_v br
    where accr.release_id = :1
    and accr.status_id in (34583, 34610,96371)
    and accr.base_bug = br.rptno
    and accr.is_masked != 'Y' ");
#
# Query to get all fixed bugs from CPM 
#
ARUDB::add_query(GET_CPM_CURRENT_FIXED_BUGS =>
"select accr.base_bug,
    to_char
   (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI'),
    accr.backport_bug
    from aru_cum_codeline_requests accr, aru_cum_codeline_req_attrs acra
    where acra.attribute_name = 'ADE Merged Timestamp'
    and acra.codeline_request_id = accr.codeline_request_id
    and accr.release_id = :1
    and accr.status_id in (34588, 34597, 34610,96302)
    and acra.attribute_value is not null
    and to_char
    (to_date(acra.attribute_value,'DD-MON-YYYY HH24:MI:SS'),'YYMMDD.HH24MI')
    <=:2 
union
select accr.base_bug, to_char (accr.requested_date,'YYMMDD.HH24MI'),accr.backport_bug
    from aru_cum_codeline_requests accr, bugdb_rpthead_v br
    where accr.release_id = :1
    and accr.status_id in (34583, 34610,96371)
    and accr.base_bug = br.rptno ");
    
ARUDB::add_query(GET_OBJECT_PERMISSIONS =>
"select aop.oui_name,aop.permission,aop.build_location,
        aop.parent_object_id,aop.comments
    from APF_OBJECT_PERMISSIONS aop, aru_objects ao,
    aru_product_release_labels aprl
    where ao.object_name = :2
    and ao.object_location = :1
    and ao.object_id  = aop.object_id
    and ao.product_release_id = aprl.product_release_id
    and aprl.label_id  = :3
    and aprl.label_id = aop.label_id");

ARUDB::add_query(GET_CPCT_TRACKING_BUG =>
"select accr.release_id,accr.tracking_bug
    from ARU_CUM_PATCH_RELEASES accr
    where accr.release_version = :1");

ARUDB::add_query(GET_CPCT_REL_ID_BY_REL_VERSION =>
"select accr.release_id
    from ARU_CUM_PATCH_RELEASES accr
    where accr.release_version = :1");

ARUDB::add_query(GET_FROM_NUMERIC_VERSION =>
"select release_version
    from aru_cum_patch_releases
    where aru_backport_util.get_numeric_version(release_version) = :1
    and   release_version like :2");


ARUDB::add_query(GET_LABEL_RELEASE_INFO =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from aru_product_releases apr
 , aru_releases ar
 , aru_products ap
 , aru_product_groups apg
 where ap.product_id = :1
 and apr.release_id = ar.release_id
 and ((apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
      or (apr.product_id = ap.product_id))
 and aru_backport_util.pad_version(:2) =
    aru_backport_util.pad_version(ar.release_name)
 and apr.product_release_id in (select product_release_id
                                from aru_product_release_labels)");

ARUDB::add_query(GET_CPCT_LABEL_RELEASE_INFO =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from aru_product_releases apr
 , aru_releases ar
 , aru_cum_patch_releases acpr
 , aru_products ap
 , aru_product_groups apg
 where ap.product_id = :1
 and apr.release_id = ar.release_id
 and ((apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
      or (apr.product_id = ap.product_id))
 and aru_backport_util.pad_version(:2) =
    aru_backport_util.pad_version(acpr.release_version)
 and ar.release_id = acpr.aru_release_id
 and apr.product_release_id in (select product_release_id
                                from aru_product_release_labels)");

ARUDB::add_query(GET_PROD_COMPONENTS =>
"select ap.bugdb_component,ap.bugdb_subcomponent
    from aru_products ap
   where ap.product_id = :1 ");

ARUDB::add_query(GET_DESC_PRODUCT_ID =>
" select distinct ap.bugdb_product_id
  from aru_product_release_labels aprl,
       aru_product_releases apr,
       aru_products ap
  where label_name like :1
   and  apr.product_release_id = aprl.product_release_id
   and ap.product_id = apr.product_id");

ARUDB::add_query(GET_PSU_ARU_FOR_PSE_ARU =>
" select distinct abr.bugfix_request_id, ab.product_id,
    ab.release_id, abr.platform_id
    from  aru_bugfix_requests abr, aru_bugfixes ab
    where abr.bugfix_request_id = (select max(abr.bugfix_request_id)
                                      from aru_bugfix_requests abr, aru_bugfixes ab ,
                                      aru_bugfix_attributes aba
                                      where abr.bugfix_id = ab.bugfix_id
                                      and ab.bugfix_id = aba.bugfix_id
                                      and aba.attribute_type = "
                                                     . ARU::Const::psu_introducing_release . "
                                      and (aba.attribute_value,abr.platform_id) =
                                      (select abr.release_id,abr.platform_id
                                       from aru_bugfix_requests abr
                                       where abr.bugfix_request_id = :1))
    and ab.bugfix_id = abr.bugfix_id");

ARUDB::add_query(CHECK_TESTRESULTS =>
"select a.job_id
 from   apf_testresults a
 ,      apf_testruns b
 where  a.testrun_id = b.testrun_id
 and    b.platform_id = :2
 and    isd_request_id = (
        select max(isd_request_id)
        from   apf_testruns
        where  pse_number = :1
        and    platform_id = :2
        and    status_id = :3)");

ARUDB::add_query(GET_BASE_BUG_ASSIGNEE =>
"select rh1.programmer from bugdb_rpthead_v rh, bugdb_rpthead_v rh1
   where rh.base_rptno = rh1.rptno and rh.rptno = :1");


ARUDB::add_query(GET_MANUAL_FLOW_FLAG =>
"select count(*) from aru_backport_requests where
   backport_bug = :1 and manual_flow_flag = 'Y'");

ARUDB::add_query(GET_ALLOUI_COMPONENTS =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
 from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
 where ald.b_used_by_a     = :1
 and ald.label_dependency in ('OUI','SAOUI','SA')
 and ald.a_uses_b = ao1.object_id
 and af1.filetype_id = ao1.filetype_id
 and ald.build_dependency <> 'NO-SHIP'
 and af1.filetype_name = '" . ARU::Const::filetype_name_st_oui . "'" .
 " and ald.label_id = :2
 UNION
 select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
 from aru_label_dependencies ald, aru_filetypes af1, aru_objects ao1
 where ald.b_used_by_a     = :1
 and ald.label_dependency in ('OUI','SAOUI','SA')
  and ald.a_uses_b = ao1.object_id
 and af1.filetype_id = ao1.filetype_id
 and ald.build_dependency <> 'NO-SHIP'
 and af1.filetype_name = '" . ARU::Const::filetype_name_st_oui . "'" .
 " and ald.label_id = :3");

ARUDB::add_query(GET_UTILITY_VERSION =>
"select b.utility_version
 from bugdb_rpthead_v b
 where b.rptno = :1");


ARUDB::add_query(GET_RELEASE_INFO_CPCT =>
" select distinct acpr.release_version
 , ar.release_id
 , ar.release_long_name
 from aru_releases ar
 , aru_cum_patch_releases acpr
 where acpr.release_id = :1
   and ar.release_id = acpr.aru_release_id");

ARUDB::add_query(GET_CPCT_BASE_RELEASE_ID =>
"select distinct acps.base_release_id
from   aru_cum_patch_releases acpr, aru_cum_patch_series acps
where  acpr.aru_release_id = :1
and    acps.series_id = acpr.series_id");

ARUDB::add_query(GET_REQ_STATUS =>
"select status_code from isd_requests where request_id=:1");

ARUDB::add_query(GET_GRID_ID =>
"select GRID_ID from isd_requests where request_id=:1");

ARUDB::add_query(GET_TRANSACTION_BUG_INFO =>
"
  select distinct nvl(at.transaction_name,'NOT_FOUND'),
         ab.bugfix_id, ab.release_id,
         nvl(rpt.status,11), lower(au.user_name)
    from aru_transactions at,
         bugdb_rpthead_v rpt,
         aru_bugfixes ab,
         aru_users au
   where ab.bugfix_rptno = :1
     and at.bugfix_id (+)= ab.bugfix_id
     and rpt.rptno (+) = ab.bugfix_rptno
     and au.user_id = ab.created_by
");

ARUDB::add_query(
     GET_RELEASE_TESTS =>
        "select testflow_id, testflow_name,testflow_sequence,
                testsuite_id,testsuite_name,test_sequence,
                testtype,host_id,command,ignore_failures,on_error,
                maximum_retries,retry_pattern_id,error_pattern_id,
                ignore_pattern_id, release_id, release_name, platform_id
           from apf_release_tests_v
          where release_id = :1
            and platform_id = :2
          order  by testflow_sequence,testflow_id,
                    test_sequence,testsuite_id");

ARUDB::add_query(
     GET_LABEL_TESTS =>
        "select testflow_id, testflow_name,testflow_sequence,
                properties, testsuite_id,testsuite_name,test_sequence,
                testtype,host_id,command,ignore_failures,on_error,
                maximum_retries,retry_pattern_id,error_pattern_id,
                ignore_pattern_id, null, null, null
           from apf_tests_v
          where label_id = :1
          order  by testflow_sequence,testflow_id,
                    test_sequence,testsuite_id");

ARUDB::add_query(
     GET_PATCH_TYPE_TESTS =>
"select atf.testflow_id, atf.testflow_name,altf.testflow_sequence,
        atf.properties, ats.testsuite_id,ats.testsuite_name,atg.test_sequence,
        ats.testtype,ats.host_id,ats.command,atg.ignore_failures,atg.on_error,
        atg.maximum_retries,atg.retry_pattern_id,atg.error_pattern_id,
        atg.ignore_pattern_id, null, null, null
  from apf_testflows atf,
       apf_testflow_groups atg,
       apf_testsuites ats,
       aru.apf_label_testflows altf,
       aru_releases ar
  where upper(altf.flow_type) = upper(:1)
    and altf.RELEASE_ID = ar.RELEASE_ID (+)
    and atf.TESTFLOW_ID = altf.TESTFLOW_ID
    and NVL(atf.ENABLED,'Y') = 'Y'
    and atg.TESTFLOW_ID = atf.TESTFLOW_ID
    and ats.TESTSUITE_ID = atg.TESTSUITE_ID
    and NVL(ats.ENABLED,'Y') = 'Y'
  order by
      altf.testflow_sequence,atg.testflow_id,
      atg.test_sequence,atg.testsuite_id");

ARUDB::add_query(
     GET_DEFAULT_TEST_PROPERTY =>
        "select command
           from apf_testsuites
          where testsuite_name = :1
            and testtype = :2");

ARUDB::add_query(
     GET_TESTFLOW_DETAILS =>
        "select testsuite_id, testflow_id, ignore_failures,
                on_error, maximum_retries, retry_pattern_id,
                error_pattern_id, ignore_pattern_id
            from apf_testflow_groups
           where testflow_id = :1
             and testsuite_id = :2");

ARUDB::add_query(
     GET_LAST_RUN_TESTDETAILS =>
      "select testresult_id, job_id, job_type, status_id,
              testflow_id, testrun_id, testsuite_id,
              test_sequence
         from apf_testresults
        where testresult_id = (
           select max(testresult_id)
              from apf_testresults
             where testrun_id = :1)");

ARUDB::add_query(
     GET_ALT_TESTS =>
        "select atfl.testflow_id, atfl.testflow_name,1 testflow_sequence,
                atfl.properties,atflg.testsuite_id,ats.testsuite_name,
                atflg.test_sequence, ats.testtype,ats.host_id,ats.command,
                atflg.ignore_failures, atflg.on_error, atflg.maximum_retries,
                atflg.retry_pattern_id, atflg.error_pattern_id,
                atflg.ignore_pattern_id
           from apf_testflows atfl, apf_testsuites ats,
                apf_testflow_groups atflg
          where atfl.testflow_id = :1
            and atflg.testflow_id = atfl.testflow_id
            and ats.testsuite_id = atflg.testsuite_id
            and nvl(ats.enabled,'Y') = 'Y'
          order  by testflow_id,testflow_sequence,
                    test_sequence,testsuite_id");

ARUDB::add_query(
     GET_BUGFIX_REQ_STATUS =>
"select status_id
   from aru_bugfix_requests
  where bugfix_request_id = :1");

ARUDB::add_query (
  GET_TEST_PATTERN =>
"select atp.pattern
  from apf_testflow_groups atg, apf_test_patterns atp
 where atg.testflow_id = :1
   and atg.testsuite_id = :2
   and atg.test_sequence = :3
   and decode(upper(:4),
              'ERROR',error_pattern_id,
              'RETRY', retry_pattern_id,
              'IGNORE',ignore_pattern_id,-1) = atp.pattern_id");

ARUDB::add_query (
  GET_PREV_FA_PATCH_JOB =>
"select tre.job_id job_id, to_char(tre.start_time,'YYMMDD') stime,
       tre.status_id
  from apf_testresults tre,
       apf_testresults tre1,
       apf_testruns tru,
       apf_testruns tru1
  where tre1.job_id = :1
    and tru1.testrun_id = tre1.testrun_id
    and tre.testflow_id = tre1.testflow_id
    and tre.testsuite_id = tre1.testsuite_id
    and tre.test_sequence = tre1.test_sequence
    and tre.start_time < tre1.start_time
    and tru.release_id = tru1.release_id
    and tru.platform_id = tru1.platform_id
    and tru.testrun_id = tre.testrun_id
  order by tre.start_time desc");

ARUDB::add_query (
  GET_PREV_FA_PATCH_DETAILS =>
"select distinct apr.bugfix_request_id, apr.bug_number,
        apr.transaction_name, apr.developer_name,
        apr.developer_email, apr.manager_email,
        decode(apr.apply_success_flag,
               'Y','Success', 'S','Skipped',
               'N', 'Failed', 'Pending') apply_status,
        apr.patch_run_id
   from apf_patch_runs apr,
        aru_bugfix_requests abr
  where abr.release_id = :1
    and apr.bugfix_request_id = abr.bugfix_request_id
    and apr.request_time < :2
  order by apr.patch_run_id desc");

ARUDB::add_query (

  FA_INSTALLTEST_DETAILS =>
"select abr.release_id, ar.release_long_name,
        ap.product_id, ap.product_name, ap.product_abbreviation,
        apr.bug_number, apr.transaction_name, apr.developer_name,
        apr.abort_logfile,
        decode(apr.abort_success_flag,
               'Y','Success', 'S','Skipped',
               'N', 'Failed', 'Pending') abort_status,
        apr.validate_logfile,
        decode(apr.validate_success_flag,
               'Y','Success', 'S','Skipped',
               'N', 'Failed', 'Pending') validate_status,
        apr.apply_logfile,
        decode(apr.apply_success_flag,
               'Y','Success', 'S','Skipped',
               'N', 'Failed', 'Pending') apply_status,
        new_flag, abr.bugfix_id, nvl(rpt.status,11),
        apr.bugfix_request_id, abr.status_id
  from apf_patch_runs apr, aru_products ap,
       aru_bugfix_requests abr, bugdb_rpthead_v rpt,
       aru_releases ar
 where apr.testresult_id = :1
   and abr.bugfix_request_id = apr.bugfix_request_id
   and ap.product_id = abr.product_id
   and ar.release_id = abr.release_id
   and rpt.rptno (+)  = apr.bug_number
 order by ap.product_id, abr.last_updated_date,
          apr.bug_number");

ARUDB::add_query(

  GET_FA_QA_CONTACT_INFO =>
"select au.user_name, au.email_address
   from aru_users au, aru_responsibilities ar,
        aru_user_responsibilities aur
  where lower(ar.responsibility_name) = lower(:1)
    and aur.RESPONSIBILITY_ID = ar.RESPONSIBILITY_ID
    and au.user_id = aur.user_id");

ARUDB::add_query(GET_BASE_CUM_RELEASE =>
"select distinct ar.base_release_id
   from aru_releases ar, aru_cum_patch_releases acpr
   where ar.release_id = acpr.aru_release_id
   and ar.release_id = :1");

ARUDB::add_query(IS_BASE_REL_TEMPL =>
"select count(distinct ev.env_id)
from aru_releases ar, aru_product_releases apr,
    aru_product_release_labels aprl, ems_envs ev
where ev.env_name = :1
and aprl.template_env_id = ev.env_id
and apr.product_release_id = aprl.product_release_id
and ar.release_id = apr.release_id
and ar.base_release_id = ar.release_id");

ARUDB::add_query(GET_RELEASE_INFO_CI =>
"select acpr.release_version, acpr.aru_release_id, acpr.release_name
   from aru_cum_patch_releases acpr, bugdb_rpthead_v rh
   where rh.rptno = :1 and
   aru_backport_util.pad_version(rh.utility_version) =
   aru_backport_util.pad_version(acpr.release_version)");

ARUDB::add_query(GET_CI_REQUEST_ID =>
"select codeline_request_id from aru_cum_codeline_requests
    where backport_bug = :1");

ARUDB::add_query(GET_CI_REQUEST_ID_FROM_BUG =>
"select codeline_request_id from aru_cum_codeline_requests
    where base_bug = :1");

ARUDB::add_query(GET_EXCEPTION_SKIP_FILES =>
"select extractvalue(apbr.xcontent,'/rules/name')
    from apf_patch_build_rules apbr
    where extractvalue(apbr.xcontent,'/rules/rule/action') = 'ignore'
    and apbr.product_id = :1
    and apbr.patch_type in (:2,'ALL')
    and apbr.status = 'Y'
    and extractvalue(apbr.xcontent,'/rules/platform') in (:3,'ALL')
    and existsNode(apbr.xcontent,
        '/rules/release[text() = \"ALL\" or text() = \"' || :4 || '\" ]') = 1
    and extractvalue(apbr.xcontent,'/rules/type')  in (:5,'none')
    and extractvalue(apbr.xcontent,'/rules/bug')  in (:6,'ALL')");

ARUDB::add_query(GET_EXCEPTION_RULE_FILES =>
"select extractvalue(apbr.xcontent,:9),
    extractvalue(apbr.xcontent,:10),
    extractvalue(apbr.xcontent,'/rules/priority')
    from apf_patch_build_rules apbr
    where extractvalue(apbr.xcontent,'/rules/rule/action') = :6
    and extractvalue(apbr.xcontent,'/rules/name') like :1
    and apbr.product_id = :2
    and apbr.patch_type in (:3,'ALL')
    and apbr.status = 'Y'
    and extractvalue(apbr.xcontent,'/rules/platform') in (:4,'ALL')
    and existsNode(apbr.xcontent,
        '/rules/release[text() = \"ALL\" or text() = \"' || :5 || '\" ]') = 1
    and extractvalue(apbr.xcontent,'/rules/type')  in (:7,'none')
    and extractvalue(apbr.xcontent,'/rules/bug')  in (:8,'ALL')
    and apbr.xcontent.existsnode(:10) = 1
    order by extractvalue(apbr.xcontent,'/rules/priority')");

ARUDB::add_query(GET_EXCEPTION_RULE_LABELLOC =>
"select extractvalue(apbr.xcontent,:10),
    extractvalue(apbr.xcontent,:11),
    extractvalue(apbr.xcontent,'/rules/priority')
    from apf_patch_build_rules apbr
    where extractvalue(apbr.xcontent,'/rules/rule/action') = :7
    and (extractvalue(apbr.xcontent,'/rules/name') like :1 or extractvalue(apbr.xcontent,'/rules/name') like :2)
    and apbr.product_id = :3
    and apbr.patch_type in (:4,'ALL')
    and apbr.status = 'Y'
    and extractvalue(apbr.xcontent,'/rules/platform') in (:5,'ALL')
    and existsNode(apbr.xcontent,
        '/rules/release[text() = \"ALL\" or text() = \"' || :6 || '\" ]') = 1
    and extractvalue(apbr.xcontent,'/rules/type')  in (:8,'none')
    and extractvalue(apbr.xcontent,'/rules/bug')  in (:9,'ALL')
    and apbr.xcontent.existsnode(:11) = 1
    order by extractvalue(apbr.xcontent,'/rules/priority')");

ARUDB::add_query(GET_VALIDATION_RULE_FILES =>
"select extractvalue(apbr.xcontent,:9),
    extract(apbr.xcontent,:10).getStringVal(),
    extractvalue(apbr.xcontent,'/rules/priority')
    from apf_patch_build_rules apbr
    where extractvalue(apbr.xcontent,'/rules/rule/action') = :6
    and extractvalue(apbr.xcontent,'/rules/name') like :1
    and apbr.product_id = :2
    and apbr.patch_type in (:3,'ALL')
    and apbr.status = 'Y'
    and extractvalue(apbr.xcontent,'/rules/platform') in (:4,'ALL')
    and extractvalue(apbr.xcontent,'/rules/series_name') in (:11,'ALL')
    and existsNode(apbr.xcontent,
        '/rules/release[text() = \"ALL\" or text() = \"' || :5 || '\" ]') = 1
    and extractvalue(apbr.xcontent,'/rules/type')  in (:7,'none')
    and extractvalue(apbr.xcontent,'/rules/bug')  in (:8,'ALL')
    and apbr.xcontent.existsnode(:10) = 1
    order by extractvalue(apbr.xcontent,'/rules/priority')");

ARUDB::add_query(GET_XMLDB_SA_PATTERNS =>
"select dummy_table.* from
    (
     select xcontent
     from apf_patch_build_rules apbr
     where extractvalue(apbr.xcontent,'/rules/rule/action') = 'ignore'
         and apbr.product_id = :1
         and apbr.patch_type in (:2,'ALL')
         and apbr.status = 'Y'
         and extractvalue(apbr.xcontent,'/rules/platform') in (:3,'ALL')
         and existsNode(apbr.xcontent,
         '/rules/release[text() = \"ALL\" or text() = \"' || :4 || '\" ]') = 1
         and extractvalue(apbr.xcontent,'/rules/type')  in (:5)
         and extractvalue(apbr.xcontent,'/rules/bug')  in (:6,'ALL')
    ) A, xmltable(
        '//pattern' PASSING A.xcontent COLUMNS
        \"file\" varchar2(1000) path '//pattern/file/text()',
        \"template\" varchar2(4000) path '//pattern/template/text()',
        \"oui\" varchar(100) path '//pattern/oui/text()',
        \"type\" varchar(10) path '//pattern/\@type'
) dummy_table");


ARUDB::add_query(GET_XMLDB_FILE_IGNORE_PATTERNS =>
"
SELECT  distinct tbl.pattern,
        CASE WHEN instr(pattern,'/') > 0
        THEN regexp_substr(tbl.pattern,'\.([^.]*?)\$',1,1,'i',1)
        ELSE null
        END as extn,
        tbl.patt_type
FROM
(
   SELECT xcontent
   FROM apf_patch_build_rules apbr
   WHERE extractvalue(apbr.xcontent,'/rules/rule/action') = 'ignore'
     AND apbr.product_id = :1
     AND apbr.patch_type in (:2,'ALL')
     AND apbr.status = 'Y'
     AND extractvalue(apbr.xcontent,'/rules/platform') in (:3,'ALL')
     AND existsNode(apbr.xcontent,
         '/rules/release[text() = \"ALL\" or text() = \"' || :4 || '\" ]') = 1
     AND extractvalue(apbr.xcontent,'/rules/type')  in ( :5 )
     AND extractvalue(apbr.xcontent,'/rules/bug')  in (:6,'ALL')

) A, XMLTABLE('//patterns/pat' PASSING A.xcontent COLUMNS
              pattern varchar2(4000) PATH '//pat/text()',
              patt_type varchar2(5) PATH '//pat/\@type') tbl
WHERE tbl.pattern is not null
ORDER BY patt_type,extn,pattern
");

ARUDB::add_query(CHECK_AUTO_RELEASE_RULE =>
"select apbr.product_id,
        nvl(extractvalue(apbr.xcontent,'/rules/rule/validate_padxml'), 'yes'),
        nvl(extractvalue(apbr.xcontent,'/rules/rule/fully_automated'), 'no')
  from apf_patch_build_rules apbr
 where apbr.product_id = :1
   and apbr.patch_type = 'ALL'
   and extractvalue(apbr.xcontent,'/rules/release[position()=1]') = :2
   and extractvalue(apbr.xcontent,'/rules/platform') in (:3,'ALL')
   and extractvalue(apbr.xcontent,'/rules/rule/action') = 'release'
   and extractvalue(apbr.xcontent,'/rules/rule/manual_override') = 1");

ARUDB::add_query('IS_WS_WCCORE_TOPLINK' =>
"select count(*)
   from aru_products
  where product_id = :1
    and bugdb_product_id in (5242, 1271, 1339)");

ARUDB::add_query(GET_CPCT_REL_ID =>
"select distinct acpr.aru_release_id
 from  aru_cum_patch_releases acpr
 where acpr.release_id = :1");

ARUDB::add_query(GET_REL_ID =>
"select distinct ar.release_id
 from  aru_product_releases apr
 , aru_releases ar
 , aru_products ap
 , aru_product_groups apg
 where ap.bugdb_product_id = :1
 and (apg.child_product_id = ap.product_id
       and apr.product_id = apg.parent_product_id)
 and ar.release_id = apr.release_id
 and aru_backport_util.pad_version(ar.release_name) =
          aru_backport_util.pad_version(:2)
 order by ar.release_id");

ARUDB::add_query(GET_RELEASE_ID_FROM_BUG =>
"select max(release_id) from aru_bugfixes
  where bugfix_rptno = :1");

ARUDB::add_query(GET_BUGFIX_ID_FOR_BUG =>
"select bugfix_id from aru_bugfixes
  where bugfix_rptno = :1
  and   release_id = :2");

ARUDB::add_query (CPCT_RELEASE_TYPE =>
"select acps.family_name || '_' || acpsp.parameter_value
    from Aru_Cum_Patch_Series acps, Aru_Cum_Patch_Releases acpr,
    aru_cum_patch_series_params acpsp
    where acpr.release_version = :2
    and acpr.Aru_Release_Id = :1
    and acps.series_id = acpr.series_id
    and acpsp.parameter_name  = 'Conflict Resolution'
    and acpsp.series_id = acpr.series_id");

ARUDB::add_query (GET_CPM_PARAM_VALUES =>
"select parameter_value, release_id, parameter_type
    from aru_cum_patch_release_params
    where release_id = :1
    and   parameter_name = :2");


ARUDB::add_query(FETCH_TRANSACTION_NAME =>
"select atr.transaction_name
 from   aru_transactions atr
 where  atr.bugfix_request_id = :1");

ARUDB::add_query(GET_IGNORE_FILELIST =>
"select  distinct ao.object_location || '/' || ao.object_name
   from aru_objects ao
      , aru_label_dependencies ald
      , aru_product_releases apr
   where ald.a_uses_b = ao.object_id
    and ao.filetype_id <> " . ARU::Const::filetype_oui . "
    and ao.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id in ( :2 , :3 )
    and ald.build_dependency = 'NO-SHIP'");

ARUDB::add_query(GET_GENERIC_32BIT_LABEL =>
"select aprl.label_name,aprl.label_id
   from aru_product_release_labels aprl,
        aru_product_release_labels aprl1
  where aprl1.label_name = :1
    and aprl.product_release_id = aprl1.product_release_id
    and aprl.platform_id in
           (" . ARU::Const::platform_linux . ","
              . ARU::Const::platform_generic . ")");

ARUDB::add_query(GET_LABEL_NAME_FROM_LABEL_ID =>
"select aprl.label_name
 from   aru_product_release_labels aprl
 where  aprl.label_id = :1");

ARUDB::add_query(GET_RELEASE_ID_FOR_EXADATA =>
"select release_id, base_release_id from aru_releases where
  release_name = :1");

 ARUDB::add_query(GET_DISTINCT_LABEL_DEP =>
 "select distinct label_dependency
     from aru_label_dependencies, aru_objects ao
     where b_used_by_a=(
             select object_id
               from aru_objects
               where object_name        = :1
                 and object_location    = :2
                 and product_release_id = :3
             )
     and label_id = :4
     and a_uses_b = ao.object_id
     and ao.object_name = :5");

 ARUDB::add_query(IS_DIRECT_PREDC_OUI =>
 "select ao.object_name, ao.object_location, ao.object_type
     from aru_label_dependencies ald, aru_objects ao
     where ald.b_used_by_a=(
             select object_id
             from aru_objects
             where object_name      = :1
             and object_location    = :2
             and product_release_id = :3
             )
     and ald.label_id     = :4
     and ao.object_type   = 'oui'
     and ( ao.object_name = :5 or ao.object_name = :6 )
     and ao.object_id     = ald.a_uses_b");


 ARUDB::add_query(IS_OUI_KID =>
 "select ao.object_name, ao.object_location, ao.object_type
     from aru_label_dependencies ald, aru_objects ao
     where ald.b_used_by_a=(
             select object_id
             from aru_objects
             where object_name      = :1
             and object_location    = :2
             and product_release_id = :3
             )
     and ald.label_id     = :4
    and ao.object_id = ald.a_uses_b");

ARUDB::add_query(GET_PATCH_TYPE_DESC =>
"select acps.family_name
 from  aru_cum_patch_series acps,
       aru_cum_patch_releases acpr
 where aru_backport_util.pad_version(acpr.release_version)
     = aru_backport_util.pad_version(:2)
 and   acpr.aru_release_id = :1
 and   acps.series_id = acpr.series_id");

ARUDB::add_query(GET_ARU_RELEASE_NAME =>
"select ar.release_name
 from aru_releases ar
 where ar.release_id = :1");

ARUDB::add_query(GET_OCOM_COUNT =>
"select count(distinct ao.object_id)
 from   aru_bugfix_request_objects abro
 ,      aru_objects ao
 ,      aru_label_dependencies ald
 where  abro.object_id = ao.object_id
 and    ald.a_uses_b = ao.object_id
 and    abro.bugfix_request_id = :1
 and    ald.label_dependency = 'OCOM'");

ARUDB::add_query(GET_NON_OCOM_COUNT =>
"select count(distinct ao2.object_id)
 from   aru_bugfix_request_objects abro2
 ,      aru_objects ao2
 ,      aru_label_dependencies ald2
 where  abro2.bugfix_request_id = :1
 and    abro2.object_id = ao2.object_id
 and    ald2.a_uses_b = ao2.object_id
 and    ald2.label_dependency <> 'OCOM'
 and    ao2.object_id not in
        (select distinct ao1.object_id
         from   aru_bugfix_request_objects abro1
         ,      aru_objects ao1
         ,      aru_label_dependencies ald1
         where  abro1.object_id = ao1.object_id
         and    abro1.bugfix_request_id = :1
         and    ald1.label_dependency = 'OCOM'
         and    ald1.a_uses_b = ao1.object_id)");


ARUDB::add_query (GET_AVAILABLE_COUNT =>
"select count(ars.isd_request_id)
 from   apf_request_statuses ars
 where  ars.host_id = :1
  and   ars.platform_id = :2
  and   ars.customer_type = :3
  and   ars.request_type = :4
  and   ars.group_id = :5
  and   ars.config_type = :6
  and   ars.status_id not in (:7,"
       .ISD::Const::isd_request_stat_fail.","
       .ISD::Const::isd_request_stat_succ.")");

ARUDB::add_query(IS_REQUEST_NEED_ABORT =>
"select count(1)
   from apf_request_statuses
  where isd_request_id = :1
  and   to_char(creation_date,'YYYYMMDD HH24MISS') !=
        to_char(last_updated_date,'YYYYMMDD HH24MISS')");

ARUDB::add_query(IS_REQ_ALREADY_ABORTED =>
"select count(1)
   from apf_request_statuses
  where isd_request_id = :1
   and  comments like :2");

ARUDB::add_query(GET_CUSTOMER_NAME =>
"select customer
 from   bugdb_rpthead_v
 where  rptno = :1");

ARUDB::add_query(GET_MANAGER_HOST_DETAILS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from aru_hosts ah, aru_file_locations afl, apf_instances ai,
        apf_host_configurations ahc
  where ai.grid_id = :1
    and afl.location_id = ai.location_id
    and afl.host_id = ah.host_id
    and ah.host_name like :2
    and ahc.host_id  = ah.host_id
    and ahc.platform_id = :3
    and ahc.config_type = :4
    and ahc.customer_type = :5
    and ahc.request_type = :6
    and ahc.group_id = :7
    and ahc.host_enabled = 'Y'
    and ah.host_id = ahc.host_id
    order by ah.host_id");

ARUDB::add_query(GET_FA_MANAGER_HOST_DETAILS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from aru_hosts ah, aru_file_locations afl, apf_instances ai,
        apf_host_configurations ahc
  where ai.grid_id = :1
    and afl.location_id = ai.location_id
    and afl.host_id = ah.host_id
    and ahc.host_id  = ah.host_id
    and ahc.platform_id = :2
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    and ah.host_id = ahc.host_id
    order by ah.host_id");

ARUDB::add_query(GET_CHILD_AVAIL_WKR_HOST_DETAILS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    order by ah.host_id");

ARUDB::add_query(GET_CHILD_AVAIL_WKR_HOSTS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_name = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    order by ah.host_id");

ARUDB::add_query(GET_PARENT_AVAIL_WKR_HOST_DETAILS =>
"select distinct ah.host_id, ah.host_name, ah.host_account,
        afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        aru_release_label_groups arlg,
        apf_host_configurations ahc
  where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id  = afl.host_id
    and ahc.host_id = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    order by ah.host_id");

ARUDB::add_query(GET_FREE_INSTALLTEST_WKR_HOST_DETAILS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = :2
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'
  order by ah.host_account");

ARUDB::add_query(GET_CHILD_BUILD_HOST_CONFIG_COUNT =>
"select count(distinct ah.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    order by ah.host_id");

ARUDB::add_query(GET_PARENT_BUILD_HOST_CONFIG_COUNT =>
"select count(distinct ah.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        aru_release_label_groups arlg,
        apf_host_configurations ahc
  where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id  = afl.host_id
    and ahc.host_id = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    order by ah.host_id");

ARUDB::add_query(GET_INSTALL_HOST_CONFIG_COUNT=>
"select count(distinct ah.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = :2
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'
  order by ah.host_account");

ARUDB::add_query(GET_HOST_COUNT =>
"select count(ahc.host_id)
 from  apf_host_configurations ahc
 where ahc.host_id = :1
   and ahc.platform_id = :2
   and ahc.config_type = :3
   and ahc.customer_type = :4
   and ahc.request_type = :5
   and ahc.group_id = :6
   and ahc.host_enabled = 'Y'
   and ahc.requests_allowed > 0");

ARUDB::add_query(GET_CONFIG_COUNT =>
"select count(ahc.host_id)
 from  apf_host_configurations ahc
 where ahc.platform_id = :1
   and ahc.customer_type = :2
   and ahc.request_type = :3
   and ahc.group_id = :4
   and ahc.config_type = :5
   and ahc.host_enabled = 'Y'
   and ahc.requests_allowed > 0");

ARUDB::add_query(GET_HOST_CONFIG_COUNT =>
"select count(ahc.host_id)
 from  apf_host_configurations ahc,
       apf_request_statuses ars
 where ars.isd_request_id = :1
   and ahc.platform_id = ars.platform_id
   and ahc.customer_type = ars.customer_type
   and ahc.request_type = ars.request_type
   and ahc.group_id = ars.group_id
   and ahc.config_type = ars.config_type
   and ahc.host_enabled = 'Y'
   and ahc.requests_allowed > 0");

ARUDB::add_query(GET_CONFIG_COUNT_FOR_FA =>
"select count(ahc.host_id)
 from  apf_host_configurations ahc
 where ahc.platform_id = :1
   and ahc.customer_type = :2
   and ahc.request_type in (:3 , :4)
   and ahc.host_enabled = 'Y'
   and ahc.group_id = :5
   and ahc.config_type = :6
   and ahc.requests_allowed > 0");
ARUDB::add_query(GET_MANAGER_HOST_COUNT =>
"select count(ahc.host_id)
 from  apf_host_configurations ahc
 where ahc.platform_id = :1
   and ahc.customer_type = :2
   and ahc.request_type = :3
   and ahc.group_id = :4
   and ahc.config_type = :5
   and ahc.host_enabled = 'Y'
   and ahc.requests_allowed > 0");

ARUDB::add_query(GET_MAX_REQ_ALLOWED =>
"select ahc.requests_allowed
  from  apf_host_configurations ahc
  where ahc.host_id = :1
    and ahc.platform_id = :2
    and ahc.customer_type = :3
    and ahc.request_type = :4
    and ahc.group_id = :5
    and ahc.config_type = :6
    and ahc.host_enabled = 'Y'");

ARUDB::add_query(GET_HOST_MAX_REQ_ALLOWED =>
"
select max(requests_allowed)
  from apf_host_configurations ahc,
       aru_hosts ah
 where ah.host_name like :1
   and ah.host_account like :2
   and ahc.host_id = ah.host_id
   and ahc.request_type = :3
"
);

ARUDB::add_query(GET_HOST_ID =>
"select distinct ah.host_id
 from  aru_hosts ah
 where ah.host_name = :1
  and  ah.host_account = :2");

ARUDB::add_query(GET_HOST_NAME =>
"select distinct ah.host_name
 from  aru_hosts ah
 where ah.host_id = :1");

ARUDB::add_query(GET_ISD_REQ_LOG =>
"select isd_logfile_name
   from apf_request_statuses
  where isd_request_id = :1");

ARUDB::add_query(GET_ISD_REQ_TYPE =>
"select request_type_code, reference_id
    from isd_requests
    where request_id = :1");

ARUDB::add_query(GET_CONFIG_UPDATE_TIME =>
" select count(1)
    from apf_host_configurations
   where host_id in (select host_id
                     from aru_hosts
                     where host_name = :1)
   and  (sysdate - :2 ) > nvl(last_updated_date,
                              to_date('01/01/2000', 'DD/MM/YYYY')) ");

ARUDB::add_query(APF_HOST_CONFIG_ID =>
"select distinct ahc.config_id
  from  apf_host_configurations ahc
  where ahc.host_id = 1
    and ahc.platform_id = :2
    and ahc.customer_type = :3
    and ahc.request_type = :4
    and ahc.config_type = :5
    and ahc.host_enabled = 'Y'");

ARUDB::add_query(GET_RELEASE_FROM_LABEL =>
"select distinct apr.release_id
   from aru_product_releases apr,
        aru_product_release_labels aprl
  where aprl.label_id = :1
   and  apr.product_release_id = aprl.product_release_id");

ARUDB::add_query(GET_PRIORITY_ISD_REQUEST =>
"select distinct pr.isd_request_id
 from
      (select distinct ars.isd_request_id isd_request_id
       from apf_request_statuses ars
       where ars.platform_id = :1
        and  ars.config_type = :2
        and  ars.customer_type = :3
        and  ars.request_type = :4
        and  ars.status_id = :5
        and  ars.group_id = :6
       order by ars.bug_priority,
                ars.creation_date,
                ars.isd_request_id) pr
 where rownum = 1");

ARUDB::add_query(GET_PRIORITY_REQUESTS =>
"select distinct pr.isd_request_id
 from
      (select distinct ars.isd_request_id isd_request_id
       from apf_request_statuses ars
       where ars.platform_id = :1
        and  ars.customer_type = :2
        and  ars.request_type = :3
        and  ars.status_id = :4
        and  ars.group_id = :5
        and  ars.config_type = :6
       order by ars.bug_priority,
                ars.creation_date,
                ars.isd_request_id) pr");

ARUDB::add_query(IS_REQUEST_HAS_HOST =>
"select count(1)
   from apf_request_statuses ars,
        apf_host_configurations ahc
  where ars.isd_request_id = :1
  and   ars.status_id not in (:2, :3)
  and   ahc.host_id = ars.host_id
  and   ahc.config_type = ars.config_type
  and   ahc.platform_id = ars.platform_id
  and   ahc.customer_type = ars.customer_type
  and   ahc.request_type = ars.request_type
  and   ahc.group_id = ars.group_id");

ARUDB::add_query(GET_APF_REQ_STATUS_DETAILS =>
"select platform_id, config_type, customer_type,
        request_type, group_id, host_id
   from apf_request_statuses
  where isd_request_id = :1");

ARUDB::add_query(GET_APF_REQUEST_DETAILS =>
"select platform_id, config_type, customer_type,
        request_type, sub_request_type, group_id, host_id,
        isd_logfile_name, label_id
   from apf_request_statuses
  where isd_request_id = :1");

ARUDB::add_query(GET_BUILD_HOST_COUNT =>
"select count(ahc.host_id)
   from apf_host_configurations ahc, aru_hosts ah
  where ah.host_name = :1
    and ah.host_account not like '%_installtest%'
    and ahc.host_id = ah.host_id
    and ahc.request_type = :2
    and ahc.platform_id = :3
    and ahc.host_enabled = 'Y'");

ARUDB::add_query(GET_INSTALL_TEST_HOST_COUNT =>
"select count(ahc.host_id)
   from apf_host_configurations ahc, aru_hosts ah
  where ah.host_name = :1
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'
    and ahc.host_id = ah.host_id
    and ahc.request_type = :2
    and ahc.platform_id = :3
    and ahc.host_enabled = 'Y'");

ARUDB::add_query(GET_APF_REQUEST_GROUP =>
"select group_id
  from  apf_request_statuses
 where  isd_request_id = :1");

ARUDB::add_query(THROTTLED_REQ_EXISTS =>
"select count(1)
   from apf_request_statuses
  where isd_request_id = :1
    and config_type = :2");

ARUDB::add_query(GET_TOP_PRIORITY_REQUESTS =>
"select pr1.isd_request_id
  from
   (select distinct pr.isd_request_id
    from
      (select distinct ars.isd_request_id isd_request_id
       from apf_request_statuses ars
       where ars.platform_id = :1
        and  ars.customer_type = :2
        and  ars.request_type = :3
        and  ars.status_id = :4
        and  ars.group_id = :5
        and  ars.config_type = :6
       order by ars.bug_priority,
                ars.creation_date,
                ars.isd_request_id) pr
    where rownum <= :7) pr1");

ARUDB::add_query(IS_REQ_TOP_PRIORITY_REQ =>
"select count(1)
  from
   (select distinct pr.isd_request_id
    from
      (select distinct ars.isd_request_id isd_request_id
       from apf_request_statuses ars
       where ars.platform_id = :1
        and  ars.customer_type = :2
        and  ars.request_type = :3
        and  ars.status_id = :4
        and  ars.group_id = :5
        and  ars.config_type = :6
       order by ars.bug_priority,
                ars.creation_date,
                ars.isd_request_id) pr
     where rownum <= :7) pr1
   where pr1.isd_request_id = :8");

ARUDB::add_query(GET_ISD_REQ_DETAILS =>
"select grid_id, status_code, priority, creation_date
   from isd_requests
  where request_id = :1");

ARUDB::add_query(GET_SUSPENDED_BUG_DETAILS=>
"select status, version_fixed, test_name
    from bugdb_rpthead_v
    where rptno = :1");

ARUDB::add_query(GET_ISD_REQUEST_STATUS =>
"select status_code, logfile_name
    from isd_requests
    where request_id = :1");

ARUDB::add_query (IS_REQUEST_AVAILABLE =>
"select count(1)
 from   apf_request_statuses ars
 where  ars.isd_request_id = :1
  and   ars.platform_id = :2
  and   ars.request_type = :3
  and   ars.group_id = :4
  and   ars.config_type = :5");

ARUDB::add_query (GET_INPROGRESS_REQUESTS =>
"select ars.isd_request_id,
        ars.status_id
 from   apf_request_statuses ars
 where  ars.host_id = :1
  and   ars.platform_id = :2
  and   ars.customer_type = :3
  and   ars.request_type = :4
  and   ars.sub_request_type = :4
  and   ars.group_id = :5
  and   ars.config_type = :6
  and   ars.status_id not in (:7,"
       .ISD::Const::isd_request_stat_fail.","
       .ISD::Const::isd_request_stat_succ.")");


ARUDB::add_query (GET_OTHER_INPROGRESS_REQUESTS =>
"select ars.isd_request_id,
        ars.status_id
 from   apf_request_statuses ars
 where  ars.host_id = :1
  and   ars.platform_id = :2
  and   ars.customer_type = :3
  and   ars.request_type = :4
  and   ars.sub_request_type = :8
  and   ars.group_id = :5
  and   ars.config_type = :6
  and   ars.status_id not in (:7,"
       .ISD::Const::isd_request_stat_fail.","
       .ISD::Const::isd_request_stat_succ.")");

ARUDB::add_query(GET_HOST_INPROGRESS_REQUESTS =>
"select isd_request_id
   from apf_request_statuses
  where host_id = :1
   and  config_type = :2
   and  status_id not in (:3,"
       .ISD::Const::isd_request_stat_fail.","
       .ISD::Const::isd_request_stat_succ.")");

ARUDB::add_query(GET_APF_REBOOT_REQUEST_ID =>
"select request_id, incident_id
from apf_incidents
where incident_id = (select max(incident_id)
   from apf_incidents
  where host_name = :1)");

ARUDB::add_query(GET_APF_INCIDENT_STATUS =>
"select count(1)
   from apf_incidents
  where request_id = :1
    and upper(status) = upper(:2)");

ARUDB::add_query(GET_INCIDENT_REBOOT_TIME =>
" select to_number(sysdate - (select last_update_date
                              from apf_incidents
                              where incident_id = :1)) * 86400
    from dual");

ARUDB::add_query(GET_REBOOT_WORKER_HOSTS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id");

ARUDB::add_query(GET_REBOOT_INSTALL_WKR_HOST_CNT =>
"select count(distinct ahc.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'");

ARUDB::add_query(GET_REBOOT_INSTALL_WKR_HOSTS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'");

ARUDB::add_query(GET_REBOOT_BUILD_WKR_HOST_CNT =>
"select count(distinct ahc.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_REBOOT_BUILD_WKR_HOSTS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where aprl.label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_REBOOT_PARENT_WKR_HOST_CNT =>
"select count(distinct ahc.host_id)
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        aru_release_label_groups arlg,
        apf_host_configurations ahc
  where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_REBOOT_PARENT_WKR_HOSTS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_hosts ah, aru_file_locations afl,
        aru_release_label_groups arlg,
        apf_host_configurations ahc
  where aprl.label_id = arlg.parent_label_id
    and arlg.child_label_id = :1
    and alls.label_id  = aprl.label_id
    and aprl.platform_id = :2
    and afl.location_id = alls.location_id
    and ah.host_id   = afl.host_id
    and ahc.host_id  = ah.host_id
    and ahc.host_enabled = 'R'
    and ahc.platform_id = aprl.platform_id
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_ALL_HOST_CONFIGS =>
"select distinct ah.host_id
    from apf_host_configurations ahc,
         aru_hosts ah
    where ah.host_name = :1
    and   (ah.host_account = 'apfwkr' or
           (ah.host_account like '%_installtest%' and
            ah.host_account not like '%_installtest%disabled%'))
    and ahc.host_id = ah.host_id
    and ahc.platform_id = :2");

ARUDB::add_query (GET_BUNDLE_REQ_COUNT =>
"select count(1)
 from   apf_request_statuses ars
 where  ars.host_id = :1
  and   ars.platform_id = :2
  and   ars.customer_type = :3
  and   ars.request_type = :4
  and   ars.sub_request_type = :5
  and   ars.group_id = :6
  and   ars.config_type = :7
  and   ars.status_id not in (:8,"
       .ISD::Const::isd_request_stat_fail.","
       .ISD::Const::isd_request_stat_succ.")");

ARUDB::add_query (IS_VALID_RUNNING_REQ =>
"select count(1)
 from isd_requests
 where request_id = :1
   and status_code = :2");

ARUDB::add_query(IS_THROTTLED_REQ_VALID =>
"select count(ahc.config_id)
from   apf_host_configurations ahc,
       apf_label_locations alls,
       aru_product_release_labels aprl,
       aru_product_releases apr,
       aru_hosts ah,
       aru_file_locations afl,
       apf_request_statuses ars
where ars.isd_request_id = :1
and   apr.release_id = ars.release_id
and   aprl.product_release_id = apr.product_release_id
and   aprl.platform_id = ars.platform_id
and   alls.label_id  = aprl.label_id
and   afl.location_id = alls.location_id
and   ah.host_id      = afl.host_id
and   ahc.host_id = ah.host_id
and   ahc.platform_id = aprl.platform_id
and   ahc.config_type = ars.config_type
and   ahc.customer_type = ars.customer_type
and   ahc.request_type= ars.request_type
and   ahc.group_id = ars.group_id
and   ahc.host_enabled = 'Y'
and   ahc.requests_allowed > 0");

ARUDB::add_query(IS_THROTTLED_BASE_REQ_VALID =>
"select count(ahc.config_id)
from   apf_host_configurations ahc,
       apf_label_locations alls,
       aru_product_release_labels aprl,
       aru_product_releases apr,
       aru_hosts ah,
       aru_file_locations afl,
       apf_request_statuses ars,
       aru_releases ar
where ars.isd_request_id = :1
and   ar.release_id = ars.release_id
and   apr.release_id = ar.base_release_id
and   aprl.product_release_id = apr.product_release_id
and   aprl.platform_id = ars.platform_id
and   alls.label_id  = aprl.label_id
and   afl.location_id = alls.location_id
and   ah.host_id      = afl.host_id
and   ahc.host_id = ah.host_id
and   ahc.platform_id = aprl.platform_id
and   ahc.config_type = ars.config_type
and   ahc.customer_type = ars.customer_type
and   ahc.request_type= ars.request_type
and   ahc.group_id = ars.group_id
and   ahc.host_enabled = 'Y'
and   ahc.requests_allowed > 0");

ARUDB::add_query(IS_MANAGER_THROTTLED_REQ_VALID =>
"select count(ahc.config_id)
from   apf_host_configurations ahc,
       aru_hosts ah,
       aru_file_locations afl,
       apf_instances ai,
       apf_request_statuses ars
where ai.grid_id = :1
and   afl.location_id = ai.location_id
and   ah.host_id      = afl.host_id
and   ahc.host_id = ah.host_id
and   ars.isd_request_id = :2
and   ahc.platform_id = ars.platform_id
and   ahc.config_type = ars.config_type
and   ahc.customer_type = ars.customer_type
and   ahc.request_type= ars.request_type
and   ahc.group_id = ars.group_id
and   ahc.host_enabled = 'Y'
and   ahc.requests_allowed > 0");

ARUDB::add_query(GET_REQ_PREVIOUS_STATUS =>
"select prev_status_id
    from apf_request_statuses
    where isd_request_id =  :1");

ARUDB::add_query(GET_PREVIOUS_REQ_HOST =>
"select distinct host_name
from (
select distinct replace(error_message,'On ') host_name, change_date
from isd_request_history
where request_id = :1
and status_code = ".ISD::Const::isd_request_stat_proc ."
order by change_date desc)");

ARUDB::add_query(GET_FREE_INSTALL_TEST_WKR_DET =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls,
        aru_product_release_labels aprl,
        aru_product_releases apr, aru_releases ar,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where ar.base_release_id = :1
    and apr.product_id = :2
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :3
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :4
    and ahc.customer_type = :5
    and ahc.request_type = :6
    and ahc.group_id = :7
    and ahc.host_enabled = 'Y'
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'
  order by ah.host_account");

ARUDB::add_query(GET_FREE_BUILD_WKR_DET =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls,
        aru_product_release_labels aprl,
        aru_product_releases apr, aru_releases ar,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where ar.base_release_id = :1
    and apr.product_id = :2
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :3
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :4
    and ahc.customer_type = :5
    and ahc.request_type = :6
    and ahc.group_id = :7
    and ahc.host_enabled = 'Y'
    and ah.host_account not like '%_installtest%'
  order by ah.host_account");

ARUDB::add_query(GET_FREE_BUILD_WKR_HOSTS =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls,
        aru_product_release_labels aprl,
        aru_product_releases apr, aru_releases ar,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where ar.base_release_id = :1
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :2
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :3
    and ahc.customer_type = :4
    and ahc.request_type = :5
    and ahc.group_id = :6
    and ahc.host_enabled = 'Y'
    and ah.host_account not like '%_installtest%'
  order by ah.host_account");

ARUDB::add_query(GET_FREE_BUILD_WKR_DET_LIKE =>
"select distinct ah.host_id, ah.host_name, ah.host_account, afl.location_path
   from apf_label_locations alls,
        aru_product_release_labels aprl,
        aru_product_releases apr, aru_releases ar,
        aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc
  where ar.base_release_id = :1
    and apr.product_id = :2
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :3
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.config_type = :4
    and ahc.customer_type = :5
    and ahc.request_type = :6
    and ahc.group_id = :7
    and aprl.label_name like :8
    and ahc.host_enabled = 'Y'
    and ah.host_account not like '%_installtest%'
  order by ah.host_account");

ARUDB::add_query(GET_REBOOT_INSTALL_WKRS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_product_releases apr, aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc, aru_releases ar
where ar.base_release_id = :1
    and apr.product_id = :2
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :3
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.host_enabled = 'R'
    and ah.host_account like '%_installtest%'
    and ah.host_account not like '%_installtest%disabled%'");

ARUDB::add_query(GET_REBOOT_BUILD_WKRS =>
"select distinct ah.host_name
   from apf_label_locations alls, aru_product_release_labels aprl,
        aru_product_releases apr, aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc, aru_releases ar
where ar.base_release_id = :1
    and apr.product_id = :2
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :3
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.host_enabled = 'R'
    and ah.host_account = 'apfwkr'
    and ah.host_account not like '%_installtest%'");

ARUDB::add_query(GET_DISABLED_WKR_HOSTS =>
"select distinct ah.host_name
    from apf_label_locations alls, aru_product_release_labels aprl,
        aru_product_releases apr, aru_hosts ah, aru_file_locations afl,
        apf_host_configurations ahc, aru_releases ar
where ar.base_release_id = :1
    and apr.release_id = ar.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = :2
    and alls.label_id  = aprl.label_id
    and afl.location_id = alls.location_id
    and ah.host_id      = afl.host_id
    and ahc.host_id     = ah.host_id
    and ahc.platform_id = aprl.platform_id
    and aprl.platform_id = ahc.platform_id
    and ahc.host_enabled in (select COLUMN_VALUE
                                   from table(aru_util.split(:3,',')))");

ARUDB::add_query(GET_REL_PLAT_FROM_LABEL =>
"select distinct apr.release_id,
    aprl.platform_id, aprl.label_name
   from aru_product_releases apr,
        aru_product_release_labels aprl
  where aprl.label_id = :1
   and  apr.product_release_id = aprl.product_release_id");

ARUDB::add_query(GET_ALL_PRIORITY_REQUESTS =>
"select distinct pr.isd_request_id, pr.release_id, pr.isd_status_code,
        pr.base_release_id
    from
    (
       select distinct ars.bug_priority,
                ir.creation_date,
                ars.isd_request_id, ars.status_id,
                ir.status_code isd_status_code,
                ars.release_id, ar.base_release_id
       from apf_request_statuses ars, isd_requests ir, aru_releases ar
       where ars.platform_id =  :1
        and  ars.customer_type = :2
        and  ars.request_type = :3
        and  ars.status_id = :4
        and  ars.group_id =  :5
        and  ars.config_type = :6
        and ir.request_id = ars.isd_request_id
        and ir.creation_date <= (select ir1.creation_date
                                 from isd_Requests ir1
                                 where ir1.request_id = :7)
        and ar.release_id = ars.release_id
        and ar.base_release_id in (select COLUMN_VALUE
                                   from table(aru_util.split(:8,',')))
       order by ars.bug_priority, ir.creation_date,
                ars.isd_request_id desc) pr");

ARUDB::add_query (GET_THROTTLE_REQ_STATUS =>
"select ars.status_id
 from   apf_request_statuses ars
 where  ars.isd_request_id = :1
  and   ars.platform_id = :2
  and   ars.request_type = :3
  and   ars.group_id = :4
  and   ars.config_type = :5");

ARUDB::add_query(GET_WKR_REBOOT_REQUEST_ID =>
"select request_id, incident_id
from apf_incidents
where incident_id = (select max(incident_id)
   from apf_incidents
  where host_name = :1
    and upper(status) = upper(:2))");

ARUDB::add_query(IS_ISD_REQ_RUNNING =>
"select count(1)
  from  isd_requests
 where  request_id = :1
  and   status_code = ".ISD::Const::st_apf_preproc);

ARUDB::add_query(GET_COPY_OR_MERGE =>
"select decode(count(request_type), 0, 'APF-COPY', 'APF-MERGE')
   from apf_build_request_history
   where request_type in (" .
   ISD::Const::st_apf_regress . ", " . APF::Const::st_apf_farm_diff_ok .
   ") and request_id = (select max(request_id) from apf_build_requests
   where backport_bug = :1)");

ARUDB::add_query(
  GET_EMCC_TESTRUN_DETAILS =>
    "select apftrs.testrun_id, apftrs.label_id,
            apftrs.platform_id, apftrs.release_id,
            apfts.testresult_id, apfts.status_id, apfts.testflow_id,
            apft.testsuite_name
       from apf_testresults apfts, apf_testruns apftrs,
            apf_testsuites apft, apf_testflows apftf
      where apftf.testflow_name like :1||'%'
        and apfts.testflow_id = apftf.testflow_id
        and apfts.testrun_id = apftrs.testrun_id
        and apftrs.testrun_id = ( select max(testrun_id)
                                    from apf_testruns
                                   where bugfix_request_id = :2 )
        and apft.testsuite_id = apfts.testsuite_id
       order by apfts.testresult_id",

  GET_EMCC_TESTS_COUNT =>
    "select count(*)
       from apf_tests_v
      where label_id = :1"
 );

ARUDB::add_query(IS_REQUEST_IN_PROGRESS =>
"select count(1)
 from   apf_request_statuses
 where  isd_request_id = :1
 and    status_id = :2
 and    group_id = :3");

ARUDB::add_query(GET_APF_REQ_STATUS =>
"select status_id
 from   apf_request_statuses
 where  isd_request_id = :1");

ARUDB::add_query(GET_REQUEST_CONFIG_TYPE =>
"select config_type
 from   apf_request_statuses
 where  isd_request_id = :1");

ARUDB::add_query(IS_PATCH_RELEASED =>
"select count(1)
  from  aru_bugfix_requests
  where bugfix_request_id = :1
   and  status_id =".ARU::Const::patch_ftped_support);

ARUDB::add_query(GET_APF_REQ_STATUS_COMMENTS =>
"select comments
 from apf_request_statuses
 where isd_request_id = :1");

ARUDB::add_query(GET_PATCH_LEVEL =>
"select value
 from aru_parameters
 where name = :1");

ARUDB::add_query(GET_CPCT_RELEASE_VERSION =>
"select aru_backport_util.pad_version(release_version)
  from  aru_cum_patch_releases
 where  release_id = :1");

ARUDB::add_query(GET_CPCT_RELEASE_DETAILS =>
"select distinct ar.release_name
 , ar.release_id
 , ar.release_long_name
 from aru_releases ar
 , aru_cum_patch_releases acpr
 where acpr.release_id = :1
 and ar.release_id = acpr.aru_release_id");

ARUDB::add_query(GET_CPCT_HYBRID_LABEL =>
 "select aprl1.label_id, aprl1.label_name,
  aprl2.label_id, aprl2.label_name
 from aru_product_release_labels aprl1,
 aru_product_release_labels aprl2,
 aru_product_releases apr
 where aprl1.product_release_id = apr.product_release_id
 and apr.product_id = :1
 and apr.release_id = :2
 and aprl1.platform_id = :3
 and aprl1.label_name in (select acprl.platform_release_label
                          from  aru_cum_plat_rel_labels acprl,
                                aru_cum_patch_releases acpr2
                          where acprl.release_id = acpr2.release_id
                          and   acpr2.aru_release_id = :2
                          and   acprl.platform_id = :3)
 and aprl2.label_id = aprl1.hybrid_label_id
 and aprl1.hybrid_label_id is not null");

ARUDB::add_query(GET_CPCT_LABEL_NAME =>
"select aprl.label_id, aprl.label_name
   from aru_product_release_labels aprl, aru_product_releases apr
  where aprl.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id = :2
    and aprl.platform_id = :3
    and aprl.label_name in (select acprl.platform_release_label
                             from  aru_cum_plat_rel_labels acprl,
                                   aru_cum_patch_releases acpr2
                             where acprl.release_id = acpr2.release_id
                             and   acpr2.aru_release_id = :2
                             and   acprl.platform_id = :3)
    and hybrid_label_id is null");

ARUDB::add_query(GET_CPCT_BASE_LABEL =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl, aru_product_releases apr,
apf_configurations ac
where apr.product_id = :1
and apr.release_id = :2
and apr.release_id = ac.release_id
and aprl.product_release_id = apr.product_release_id
and aprl.platform_id = ac.platform_id
and ac.request_enabled = '" . ARU::Const::auto_req_base_us . "'
and ac.apf_type = '" . ARU::Const::apf_manager_type . "'
and ac.language_id = " . ARU::Const::language_US ."
and aprl.label_name in (select acprl.platform_release_label
                       from aru_cum_plat_rel_labels acprl,
                            aru_cum_patch_releases acpr
                       where acprl.platform_id = ac.platform_id
                       and   acprl.release_id = acpr.release_id
                       and   acpr.aru_release_id = :2)");

ARUDB::add_query(GET_CPCT_LABEL_BY_PARAMS =>
"select acprp.parameter_name
from   aru_cum_patch_release_params acprp
where  acprp.release_id = :1
and    parameter_value = :2
and    parameter_name like :3 escape '\\'
and    parameter_name <> :4");

ARUDB::add_query(GET_CPCT_INFO_BY_PSE =>
"select acprp.parameter_name, brv.base_rptno, ap.platform_name
from   aru_cum_patch_release_params acprp
,      bugdb_rpthead_v brv
,      aru_platforms ap
where  brv.rptno = :1
and    ap.bugdb_platform_id = brv.portid
and    acprp.parameter_value = to_char(brv.base_rptno)");

ARUDB::add_query(GET_REPORTED_BY =>
"select rptd_by
 from bugdb_rpthead_v
 where rptno = :1");

ARUDB::add_query(GET_PARENT_PROD_ID =>
"select min(parent_product_id)
 from aru_product_groups apg, aru_products ap
 where apg.child_product_id = ap.product_id
 and   apg.relation_type    = ".ARU::Const::direct_relation ."
 and   ap.product_id     = :1
 and   ap.product_type != :2");

ARUDB::add_query(GET_AREA_MANAGER_DETAILS=>
"select qown, qownmail, dev_owner, area_mgr,
        active_flg, platform
from PDTASGTBL
where pdtid = :1
  and comp  = :2
  and subc  = :3
  and g_or_p = 'G'");

ARUDB::add_query(GET_MANAGER_EMAIL =>
"select full_email, manager_email
from bugdb_bug_user_mv
where upper(bug_username) = upper(:1)");

ARUDB::add_query(GET_MANAGER_EMAIL_USING_GUID =>
"select concat(manager_email, '\@ORACLE.COM')
from bugdb_bug_user_mv
where global_uid = upper(:1)");

ARUDB::add_query(GET_SUPPORT_CONTACT =>
"select SUPPORT_CONTACT from bugdb_rpthead_v where rptno=:1");

ARUDB::add_query(GET_REGRESSION_STATUS =>
"select regression_status from bugdb_rpthead_v
  where rptno = (select base_rptno from bugdb_rpthead_v
  where rptno = :1)");

ARUDB::add_query(GET_KSPARE_DATA =>
"select decode(substr(request_params,4,1), 'Y', 1, 0) from apf_build_requests
   where request_id = (select max(request_id) from apf_build_requests
   where backport_bug = :1)");

ARUDB::add_query(GET_PROD_INFO_FROM_LABEL =>
"select apr.product_id,apr.release_id,apr.product_release_id ,apr.pset_prefix,
ap.bugdb_product_id,
ap.bugdb_component,
ap.bugdb_subcomponent,
ap.product_name,
ap.product_abbreviation
from aru_product_releases apr, aru_products ap
where product_release_id = (
select product_release_id from aru_product_release_labels aprl
where label_name = :1
and platform_id = :2 )
and ap.product_id = apr.product_id");

ARUDB::add_query(GET_COMPAT_PARAM =>
"select value, description
 from aru_parameters
 where name = :1");

ARUDB::add_query(GET_REQUEST_STATUS =>
"select decode(status,'ENABLE',1,'DISABLE',0,'SUSPEND',-1) as STATUS ,
       description,exception_rule_ids
from apf_automation_types
where label_id = :1
and type = :2 ");

ARUDB::add_query(GET_EXCEPTION_RULES =>
"select rule_id,extract(xcontent,'/').getStringVal()
from apf_patch_build_rules
where rule_id in (
    select distinct regexp_substr( :1 ,'[^,]+', 1  , level ) from dual
    connect by regexp_substr(:2, '[^,]+', 1 , level ) is not null) ");

ARUDB::add_query(GET_BASE_LABEL_INFO =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl, aru_product_releases apr,
apf_configurations ac
where apr.product_id = :1
    and apr.release_id = :2
    and apr.release_id = ac.release_id
    and aprl.product_release_id = apr.product_release_id
    and aprl.platform_id = ac.platform_id
    and aprl.platform_id = :3 ");

ARUDB::add_query(GET_PARENT_LABEL_ID =>
"select distinct parent_label_id
from aru_release_label_groups
where child_label_id = :1
union
select distinct parent_label_id
from aru_release_label_groups
where parent_label_id = :1");

ARUDB::add_query(CI_ASSIGNED_TO_DEV =>
"select count(distinct developer_assigned)
  from aru_cum_patch_releases acpr, bugdb_rpthead_v rh
  where acpr.release_version = rh.utility_version
  and developer_assigned = 'Y'
  and rh.rptno = :1");

ARUDB::add_query(GET_BUG_DETAILS =>
"select rptno, base_rptno, utility_version, status, version,
        portid, generic_or_port_specific, product_id, category,
        sub_component, customer, version_fixed, test_name, rptd_by
 from  bugdb_rpthead_v
 where rptno = :1");

ARUDB::add_query(GET_BUG_UPDATE_DETAILS =>
" select programmer, version_fixed, test_name, status
   from  bugdb_rpthead_v
   where rptno = :1");

ARUDB::add_query(GET_FUSION_DO_RCS_VER =>
"select substr(abov.rcs_version,(instr(abov.rcs_version,'/',-1)+1))
 from   aru_bugfix_object_versions abov, aru_bugfixes ab, aru_objects ao
 Where  ab.bugfix_id = abov.bugfix_id
 and    abov.object_id = ao.object_id
 and    ab.bugfix_rptno = :1
 and    ao.object_location = :2
 and    ao.object_name = :3
 and    ab.release_id = :4
 and    (abov.source like 'D%' or abov.source like '%I%')");

ARUDB::add_query("GET_BUGDB_PRODUCT_ID" =>
"select bugdb_product_id
    from aru_products
    where product_id = :1");


ARUDB::add_query("GET_MLR_ASG_PARAM" =>
"select 1 status
    from aru_parameters
    where name = 'MLR ASSIGNMENT'
    and value like :1
    and rownum = 1");

ARUDB::add_query("GET_USER_STATUS" =>
"select 1
    from bugdb_bug_user_mv
    where status = 'A'
    and  bug_username = :1
    and  rownum < 2 ");

ARUDB::add_query("GET_ARU_PARAM" =>
"select value
    from aru_parameters
    where name = :1
    and rownum = 1");

ARUDB::add_query("GET_DEP_LABEL_REL_ID" =>
"select release_id
from aru_cum_patch_release_params
where parameter_name = :1");

ARUDB::add_query("GET_USER_STATUS" =>
"select 1
    from bugdb_bug_user_mv
    where status = 'A'
    and  bug_username = :1
    and  rownum < 2 ");

ARUDB::add_query("GET_RELEASED_ARU_STATUS" =>
"select status_id
 from aru_bugfix_request_history
 where status_id in (".ARU::Const::patch_ftped_support . "," .
                      ARU::Const::patch_ftped_dev . ")
 and BUGFIX_REQUEST_ID = :1
 and bugfix_request_history_id = (
 select max(bugfix_request_history_id)
 from aru_bugfix_request_history
 where status_id in (".ARU::Const::patch_ftped_support . "," .
                      ARU::Const::patch_ftped_dev . ")
 and BUGFIX_REQUEST_ID = :1 )" );

ARUDB::add_query("GET_SRC_LIST_FOR_TXN" =>
"select ao.object_name
 from   aru_objects ao, aru_bugfix_object_versions abov, aru_transactions at
 where  ao.object_id = abov.object_id
 and    abov.bugfix_id = at.bugfix_id
 and    (abov.source like 'D%' or abov.source like '%I%')
 and    at.transaction_name = :1");

ARUDB::add_query("GET_DEP_SKIPPED_PATCHES" =>
"select max(bugfix_request_id), abr_ab.bugfix_id
              from aru_bugfix_requests abr, aru_bugfixes abr_ab,
              aru_bugfix_relationships abrs
              where abrs.bugfix_id = :1
              and relation_type in (" . ARU::Const::included_direct . ", " .
                                        ARU::Const::included_indirect . ")
              and abr_ab.bugfix_id = abrs.related_bugfix_id
              and abr_ab.status_id = " . ARU::Const::checkin_on_hold . "
              and abr.bugfix_id =  abr_ab.bugfix_id
              and abr.status_id = " . ARU::Const::patch_skipped . "
              and abr.language_id = " . ARU::Const::language_US . "
              and abr.platform_id in
                          (" . ARU::Const::platform_generic . " , " .
                               ARU::Const::platform_linux64_amd . ")
              group by abr_ab.bugfix_id");

ARUDB::add_query("GET_REFERENCE_ID" =>
 "select distinct reference_id
  from isd_requests
  where request_id = :1
     and  rownum < 2 ");

ARUDB::add_query("GET_DEP_SKIPPED_PATCH_DO" =>
"select max(apov.object_version_id)
               from aru_patch_obj_versions apov, aru_object_versions aov,
               aru_objects ao
               where apov.bugfix_request_id = :1
               and   apov.object_version_id = aov.object_version_id
               and   aov.rcs_version = :4
               and   ao.object_id = aov.object_id
               and   ao.object_location = :2
               and   ao.object_name = :3");


ARUDB::add_query("GET_SRC_LIST_FOR_TXN" =>
"select ao.object_name
 from   aru_objects ao, aru_bugfix_object_versions abov, aru_transactions at
 where  ao.object_id = abov.object_id
 and    abov.bugfix_id = at.bugfix_id
 and    (abov.source like 'D%' or abov.source like '%I%')
 and    at.transaction_name = :1");

ARUDB::add_query("GET_DEP_SKIPPED_PATCHES" =>
"select max(bugfix_request_id), abr_ab.bugfix_id
              from aru_bugfix_requests abr, aru_bugfixes abr_ab,
              aru_bugfix_relationships abrs
              where abrs.bugfix_id = :1
              and relation_type in (" . ARU::Const::included_direct . ", " .
                                        ARU::Const::included_indirect . ")
              and abr_ab.bugfix_id = abrs.related_bugfix_id
              and abr_ab.status_id = " . ARU::Const::checkin_on_hold . "
              and abr.bugfix_id =  abr_ab.bugfix_id
              and abr.status_id = " . ARU::Const::patch_skipped . "
              and abr.language_id = " . ARU::Const::language_US . "
              and abr.platform_id in
                          (" . ARU::Const::platform_generic . " , " .
                               ARU::Const::platform_linux64_amd . ")
              group by abr_ab.bugfix_id");

ARUDB::add_query("GET_DEP_SKIPPED_PATCH_DO" =>
"select max(apov.object_version_id)
               from aru_patch_obj_versions apov, aru_object_versions aov,
               aru_objects ao
               where apov.bugfix_request_id = :1
               and   apov.object_version_id = aov.object_version_id
               and   aov.rcs_version = :4
               and   ao.object_id = aov.object_id
               and   ao.object_location = :2
               and   ao.object_name = :3");

ARUDB::add_query("CHECK_IS_VIEW_IN_USE" =>
"select count(1)
from  isd_requests ir, isd_request_parameters irp
where irp.param_name = 'st_apf_build'
 and  irp.param_value like :1
 and  ir.request_id = irp.request_id
 and  ir.status_code not in (". ISD::Const::isd_request_stat_succ . "," .
                           ISD::Const::isd_request_stat_fail . "," .
                           ISD::Const::isd_request_stat_abtd . ")");

ARUDB::add_query("GET_FUSION_LOG_REQUESTS" =>
"select distinct ir.request_id
from  isd_requests ir, isd_request_parameters irp
where ir.grid_id in (:1 , :2)
 and  irp.request_id = ir.request_id
 and  irp.param_name = :3
 and  irp.param_value = :4");

ARUDB::add_query("GET_ISD_PARAM_VALUE" =>
"select max(param_value)
from   isd_request_parameters
where  request_id = :1
and    param_name = :2 ");

ARUDB::add_query("GET_GRID_HOSTS" =>
"select ah.host_id, ah.host_name
 from  aru_hosts ah , aru_file_locations afl, apf_instances ai
 where ai.grid_id = :1
 and   afl.location_id = ai.location_id
 and   ah.host_id = afl.host_id");

ARUDB::add_query("GET_ABRH_SQL_COMMENT" =>
"select abrh.comments
  from aru_bugfix_request_history abrh,
       (select max(bugfix_request_history_id) bugfix_request_history_id,
               bugfix_request_id
          from aru_bugfix_request_history
         where bugfix_request_id = :1
           and status_id = 5
         group by bugfix_request_id) abrh1
 where abrh.bugfix_request_id = abrh1.bugfix_request_id
   and comments like 'sql_auto_release%'
   and abrh.bugfix_request_history_id > abrh1.bugfix_request_history_id");

ARUDB::add_query(GET_LABEL =>
"select aprl.label_id, aprl.label_name
from aru_product_release_labels aprl, aru_product_releases apr
where aprl.product_release_id = apr.product_release_id
and apr.product_id = :1
and apr.release_id = :2
and aprl.platform_id = :3");

ARUDB::add_query("GET_BLR_FROM_PSE" =>
"select distinct  backport_bug
from  aru_backport_requests
where base_bug = :1
and   version_id = :2
and   request_type in (:3 , :4)");

ARUDB::add_query("GET_BLR_FROM_PSE_STATUS" =>
"select distinct  backport_bug
from  aru_backport_requests
where base_bug = :1
and   version_id = :2
and   request_type in (:3 , :4)
and   status_id  = :5");

ARUDB::add_query("GET_BUG_DET_FROM_BACKPORT_REQ" =>
" select distinct abr.base_bug, abr.version_id,
    abr.platform_id, acpr.release_version
    from aru_backport_requests abr, aru_cum_patch_releases acpr
   where abr.backport_bug = :1
    and  abr.request_type = :2
    and  acpr.release_id = abr.version_id");

ARUDB::add_query("GET_BUG_DET_FROM_BACKPORT_REQUESTS" =>
" select distinct abr.base_bug, abr.version_id,
    abr.platform_id
    from aru_backport_requests abr
   where abr.backport_bug = :1
    and  abr.request_type = :2");

ARUDB::add_query("GET_ARU_NO_FROM_PSE" =>
" select max(abr.bugfix_request_id)
  from   aru_bugfix_requests abr, aru_backport_bugs abb
  where  abb.backport_bug = :1
   and   abb.backport_bug_type =  ".ISD::Const::st_pse . "
   and   abr.bugfix_request_id = abb.bugfix_request_id");

ARUDB::add_query("GET_PSE_ISD_REQUEST" =>
" select max(request_id)
    from isd_requests
   where reference_id = :1
   order by request_id ");

ARUDB::add_query("GET_APF_REQ_DETAILS" =>
" select request_type
    from apf_request_statuses
   where isd_request_id = :1");

ARUDB::add_query("GET_ARU_UPDATED_DATE" =>
" select to_char(last_updated_date, 'YYYYMMDD')
    from aru_bugfix_requests
   where bugfix_request_id = :1");

ARUDB::add_query(GET_BUGFIX_ID_WITHOUT_RELEASE=>
                  "select   bugfix_id
                    from     aru_bugfixes
                    where    bugfix_name  = :1");

ARUDB::add_query(GET_BUGFIX_ID_EXISTS=>
                  "select   count(*)
                    from     aru_bugfixes
                    where    bugfix_name  = :1");

ARUDB::add_query(GET_BUGFIX_ID_FROM_NAME=>
                 "select   bugfix_id
                    from     aru_bugfixes
                    where    bugfix_name  = :1 and
                             release_id   = :2 ");
ARUDB::add_query(GET_PRODUCT_ID_P4FA=>
                 "select  product_id
                    from     aru_products
                    where   product_name = :1");

ARUDB::add_query(GET_RELEASE_NAME=>
                 "select  RELEASE_NAME
                    from     aru_releases
                    where   release_long_name = :1");

ARUDB::add_query(GET_RELATION_EXISTS=>
                 "select  'EXISTS'
                    from     aru_bugfix_relationships
                    where   bugfix_id = :1 and
                            related_bugfix_id = :2");

ARUDB::add_query("GET_INSTALLTEST_SUBMIT_USER" =>
" select au.user_name
    from aru_users au , isd_requests ir
    where au.user_id = ir.user_id
    and ir.request_id = :1
    and ir.request_type_code = :2");

ARUDB::add_query("GET_SERIES_FROM_TRACKING_BUG" =>
"select acps.series_name
    from aru_cum_patch_series acps, aru_cum_patch_releases acpr
    where acps.series_id = acpr.series_id
    and acpr.tracking_bug = :1");

ARUDB::add_query("IS_BACKPORT_AUTO_APPROVED" =>
"select substr(request_params,2,1) from apf_build_requests
where request_id = (select max(request_id) from
apf_build_requests where backport_bug = :1)");

ARUDB::add_query("IS_PATCH_UPLOADED" =>
" select count(1)
  from   aru_bugfix_requests
  where  bugfix_request_id = :1
   and   status_id = ".ARU::Const::patch_ftped_support);

ARUDB::add_query("GET_SERIES_FROM_TRACKING_BUG" =>
"select acps.series_name
    from aru_cum_patch_series acps, aru_cum_patch_releases acpr
    where acps.series_id = acpr.series_id
    and acpr.tracking_bug = :1");

ARUDB::add_query("GET_SERIES_ID_FROM_TRACKING_BUG" =>
"select acps.series_id
    from aru_cum_patch_series acps, aru_cum_patch_releases acpr
    where acpr.tracking_bug = :1
    and acps.series_id = acpr.series_id");

ARUDB::add_query("GET_SERIES_ID_FROM_LABEL" =>
"select acs.series_id
    from   aru_cum_patch_series acs , aru_cum_patch_releases  acr
    where  acr.release_label = :1
    and acs.series_id = acr.series_id");

ARUDB::add_query("GET_SERIES_ID_FROM_REQUESTS" =>
"select distinct acps.series_id from
    aru_cum_patch_series acps, aru_cum_patch_releases acpr,
    isd_request_parameters irp, isd_requests ir
    where trunc(ir.creation_date) >= trunc(sysdate - 60)
    and irp.request_id = ir.request_id
    and irp.param_value like '%' || :1 || '%'
    and acpr.tracking_bug = ir.reference_id
    and acps.series_id = acpr.series_id");

#
# Given a parameter, get the respective CPM series id.
# The parameter can be any of the following:
# 1) CPM tracking bug in aru_cum_patch_releases table
# 2) CPM tracking bug in aru_cum_patch_release_params table
# 3) ISD Request ID
# 4) PSE number
#
ARUDB::add_query("GET_CPM_SERIES_ID" =>
"select distinct acps.series_id
from   aru_cum_patch_series acps, aru_cum_patch_releases acpr
where  acps.series_id = acpr.series_id
and    acpr.tracking_bug = :1
union
select distinct acps.series_id
from   aru_cum_patch_series acps
,      aru_cum_patch_releases acpr
,      aru_cum_patch_release_params acprp
where  acps.series_id = acpr.series_id
and    acpr.release_id = acprp.release_id
and    acprp.parameter_value = :1
union
select distinct acps.series_id
from   aru_cum_patch_series acps
,      aru_cum_patch_releases acpr
,      aru_cum_patch_release_params acprp
,      isd_requests ir
,      bugdb_rpthead_v rpt
where  acps.series_id = acpr.series_id
and    ir.reference_id = rpt.rptno
and    (rpt.base_rptno = acpr.tracking_bug or
        (to_char(rpt.base_rptno) = acprp.parameter_value and
         acprp.release_id = acpr.release_id))
and    ir.request_id = :1
union
select distinct acps.series_id
from   aru_cum_patch_series acps
,      aru_cum_patch_releases acpr
,      aru_cum_patch_release_params acprp
,      bugdb_rpthead_v rpt
where  acps.series_id = acpr.series_id
and    (rpt.base_rptno = acpr.tracking_bug or
        (to_char(rpt.base_rptno) = acprp.parameter_value and
         acprp.release_id = acpr.release_id))
and    rpt.rptno = :1");


ARUDB::add_query(GET_APF_TRACKING_GROUP_VALUE =>
"select rtg.VALUE, rtg.tracking_group_value_id
    FROM bugdb_tracking_groups_v tg,
    bugdb_rpthead_tracking_gps_v rtg
    where rtg.rptno =  :1
    and rtg.TRACKING_GROUP_ID = tg.ID
    and tg.name = :2");

ARUDB::add_query("GET_TRACKING_GROUP_VALUE" =>
"select brtg.value
    from     bugdb_rpthead_tracking_gps_v brtg,
    bugdb_tracking_groups_v btg
    where    brtg.rptno                 =  :1
    and      brtg.tracking_group_id     =  btg.id
    and      btg.name like 'P4FA Label Inclusion%'
    and      btg.type = 'F'
    and      brtg.value like 'PATCHES4FA%'");

ARUDB::add_query("GET_FARM_RETRY_COUNT" =>
"select count(*) from apf_build_request_history
    where request_type = 95040
    and request_id = (select max(request_id)
                   from apf_build_requests
                   where backport_bug = :1)");

ARUDB::add_query("LAST_REQ_STATUS" =>
" select status_code from isd_requests
where reference_id=:1
order by request_id desc");

ARUDB::add_query("GET_REQUEST_TYPE_CODE" =>
"select request_type_code
    from isd_requests
    where request_id = :1 ");

ARUDB::add_query("GET_RETRY_REQ_COUNT" =>
"select count(1)
   from isd_request_history
  where request_id = :1
    and status_code = :2");

ARUDB::add_query("GET_PREV_ISD_REQ_ID" =>
" select max(request_id)
    from isd_requests
   where reference_id = (select reference_id
                           from isd_requests
                        where request_id = :1)
    and  request_type_code = :2");

ARUDB::add_query("GET_PREV_ISD_REQ_PARAMS" =>
" select ir.request_id, irp.param_value
    from isd_requests ir,
         isd_request_parameters irp
   where ir.reference_id = (select reference_id
                              from isd_requests
                             where request_id = :1)
    and  ir.request_type_code = :2
    and irp.request_id = ir.request_id
    and irp.param_name = :3
  order by 1 desc");

ARUDB::add_query("GET_MAX_REQ_ID" =>
" select max(request_id)
    from isd_requests
   where reference_id =  :1
    and  request_type_code = :2");

ARUDB::add_query("GET_BUGFIX_ARU_TXN_INFO" =>
"select abr.bugfix_request_id, ab.bugfix_id,
        at.transaction_id, at.transaction_name,
        ab.product_id
  from  aru_bugfix_requests abr, aru_bugfixes ab, aru_transactions at
 where  ab.bugfix_id = abr.bugfix_id
   and  abr.bugfix_request_id = at.bugfix_request_id
   and  ab.bugfix_rptno = :1
   and  ab.release_id = :2
   and  abr.platform_id = :3
   and  abr.status_id <> ". ARU::Const::patch_deleted);

ARUDB::add_query("WAS_MERGEREQ_SUBMITTED" =>
"select count(*) from apf_build_request_history where
  request_type = " . ISD::Const::st_apf_mergereq .
  "and request_id in (select request_id from apf_build_requests
   where backport_bug = :1)");

ARUDB::add_query("GET_OUI_INFO" =>
"select ao1.object_name,ao1.object_location
  from aru_label_dependencies ald, aru_objects ao , aru_objects ao1,
       aru_product_release_labels aprl, aru_product_releases apr,
       aru_products ap, aru_releases ar,aru_product_groups apg
    where ao.object_name=:1
      and ao.object_location=:2
      and ald.b_used_by_a=ao.object_id
      and ao1.object_id=ald.a_uses_b
      and aprl.label_id=ald.label_id
      and aprl.product_release_id=apr.product_release_id
      and ald.label_id=:3
      and apr.release_id=ar.release_id
      and ap.product_id=apr.product_id
      and ap.product_id = apg.child_product_id
      and apg.parent_product_id=:4
      and ald.label_dependency=:5 ");

ARUDB::add_query("GET_TXN_SRC_DOS" =>
"select ao.object_location || '/' || ao.object_name
   from aru_patch_obj_versions apov, aru_object_versions aov, aru_objects ao
  where apov.object_version_id = aov.object_version_id
    and aov.object_id = ao.object_id
    and apov.bugfix_request_id = :1");

ARUDB::add_query(GET_PRODUCT_REL_ID=>
                 "select ab.release_id, ab.product_id, count(*) from
                  aru_bugfixes ab, aru_bugfix_requests abr,
                  aru_bugfix_request_objects abro, aru_objects ao
                  where ab.bugfix_id = abr.bugfix_id and
                        abr.bugfix_request_id = abro.bugfix_request_id and
                        abro.object_id = ao.object_id and
                        ao.object_name like :1"."||'%'
                     and abro.oui_object_version = :2
                 group by ab.release_id, ab.product_id order by 3 desc");

ARUDB::add_query(GET_BUGFIX_ID_FROM_ARUFILES=>
    "select abr.bugfix_id, abr.release_id
    from aru_patch_files apf, aru_files af, aru_bugfix_requests abr
    where
    apf.file_id = af.file_id and
    abr.bugfix_request_id = apf.bugfix_request_id and
    af.file_name = :1");

ARUDB::add_query(GET_BUGFIX_COUNT_FROM_ARUFILES=>
    "select count(*)
    from aru_patch_files apf, aru_files af, aru_bugfix_requests abr
    where
    apf.file_id = af.file_id and
    abr.bugfix_request_id = apf.bugfix_request_id and
    af.file_name = :1");

ARUDB::add_query("GET_ONHOLD_ARU" =>
"select bug_number, bugfix_request_id
   from aru_bugfix_requests
  where bug_number = :1
    and release_id = :2
    and platform_id in (".
    ARU::Const::platform_generic .",".
    ARU::Const::platform_linux64_amd .")
    and status_id = ". ARU::Const::patch_on_hold);

ARUDB::add_query(GET_BRANCH_BASE_REL =>
"select release_id from aru_releases
  where release_name = :1
   and  release_id like '". ARU::Const::applications_fusion_rel_exp . "%'");

ARUDB::add_query(GET_PROD_REL_COUNT =>
"select count(1)
  from  aru_product_releases
 where  release_id = :1");

ARUDB::add_query("IS_CPCT_RELEASE" =>
"select count(*) from aru_cum_patch_releases
 where aru_release_id = :1");

ARUDB::add_query("GET_BUGFIX_ABSTRACT" =>
"select abstract from aru_bugfixes
 where bugfix_rptno = :1 and release_id=:2");

ARUDB::add_query("IS_DBPSU_EXADATA_CI_EXISTS" =>
"select count(*) from aru_backport_requests abr, bugdb_rpthead_v rh
  where abr.backport_bug = rh.rptno and abr.base_bug = :1
  and rh.status in (35,38,74,75,88,90,93,80)
  and request_type = 45054 and version_id in
  (select acpr.release_id from aru_cum_patch_releases acpr,
   aru_cum_patch_series acps where acpr.series_id = acps.series_id
   and family_name like :2 and base_release_id = :3)");

ARUDB::add_query("GET_BACKPORT_SEVERITY" =>
"select cs_priority from bugdb_rpthead_v where rptno = :1");

ARUDB::add_query("GET_FUSION_NON_OBS_DEP_PATCHES" =>
"select ab2.bugfix_rptno, ab2.release_id, ab2.status_id,
 ab2.bugfix_id
 from   aru_bugfix_relationships abr, aru_bugfixes ab1,
        aru_bugfixes ab2
 where  ab1.bugfix_rptno = :1
  and   ab1.release_id = :2
  and   ab1.bugfix_id = abr.related_bugfix_id
  and   abr.relation_type in (" . ARU::Const::prereq_direct .
        "," . ARU::Const::included_direct .
        "," . ARU::Const::included_indirect . ")
  and   ab2.bugfix_id = abr.bugfix_id
  and   ab2.status_id <> ". ARU::Const::checkin_obsoleted ."
  and   ab2.release_id = ab1.release_id
  order by ab2.bugfix_rptno");

ARUDB::add_query("GET_FA_OBS_LST_FOR_CRON_ALERT" =>
 "select ab.bugfix_id,ab.bugfix_rptno,ab.release_id
    from aru_bugfixes ab
    where ab.release_id like '". ARU::Const::applications_fusion_rel_exp . "%'
      and ab.obsoleted_date >= (sysdate - 60) ");

ARUDB::add_query("GET_FA_PATCH_TYPE" =>
 "select ab.patch_type, aba.attribute_value
  from aru_bugfixes ab , aru_bugfix_attributes aba
 where ab.bugfix_id=:1
 and ab.bugfix_id=aba.bugfix_id
 and aba.attribute_type=". ARU::Const::group_patch_types);

ARUDB::add_query("GET_REGRESSED_BLR_NUMBER" =>
"select max (a.rptno)
    from bugdb_rpthead_v a, bugdb_rpthead_v b
    where b.rptno = :1
    and a.utility_version = b.utility_version
    and a.generic_or_port_specific = b.generic_or_port_specific
    and a.base_rptno = b.base_rptno
    and a.status in (55, 59)");

ARUDB::add_query("CHECK_IF_REPLACEMENT_PATCH" =>
"select 1, ab.bugfix_rptno
    from apf_patch_supersedures aps, aru_bugfixes ab
    where aps.base_bugfix = ab.bugfix_id
    and ab.release_id = :1
    and aps.superseding_bug = :2
    and aps.status_id <> ".ARU::Const::patch_skipped);

ARUDB::add_query("GET_REL_SKIPPED_PATCHES" =>
"select ab.bugfix_rptno, aps.base_bugfix
   from apf_patch_supersedures aps, aru_bugfixes ab
  where aps.base_bugfix = ab.bugfix_id
    and aps.superseding_bug = :1
    and aps.status_id = ". ARU::Const::patch_skipped ."
    and ab.release_id = :2");

ARUDB::add_query("GET_FA_HP_ENABLED_EXTNS" =>
"select value
    from aru_parameters
    where name = '". ARU::Const::fa_hp_enabled_extns ."'" );

ARUDB::add_query("GET_PREV_ADE_VER_IN_ARU" =>
"select
max(substr(abov.rcs_version,0,(instr(abov.rcs_version,'/',-1)))) ||
max(to_number(substr(abov.rcs_version,(instr(abov.rcs_version,'/',-1)+1))))
   from aru_objects ao, aru_bugfix_object_versions abov, aru_bugfixes ab,
        aru_bugfix_requests abr
  where ao.object_id = abov.object_id
  and abov.bugfix_id = ab.bugfix_id
  and abr.bugfix_id = ab.bugfix_id
  and ao.object_name = :1
  and ao.object_location = :2
  and ab.release_id = :3
  and abov.rcs_version <> :4
  and substr(abov.rcs_version,0,(instr(abov.rcs_version,'/',-1))) <= :5
  and to_number(substr(abov.rcs_version,(instr(abov.rcs_version,'/',-1)+1)))<:6
  and abr.status_id not in ( " . ARU::Const::patch_deleted . "," .
                             ARU::Const::patch_skipped . "," .
                             ARU::Const::patch_denied_no_aru_patch . ")
   and abr.platform_id in (" . ARU::Const::platform_generic . "," .
    ARU::Const::platform_linux64_amd . ")
   group by ao.object_name, ao.object_location");

ARUDB::add_query("GET_NLS_PATCH_VERSION" =>
"select nvl(count(abr.bugfix_request_id),0)+1
from aru_bugfixes ab, aru_bugfix_requests abr, aru_bugfix_request_history abrh
where ab.bugfix_id= :1
and ab.bugfix_id=abr.bugfix_id
and abr.platform_id = :2
and abr.language_id = :3
and abr.bugfix_request_id=abrh.bugfix_request_id
and abrh.status_id in(" . ARU::Const::patch_ftped_support . "," .
ARU::Const::patch_ftped_dev . ")");

ARUDB::add_query("GET_OUTOFMEMORY_FAILURES" =>
"select ir1.request_id , ir1.user_id, ir1.error_message
    from isd_requests ir1
    where ir1.grid_id in ('APF_FUSION_PBUILD_GRID_NEW', ''FUSIONAPPS_US_GRID')
    and ir1.status_code = " . ISD::Const::isd_request_stat_fail ."
    and ir1.error_message like '%OutOfMemory%'
    and ir1.creation_date > sysdate-1
    and ir1.request_id = (select max(ir2.request_id) from isd_requests ir2
                          where ir2.reference_id=ir1.reference_id)");

ARUDB::add_query("GET_FAILED_CHECKIN_COMMIT" =>
"select ir1.request_id , ir1.user_id, ir1.error_message
    from isd_requests ir1
    where ir1.grid_id in ('APF_FUSION_PBUILD_GRID_NEW', ''FUSIONAPPS_US_GRID')
    and ir1.status_code = " . ISD::Const::isd_request_stat_fail ."
    and ir1.error_message like '%Log is not generated by Checkin Commit%'
    and ir1.creation_date > sysdate-1
    and ir1.request_id = (select max(ir2.request_id) from isd_requests ir2
                          where ir2.reference_id=ir1.reference_id)");

ARUDB::add_query("GET_DESCRIBETRANS_FAILURES" =>
"select ir1.request_id , ir1.user_id, ir1.error_message
    from isd_requests ir1
    where ir1.grid_id in ('APF_FUSION_PBUILD_GRID_NEW', ''FUSIONAPPS_US_GRID')
    and ir1.status_code = " . ISD::Const::isd_request_stat_fail ."
    and ir1.error_message like '%describetrans failed for txn%'
    and ir1.creation_date > sysdate-1
    and ir1.request_id = (select max(ir2.request_id) from isd_requests ir2
                          where ir2.reference_id=ir1.reference_id)");

ARUDB::add_query("GET_PERMISSION_ISSUE_FAILURES" =>
                     "select ir1.request_id , ir1.user_id, ir1.error_message
    from isd_requests ir1
    where ir1.grid_id in ('APF_FUSION_PBUILD_GRID_NEW', ''FUSIONAPPS_US_GRID')
    and ir1.status_code = " . ISD::Const::isd_request_stat_fail ."
    and ir1.error_message like 'Port Platform Specific Files: One or more ' ||
    'files failed to compile, check log files for more details: ' ||
    'ade ERROR: Could not create view storage dir%Permission denied'
    and ir1.creation_date > sysdate-1
    and ir1.request_id = (select max(ir2.request_id) from isd_requests ir2
                          where ir2.reference_id=ir1.reference_id)");

ARUDB::add_query("GET_BUG_DETAILS_FROM_BUGDB" =>
"select status, product_id, cs_priority
    from  bugdb_rpthead_v
    where rptno = :1");

ARUDB::add_query("IS_PLATFORM_PSE_EXITS" =>
"select count(rptno)
   from bugdb_rpthead_v
  where base_rptno = :1
   and  utility_version = :2
   and  generic_or_port_specific = 'O'
   and  portid = :3
   and  status not in (59, 36, 32, 92, 96)");

ARUDB::add_query("GET_BUGFIX_ID_FROM_ARU"=>
"select bugfix_id
 from  aru_bugfix_requests
  where bugfix_request_id =:1");

ARUDB::add_query("GET_BASEBUG_FOR_PSE"=>
"select nvl(base_rptno,rptno)
    from  bugdb_rpthead_v
    where rptno = :1");

ARUDB::add_query("GET_BUGDB_FAILURES" =>
    "select ir1.request_id , ir1.user_id, ir1.error_message
    from isd_requests ir1
    where ir1.grid_id in ('APF_FUSION_PBUILD_GRID_NEW', 'FUSIONAPPS_US_GRID')
    and ir1.status_code = " . ISD::Const::isd_request_stat_fail ."
    and ir1.error_message like '%Unable to connect to bug database%'
    and ir1.last_updated_date >= sysdate-2
    and ir1.request_id = (select max(ir2.request_id) from isd_requests ir2
                          where ir2.reference_id=ir1.reference_id)");

ARUDB::add_query("GET_CPM_TESTFLOW" =>
"select acpsp.parameter_value, acpr.release_id
 from   aru_cum_patch_series_params acpsp
 ,      aru_bugfix_requests abr
 ,      aru_cum_patch_releases acpr
 where  abr.bug_number = acpr.tracking_bug
 and    acpr.series_id = acpsp.series_id
 and    abr.bugfix_request_id = :1
 and    acpsp.parameter_name = :2");

ARUDB::add_query("GET_CMDS_BY_TESTFLOW" =>
"select ats.testsuite_name, ats.command, ats.testtype
 from   apf_testflow_groups atfg
 ,      apf_testsuites ats
 where  atfg.testflow_id = :1
 and    atfg.testsuite_id = ats.testsuite_id
 order by atfg.test_sequence");

ARUDB::add_query("GET_RECOM_COREQS" =>
"select related_bugfix_id, related_bug_number, relation_type
    from aru_bugfix_relationships
    where bugfix_id = :1
    and relation_type in (" . ARU::Const::fusion_coreq_recommended . ", " .
                              ARU::Const::fusion_coreq_reco_indirect . ")
");

ARUDB::add_query("GET_REQD_COREQS" =>
"select related_bugfix_id, related_bug_number, relation_type
    from aru_bugfix_relationships
    where bugfix_id = :1
    and relation_type in (" . ARU::Const::fusion_coreq_required . ", " .
                              ARU::Const::fusion_coreq_reqd_indirect . ")
");

ARUDB::add_query('TXN_CONTAINS_NEW_FILES' =>
"select count(at.transaction_id) from aru_transactions at ,
 aru_transaction_attributes ata
 where at.transaction_id = ata.transaction_id
 and at.transaction_name = :1
 and ata.attribute_name = 'NEW_FILES'");

ARUDB::add_query('GET_PREREQ_LIST' =>
"select ab2.bugfix_rptno from aru_bugfixes ab1 , aru_bugfixes ab2 ,
aru_bugfix_relationships abr
where ab1.bugfix_rptno = :1
and ab1.release_id = :2
and ab1.bugfix_id = abr.bugfix_id
and abr.relation_type = ". ARU::Const::prereq_direct ."
and ab2.bugfix_id = abr.related_bugfix_id");

ARUDB::add_query('IS_BUG_IN_SB_CHAIN' =>
"select 1 from aru_bugfixes ab1 , aru_bugfixes ab2 ,
aru_bugfix_relationships abr
where ab1.bugfix_rptno = :1
and ab1.release_id = :2
and ab1.bugfix_id = abr.bugfix_id
and abr.relation_type in (". ARU::Const::included_direct. ",".
ARU::Const::included_indirect . ")
and ab2.bugfix_id = abr.related_bugfix_id
and ab2.bugfix_rptno = :3
and ab1.release_id = :2");

ARUDB::add_query("GET_CODELINE_REQUEST" =>
"select codeline_request_id, backport_bug,status_id
from aru_cum_codeline_requests
where base_bug = :1
and  release_id = :2");


ARUDB::add_query("GET_CODELINE_REQUEST_ID" =>
"select codeline_request_id
from aru_cum_codeline_requests
where backport_bug in (:1)");

ARUDB::add_query("GET_PREVIOUS_FARM_PARAMS" =>
"select param_value from isd_request_parameters where request_id in (
  select request_id from isd_requests
    where reference_id = :1
    and request_type_code = 80170)
  order by request_id desc");

ARUDB::add_query("GET_FARM_REQ_PARAMS" =>
"select comments from apf_build_request_history
where request_type = 95370
and request_id = (select max(request_id)
from apf_build_requests where backport_bug = :1)");

ARUDB::add_query('WAS_TRANSACTION_CLOSED' =>
"select count(*) from apf_build_request_history
   where request_type = 95390
   and request_id = (select max(request_id) from
   apf_build_requests where backport_bug = :1)");

ARUDB::add_query('GET_WORKER_HOST' =>
"select param_value from isd_request_parameters 
      where param_name = 'worker_host' 
      and request_id = ( select max(request_id) 
                     from isd_requests 
                     where request_type_code = 80230 
                     and reference_id = :1)");

ARUDB::add_query('GET_BUILD_FILE_LOC' =>
"select comments from apf_build_request_history
   where request_type = 95380
   and request_id = (select max(request_id) from
   apf_build_requests where backport_bug = :1)");

ARUDB::add_query('GET_LATEST_FARMJOB_LRGLIST' =>
"select comments from apf_build_request_history
   where request_type = 95110
   and request_id = (select max(request_id) from
   apf_build_requests where backport_bug = :1)
   and rownum = 1
   order by request_history_id desc");


 ARUDB::add_query("GET_MLR_LABEL_PLATFORM" =>
  "select aprl.platform_id
    from aru_product_release_labels aprl,aru_product_releases apr,
     aru_products ap
    where apr.product_id = ap.product_id
    and apr.product_release_id = aprl.product_release_id
    and aprl.label_name = :1
    and apr.release_id = :2
    and ap.product_id in (9480, 9481)");

 ARUDB::add_query("GET_DATED_LABEL" =>
  "select * from
    (select irp.param_value from isd_requests ir, isd_request_parameters irp
     where ir.reference_id = :1 and irp.request_id = ir.request_id and
     irp.param_value like '%TYPE:dated!%' and irp.param_value like '%LABEL:%'
     order by ir.last_updated_date desc) where rownum = 1");

 ARUDB::add_query("GET_FA_PORT_SPECIFIC_INCLUDED_TXNS" =>
  "select at.transaction_name, ao.object_id, ao.object_name,
          ao.object_location, abov.rcs_version,
          ao.filetype_id, af.filetype_name, af.requires_porting,
          af.source_extension
      from aru_bugfixes ab, aru_bugfix_object_versions abov, aru_objects ao ,
           aru_bugfix_requests abr , aru_transactions at , aru_filetypes af
    where abov.object_id = ao.object_id
       and abov.bugfix_id = ab.bugfix_id
       and ab.bugfix_rptno in (select related_bug_number
                               from aru_bugfix_relationships abrl,
                                    aru_bugfixes ab
                             where abrl.bugfix_id = ab.bugfix_id
                               and ab.bugfix_rptno = :1
                               and ab.release_id = :2
                               and abrl.relation_type = " .
                                 ARU::Const::included_direct .
                               ")".
     "and ab.release_id = :2
     and abr.bugfix_id=ab.bugfix_id
     and at.bugfix_request_id=abr.bugfix_request_id
     and ao.filetype_id=af.filetype_id
     and af.requires_porting = 'Y'");

ARUDB::add_query("GET_ALL_PSES" =>
  "select abr.backport_request_id, abr.status_id, abr.severity,
          abr.backport_bug, abr.requested_by
    from aru_backport_requests abr, aru_backport_requests abr1
    where abr.base_bug = abr1.base_bug and abr1.backport_bug = :2
    and abr.request_type =" . ARU::Const::backport_pse .
    "and abr.status_id in (" .
      ARU::Const::backport_request_pending . "," .
      ARU::Const::backport_request_bug_filed . ")
    and abr.version_id = abr1.version_id
    and abr.base_bug = :1");

ARUDB::add_query(GET_STATUS_ASSIGNEE =>
" select status, programmer
   from  bugdb_rpthead_v
   where rptno = :1");

ARUDB::add_query(GET_DUPLICATE_PSES =>
"select rptno
 from   bugdb_rpthead_v
 where  base_rptno = :1
 and    utility_version = :2
 and    portid = :3
 and    status NOT IN (53,55,59)
 and    GENERIC_OR_PORT_SPECIFIC = 'O'");

ARUDB::add_query(IGNORE_NEW_FILES_REQUEST =>
  "select count(*) from apf_build_request_history
    where request_type = 95430
    and request_id = (select max(request_id)
                   from apf_build_requests
                   where backport_bug = :1)");

ARUDB::add_query(GET_BUNDLE_PATCH_DETAILS_FROM_LABEL =>
  "select  from_label_name, bundle_patch_type, tracking_bug, pse_bug,
           bp_component_version, aru_product_id, cpm_release_id, bugfix_request_id,
           patch_current_status, patch_current_stage, patch_start_stage,
           patch_end_stage,start_time, end_time, remarks, created_by, updated_by
    from apf_bundles
    where to_label_name = :1");

ARUDB::add_query(GET_LAST_RELEASED_BUNDLE_BY_REL_PF =>
"with maxrel as
     (select maxdate from
         (select ab1.released_date as maxdate
           from aru_bugfixes ab1,aru_bugfix_attributes aba
              where ab1.release_id = :1
                and ab1.product_id=:2
                and ab1.patch_type = ". ARU::Const::ptype_bundle ."
                and ab1.bugfix_id=aba.bugfix_id
                and aba.attribute_type= ". ARU::Const::group_patch_types ."
                and aba.attribute_value not like '%aoo'
                and ab1.released_date is not null
                order by ab1.released_date desc)
         where rownum <= 2
       )
 select ab.bugfix_id, ab.bugfix_rptno, ab.abstract
       from aru_bugfixes ab , maxrel
       where ab.release_id = :1
         and ab.product_id=:2
         and ab.patch_type = ". ARU::Const::ptype_bundle ."
         and ab.released_date in (maxrel.maxdate)
 order by ab.released_date desc");

ARUDB::add_query(IS_BUNDLE_INC_SNOWBALL =>
"select 1
   from aru_bugfix_relationships abr1, aru_bugfixes ab1
  where abr1.bugfix_id = ab1.bugfix_id
    and ab1.bugfix_rptno = :1
    and abr1.relation_type = ".ARU::Const::included_direct ."
    and abr1.related_bug_number = :2
    and ab1.status_id <> ".ARU::Const::checkin_obsoleted);

ARUDB::add_query(CMP_BUNDLE_PATCH =>
"select abr1.related_bug_number, aba2.attribute_value
   from aru_bugfixes ab1, aru_bugfix_relationships abr1,
        aru_bugfixes ab2, aru_bugfix_attributes aba2
  where ab1.bugfix_id = abr1.bugfix_id
    and abr1.related_bugfix_id = ab2.bugfix_id
    and ab2.bugfix_id = aba2.bugfix_id
    and ab1.bugfix_rptno = :1
    and ab1.release_id = :3
    and abr1.relation_type in (". ARU::Const::included_direct .",
                               ".ARU::Const::included_indirect .")
    and abr1.related_bugfix_id not in (select abr2.related_bugfix_id
                                         from aru_bugfix_relationships abr2,
                                              aru_bugfixes ab3
                                        where abr2.bugfix_id = ab3.bugfix_id
                                          and ab3.bugfix_rptno = :2
                                          and abr2.relation_type in (".
                                              ARU::Const::included_direct ."
                                            , ".
                                              ARU::Const::included_indirect
                                             .")
                                          and ab3.status_id <> ".
                                              ARU::Const::checkin_obsoleted
                                              .")
    and ab2.status_id <> ". ARU::Const::checkin_obsoleted ."
    and aba2.attribute_type = ".ARU::Const::fusion_hotpatch_mode."
    order by aba2.attribute_value");

ARUDB::add_query(GET_FA_REL_ID_BY_VERSION =>
"select max(release_id) from aru_releases ".
                      "where release_name = :1 ".
                      "and release_id like '".
                 ARU::Const::applications_fusion_rel_exp."%'");

ARUDB::add_query(GET_BUG_BY_TEST_NAME =>
"select rptno,test_name from bugdb_rpthead_v
where test_name=:1
and product_id=:2
and category=:3
and utility_version=:4");

ARUDB::add_query(GET_EMAIL_ALERTS_DL =>
"select value,development_value
from aru_parameters where name=:1");

ARUDB::add_query(GET_ERROR_PATTERNS =>
"select err_template, err_description
from apf_error_descriptions
where gen_or_port=:1
    and patch_type = :2
    and status = 'Y'");

ARUDB::add_query(GET_P1_BUG =>
"select rptno
 from   bugdb_rpthead_v
 where  product_id = 1057
 and    subject like :1 || '%'
 and    upper(bugdb.query_bug_tag(rptno))
        like '%' || :2 || '%'
 and    rownum = 1
 order by rptno desc");

ARUDB::add_query(GET_BUG_ASSIGNMENT =>
 "
select  extractvalue(apbr.xcontent,'/rules/assignee'),
        extractvalue(apbr.xcontent,'/rules/email')
from apf_bug_assignment_rules apbr
where extractvalue(apbr.xcontent,'/rules/name') like 'BUG_ASSIGNMENT'
  and extractvalue(apbr.xcontent,'/rules/bugdb_product_id')  in (:1,'ALL')
  and extractvalue(apbr.xcontent,'/rules/component')  in (:2,'ALL')
  and extractvalue(apbr.xcontent,'/rules/sub_component')  in (:3,'ALL')
  and upper(:4) like
      upper(extractvalue(apbr.xcontent,'/rules/issue_type')) || '%'
  and extractvalue(apbr.xcontent,'/rules/utility_version')  in (:5,'ALL')
  and extractvalue(apbr.xcontent,'/rules/gen_or_port')  in (:6,'ALL')
  and extractvalue(apbr.xcontent,'/rules/platform') in (:7,'ALL')
  and existsNode(apbr.xcontent,
      '/rules/release[text() = \"ALL\" or text() = \"' || :8 || '\" ]') = 1
  and apbr.patch_type in (:9,'ALL')
  and apbr.product_id = :10
  and apbr.status = 'Y'
  and rownum = 1
order by rule_id desc
");

ARUDB::add_query(GET_P1_REASON_TG =>
 "
select  extractvalue(apbr.xcontent,'/rules/assignee'),
        extractvalue(apbr.xcontent,'/rules/p1_reason')
from apf_bug_assignment_rules apbr
where extractvalue(apbr.xcontent,'/rules/name') like 'BUG_ASSIGNMENT'
  and extractvalue(apbr.xcontent,'/rules/bugdb_product_id')  in (:1,'ALL')
  and extractvalue(apbr.xcontent,'/rules/component')  in (:2,'ALL')
  and extractvalue(apbr.xcontent,'/rules/sub_component')  in (:3,'ALL')
  and upper(:4) like
      upper(extractvalue(apbr.xcontent,'/rules/issue_type')) || '%'
  and extractvalue(apbr.xcontent,'/rules/utility_version')  in (:5,'ALL')
  and extractvalue(apbr.xcontent,'/rules/gen_or_port')  in (:6,'ALL')
  and extractvalue(apbr.xcontent,'/rules/platform') in (:7,'ALL')
  and existsNode(apbr.xcontent,
      '/rules/release[text() = \"ALL\" or text() = \"' || :8 || '\" ]') = 1
  and apbr.patch_type in (:9,'ALL')
  and apbr.product_id = :10
  and apbr.status = 'Y'
  and rownum = 1
order by rule_id desc
");

ARUDB::add_query(IS_REFRESH_TXN_REQUEST =>
  "select count(*) from apf_build_request_history
    where request_type = 95440
    and request_id = (select max(request_id)
                   from apf_build_requests
                   where backport_bug = :1)");


ARUDB::add_query(COUNT_REQS_BY_REF =>
"select count(request_id) from isd_requests
   where  reference_id =
      (select reference_id from isd_requests
        where request_id = :1)");

ARUDB::add_query(GET_CHECKIN_FILE_PROD =>
"select product_abbreviation
from aru_products where product_id =
    (select min(product_id)
     from aru_product_releases
     where release_id = :1
     and product_top is not null)");

ARUDB::add_query("GET_ISD_CHECKIN_REQUEST" =>
" select max(request_id)
    from isd_requests
   where reference_id = :1
     and request_type_code = " . ISD::Const::st_apf_request_task . "
   order by request_id ");

ARUDB::add_query("GET_PHYSICAL_GRID_ID" =>
"select distinct replace(irh.error_message,'On '), ir.grid_id,
       ah.host_name, ai.grid_id, irh.change_date
  from isd_request_history irh, isd_requests ir,
       aru_hosts ah, aru_file_locations afl, apf_instances ai
 where irh.request_id = :1
   and irh.error_message like '%On%'
   and ir.request_id = irh.request_id
   and replace(ah.host_name,'.us.oracle.com') =
                          replace(irh.error_message,'On ')
   and afl.host_id = ah.host_id
   and ai.location_id = afl.location_id
order by irh.change_date desc"
);

ARUDB::add_query(GET_FMW_REMOTE_TXN =>
"select transaction_id,transaction_name from
 (select transaction_id,transaction_name
  from aru.apf_remote_transactions
    where  backport_bug=:1
    order by creation_date desc)
 where rownum = 1");

ARUDB::add_query(IS_CD_ENABLED_RELEASE =>
  "select count(*)
     from aru_cum_patch_series_params acpsp, aru_cum_patch_releases acpr
     where acpsp.series_id = acpr.series_id
     and parameter_name = 'JIRA Project Key'
     and parameter_value = 'SECD'
     and release_version = :1");

ARUDB::add_query(GET_FMW_REMOTE_TXN_FILES =>
"select file_name,file_location
  from aru.apf_remote_transaction_files
    where  transaction_id=:1
      order by file_id");

ARUDB::add_query("GET_ALL_BACKPORT_PSES" =>
  "select abr.backport_bug, abr.severity
    from aru_backport_requests abr, aru_backport_requests abr1
    where abr.base_bug = abr1.base_bug and abr1.backport_bug = :2
    and abr.request_type =" . ARU::Const::backport_pse .
    "and abr.status_id = ".
      ARU::Const::backport_request_bug_filed .
  "  and abr.version_id = abr1.version_id
    and abr.base_bug = :1");

ARUDB::add_query("GET_ALL_BUGDB_BACKPORT_PSES" =>
"select distinct rptno, cs_priority
from bugdb_rpthead_v
where base_rptno = :1
and  aru_backport_util.pad_version(utility_version) =
    aru_backport_util.pad_version(:2)
and generic_or_port_specific = 'O'
and  status not in (53, 55, 59, 36, 32, 92, 96)");

ARUDB::add_query("GET_REL_PROD_FROM_LABEL" =>
" select distinct apr.product_id, apr.release_id
    from aru_product_releases apr,
    aru_product_release_labels aprl
   where aprl.label_id = :1
    and  apr.product_release_id = aprl.product_release_id");

ARUDB::add_query("GET_BLR_PSE_ISD_REQ" =>
"select request_id
    from isd_requests
    where reference_id = :1
    and status_code in (". ISD::Const::st_apf_preproc.",".
ISD::Const::isd_request_stat_qued.",".ISD::Const::isd_request_stat_proc.")");

ARUDB::add_query("GET_ISD_ERROR_MSG" =>
"select error_message from isd_requests where request_id = :1");

ARUDB::add_query("GET_PSE_MAX_ISD_REQ" =>
"select ir1.request_id, ir1.status_code
     from (
    select ir.request_id, ir.status_code
    from isd_requests ir
    where ir.reference_id = :1
    order by ir.last_updated_date desc) ir1
    where rownum = 1");

ARUDB::add_query("IS_REQ_FIRST_RUN" =>
"select count(1)
  from  isd_request_history
 where  request_id = :1
   and  status_code = :2");

ARUDB::add_query("IS_PSE_BACKPORT_REQ_LATEST" =>
"select count(1)
   from isd_requests
  where request_id = :1
    and last_updated_date < (select creation_date
                             from   isd_requests
                             where request_id = :2)");

ARUDB::add_query("GET_BLR_PSE_ARUS" =>
"select bugfix_request_id from aru_bugfix_requests
    where bug_number = :1
    and release_id = :2
    and status_id in (".ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query("GET_BLR_REL_PSE_ARUS" =>
"select bugfix_request_id from aru_bugfix_requests
    where bug_number = :1
    and release_id = :2
    and platform_id  = :3
    and status_id in (".ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::patch_on_hold . "," .
                        ARU::Const::patch_ftped_internal. ")");

ARUDB::add_query(GET_FMW_MERGED_BUGS =>
"select abbr.related_bug_number
from aru_backport_requests abr,
    aru_backport_bug_relationships abbr
where abr.backport_bug = :1
and abbr.backport_request_id = abr.backport_request_id
and abbr.relation_type in (".ARU::Const::fixed_direct.",".
ARU::Const::included_direct.")");

ARUDB::add_query("GET_PATCH_UPTIME_OPTION" =>
"select tracking_group_value_id
  from bugdb_rpthead_tracking_gps_v brtgv
   where   brtgv.tracking_group_id = 8546
    and    brtgv.rptno = :1 "
);

ARUDB::add_query("GET_OPATCH_ARU" =>
"select bugfix_request_id
   from aru_bugfix_requests abr,
        aru_releases ar
  where abr.bug_number = 6880880
    and abr.status_id = 22
    and abr.platform_id in (:1,2000)
    and ar.release_id = abr.release_id
    and (ar.release_name in (:2, :3)
         or ar.release_name like :4)
    and abr.product_id in (:5, :6)"
);


ARUDB::add_query("IS_ARCHIVE_ENABLED_TMPL" =>
"select max(tmpl_id)
from automation_archive_tmpls
where series_id = :1
and  platform_id = :2
and enabled = 'Y'");

ARUDB::add_query("GET_ARCHIVE_TMPL" =>
"select text
from automation_archive_tmpls
where tmpl_id = :1");

ARUDB::add_query(GET_BUGFIX_ID_ONLY_BUG =>
"select bugfix_id from aru_bugfixes
  where bugfix_rptno = :1");

ARUDB::add_query(GET_COMPOSITE_CONSTITUENTS =>
"select bugfix_request_id from aru_bugfix_requests
  where (bugfix_id in (
          select related_bugfix_id from aru_bugfix_relationships
               where relation_type=". ARU::Const::composite_constituents .
 " and bugfix_id = :1) or bugfix_id=:1 )
      and platform_id = :2 and status_id in
                     (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::patch_ftped_internal. ")" .
      " order by bugfix_request_id asc");

ARUDB::add_query("GET_NOTIFICATION_LIST" =>
"select distinct email_address
 ,      dev_value
 ,      type
 ,      email_template
 from   apf_notifications
 where  (series_id = :1 or
         product_release_id = :1)
 and rownum = 1");

ARUDB::add_query("GET_NOTIFICATION_LIST_BY_TYPE" =>
"select distinct email_address
 ,      dev_value
 ,      type
 ,      email_template
 from   apf_notifications
 where  (series_id = :1 or
         product_release_id = :1)
 and    type in (:2)");

ARUDB::add_query("IS_CD_PF" =>
"select distinct email_address
 from   apf_notifications
 where  (series_id = :1 or
         product_release_id = :1)
 and    type in ('PF','CD')");

ARUDB::add_query(GET_AUTO_TRACKING_GROUP =>
                "select substr(rtg.VALUE,10)
FROM bugdb_tracking_groups_v tg,
bugdb_rpthead_tracking_gps_v rtg
where rtg.rptno =  :1
and rtg.TRACKING_GROUP_ID = tg.ID
and tg.name = 'Patch Automation Attributes'");

ARUDB::add_query(GET_FMW12C_TEST_BLR =>
                "select rtg.VALUE
FROM bugdb_tracking_groups_v tg,
bugdb_rpthead_tracking_gps_v rtg
where rtg.rptno =  :1
and rtg.TRACKING_GROUP_ID = tg.ID
and tg.name = 'Patch Automation Attributes'");

ARUDB::add_query(GET_ALL_BASE_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_label_dependencies ald, aru_objects ao1
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" ."
and ald.a_uses_b = ao1.object_id
and ald.label_id        = :2");

ARUDB::add_query(GET_BASE_PRODUCT_FROM_ARU =>
"select ap.product_abbreviation, ap1.product_abbreviation
  from aru_bugfix_requests abr, aru_products ap,
       aru_product_groups apg, aru_products ap1
 where abr.product_id = ap.product_id
   and ap.product_id = apg.child_product_id
   and apg.parent_product_id = ap1.product_id
   and apg.relation_type =  ".ARU::Const::direct_relation."
   and abr.bugfix_request_id = :1");

ARUDB::add_query(GET_BUGFIX_REQUEST_ID =>
  "select bugfix_request_id from aru_backport_bugs
     where backport_bug = :1");

ARUDB::add_query(GET_MAX_TMPL_ID =>
  "select max(tmpl_id) from automation_archive_tmpls");

ARUDB::add_query(GET_FAILURE_BUG_NUM =>
"select rptno
  from  bugdb_rpthead_v
 where  product_id = :1
   and  category = :2
   and  sub_component = :3
   and  portid = :4
   and  utility_version = :5
   and  third_party_product = :6
   and  status not in (36, 32, 90, 96, 93, 35)");

ARUDB::add_query(GET_FAILURE_BUG_NUM_NEW =>
"select amb.MATS_BUG
from ARU_DTE_MATS adm , ARU_MATS_BUGS amb, bugdb_rpthead_v brv
where adm.mats_name=:1
and adm.bugdb_product_id=:2
and adm.GA_RELEASE=:3
and adm.mats_id=amb.mats_id
and amb.mats_bug=brv.rptno
and brv.status not in (36, 32, 90, 96, 93, 35, 92)");

ARUDB::add_query(GET_DTE_APF_FILED_BUGS =>
"select rptno, third_party_product, portid,
        utility_version, programmer
   from bugdb_rpthead_v
  where product_id = :1
   and  category = :2
   and  sub_component = :3
   and  third_party_product like :4
   and  upd_date > (sysdate - :5)
   and  status not in (36, 32, 90, 96, 93, 35)");

ARUDB::add_query(GET_PLATFORM_SHORT_NAME =>
"select platform_short_name
   from aru_platforms
  where bugdb_platform_id = :1
    and obsolete = 'N'");

ARUDB::add_query(GET_BASE_PRODUCT_FROM_BUG =>
"select ap.product_id, ap1.product_id
  from aru_products ap, aru_products ap1,
       aru_product_groups apg, bugdb_rpthead_v br
 where br.product_id = ap.bugdb_product_id
   and ap.product_id = apg.child_product_id
   and apg.parent_product_id = ap1.product_id
   and apg.relation_type =  ".ARU::Const::direct_relation."
   and br.rptno = :1");

ARUDB::add_query(GET_UPLOADED_BASE_BUG =>
"select ab.bugfix_rptno
 from   aru_bugfixes ab
 ,      aru_bugfix_requests abr
 where  ab.bugfix_rptno = :1
 and    ab.bugfix_id = abr.bugfix_id
 and    abr.status_id in (22, 23, 24)");

ARUDB::add_query(GET_PREV_BASE_BUG =>
"select parameter_name, parameter_value
 from   aru_cum_patch_release_params acprp
 where  acprp.release_id = :1
 and    parameter_value = (select max(parameter_value)
                           from   aru_cum_patch_release_params acprp
                           ,      aru_bugfixes ab
                           ,      aru_bugfix_requests abr
                           where  acprp.release_id = :1
                           and acprp.parameter_value = to_char(ab.bugfix_rptno)
                           and ab.bugfix_id = abr.bugfix_id
                           and abr.status_id in (22, 23, 24))");

ARUDB::add_query(GET_ARU_BY_BUG_PLATFORM =>
"select abr.bugfix_request_id,abr.status_id
  from aru_bugfix_requests abr, aru_bugfixes ab
  where ab.bugfix_rptno=:1
      and abr.bugfix_id=ab.bugfix_id
      and abr.platform_id=:2
      and abr.status_id in
      (". ARU::Const::patch_ftped_support . "," .
          ARU::Const::patch_ftped_dev . "," .
          ARU::Const::patch_ftped_internal. ")" .
      " order by abr.bugfix_request_id");

ARUDB::add_query(GET_PATCH_BUGFIXES =>
"select related_bug_number
 from   aru_bugfixes ab
 ,      aru_bugfix_bug_relationships abbr
 where  ab.bugfix_id = abbr.bugfix_id
 and    ab.bugfix_rptno = :1
 order by 1");

ARUDB::add_query(GET_PATCH_JOB_DETAILS_WITHOUT_ISD_REQ =>
" select patch_job_id, job_id, job_name, job_url from
(select apjd.patch_job_id , apbj.job_id, apbj.job_name, apbj.job_url
from aru_patch_job_details apjd, aru_product_build_jobs apbj
where apjd.backport_bug = :1
and apjd.isd_request_id is null
and apjd.job_id=apbj.job_id
order by apjd.CREATION_DATE desc)
  where rownum = 1");

ARUDB::add_query(GET_PATCH_JOB_DETAILS_BY_BP_ISD_REQ =>
" select patch_job_id, job_id, job_name, job_url from
(select apjd.patch_job_id , apbj.job_id, apbj.job_name, apbj.job_url
from aru_patch_job_details apjd, aru_product_build_jobs apbj
where apjd.backport_bug = :1
and apjd.isd_request_id = :2
and apjd.job_id=apbj.job_id
order by apjd.CREATION_DATE desc)
  where rownum = 1");

ARUDB::add_query(GET_PATCH_JOB_DETAILS =>
" select patch_job_id, job_id, job_name, job_url from
(select apjd.patch_job_id , apbj.job_id, apbj.job_name, apbj.job_url
from aru_patch_job_details apjd, aru_product_build_jobs apbj
where apjd.backport_bug = :1
and apjd.job_id=apbj.job_id
order by apjd.CREATION_DATE desc)
  where rownum = 1");

ARUDB::add_query(GET_PATCH_JOB_INFO =>
" select apbj.job_id, apbj.job_name, apjd.backport_bug,
  apbj.job_url, apbj.DEV_OWNER, apbj.se_owner, apjd.created_by,
  apjd.build_number, apjd.orch_url, apbj.scm, apjd.comments, apjd.ADDITIONAL_INFO
from aru_patch_job_details apjd, aru_product_build_jobs apbj
where apjd.patch_job_id = :1
and apjd.job_id=apbj.job_id   ");

ARUDB::add_query(GET_JOB_PARAMS =>
" select param_name, param_value, param_type
from aru_build_job_parameters where job_id=:1   ");

ARUDB::add_query(GET_PATCH_JOB_PARAMS =>
"select apjp.param_name, apjp.param_value, abjp.param_type
from aru_patch_job_params apjp , aru_patch_job_details apjd,
     aru_build_job_parameters abjp
where apjp.patch_job_id = :1
  and apjp.patch_job_id=apjd.patch_job_id
  and apjd.job_id = abjp.job_id
  and apjp.param_name = abjp.param_name");

ARUDB::add_query(GET_PATCH_JOB_TXN_NAME =>
"select apjp.param_value from aru_patch_job_params  apjp,
aru_patch_job_details apjd, aru_build_job_parameters abjp
 where apjp.patch_job_id = :1
   and apjp.patch_job_id = apjd.patch_job_id
   and apjd.job_id=abjp.job_id
   and apjp.param_name=abjp.param_name
   and abjp.param_type='transaction'");

ARUDB::add_query(GET_PATCH_JOB_EMAIL =>
"select apjp.param_value from aru_patch_job_params  apjp,
aru_patch_job_details apjd, aru_build_job_parameters abjp
 where apjp.patch_job_id = :1
   and apjp.patch_job_id = apjd.patch_job_id
   and apjd.job_id=abjp.job_id
   and apjp.param_name=abjp.param_name
   and abjp.param_type='EMAIL'");

ARUDB::add_query(GET_PATCH_JOB_BY_ISD_REQ =>
" select patch_job_id, job_id, base_bug, comp_ver,
  to_char(build_start_time,'yyyy-mm-dd hh24:mi:ss') ,
  created_by, build_number, orch_url
      from
(select patch_job_id, job_id, base_bug, comp_ver,
  build_start_time, created_by, build_number, orch_url
from aru_patch_job_details apjd
where apjd.isd_request_id = :1
    order by apjd.build_start_time desc)
    where rownum = 1");

ARUDB::add_query(GET_PATCH_JOB_CNT_ISD_REQ =>
"select count(apjd.patch_job_id)
from aru_patch_job_details apjd
where apjd.isd_request_id = :1");

ARUDB::add_query(IS_PREV_HUDSON_BUILD_RUNNING =>
"select ir1.request_id
from isd_requests ir1, isd_requests ir2
where ir1.request_id = :1
and   ir2.reference_id = ir1.reference_id
and  ir2.creation_date < ir1.creation_date
and ir2.STATUS_CODE not in (
".ISD::Const::isd_request_stat_succ.",
".ISD::Const::isd_request_stat_fail.",
".ISD::Const::isd_request_stat_abtg.",
".ISD::Const::isd_request_stat_abtd.")
and ir2.request_type_code = ir1.request_type_code ");

ARUDB::add_query(GET_PREVIOUS_OVERLAYS_DTE =>
"select distinct dte.dte_command_id,
  dte.dte_command,
  ap.product_id,
  ap.product_name,
  ar1.release_id,
  ar1.release_long_name,
  dte.platform_id
from aru_releases ar1,
  (select base_release_id
  from aru_releases
  where release_id = :1
  ) ar2,
  aru_products ap,
  aru_product_releases apr,
  apf_dte_commands dte ,
  apf_dte_results adr
where ar2.base_release_id = ar1.base_release_id
and ar1.release_id       <> ar1.base_release_id
and ap.product_id         = :2
and ap.product_id         = apr.product_id
and ar1.release_id         = apr.release_id
and apr.product_release_id = dte.product_release_id
and dte.platform_id        = :3
and dte.dte_command_id = adr.dte_command_id
and adr.status       = 'dte_success' ");

  ARUDB::add_query(GET_BP_TESTFLOW_ID =>
"select testflow_id
from apf_testflows
where testflow_name like :1
and enabled = 'Y'");


ARUDB::add_query(IS_BASE_ARU_RELEASED =>
"select abr1.bugfix_request_id
from aru_bugfix_requests abr1 , aru_bugfix_requests abr2,
     aru_bugfixes ab
where abr1.bugfix_id = abr2.bugfix_id
and ab.bugfix_id=abr2.bugfix_id
and ab.status_id=" . ARU::Const::checkin_released . "
and abr1.status_id in (" .
ARU::Const::patch_ftped_support . "," .
ARU::Const::patch_ftped_dev . ")
and abr1.platform_id=" . ARU::Const::platform_linux64_amd . "
and abr2.bugfix_request_id=:1");

ARUDB::add_query(GET_REMOTE_TXN_SRC_DOS =>
"select distinct artf.file_name, artf.file_location, substr(artf.file_type,-2)
   from apf_remote_transactions art, apf_remote_transaction_files artf
  where art.transaction_id = artf.transaction_id
    and art.transaction_name = :1");

ARUDB::add_query(GET_SRC_BY_DELIVERABLE =>
"select ao2.object_location, ao2.object_name,
 ald.b_used_by_a,  ald.a_uses_b
  from aru_label_dependencies ald, aru_objects ao1,
    aru_objects ao2, aru_product_release_labels aprl
where ao1.object_name=:1
and ao1.object_location=:2
and ald.label_id=:3
and ald.a_uses_b=ao1.object_id
and ao2.object_id=ald.b_used_by_a
and aprl.label_id=ald.label_id
and ao2.product_release_id=aprl.product_release_id
and ald.label_dependency='BASE'
");

ARUDB::add_query(GET_MANUAL_UPLOAD_DETAILS =>
"select 1
   from aru_bugfix_request_history
  where bugfix_request_id = :1
    and status_id = :2");

ARUDB::add_query(GET_REQUEST_PATCH_LOCATION =>
"select irp.param_value
   from isd_request_parameters irp
  where irp.request_id = :1
   and  irp.param_name='patch_location'");

ARUDB::add_query(GET_BLR_TG_FROM_PSE =>
                "select substr(rtg.VALUE,10)
      FROM bugdb_tracking_groups_v tg,
           bugdb_rpthead_tracking_gps_v rtg,
           bugdb_rpthead_v brv,
           bugdb_rpthead_v brv1
      where rtg.rptno =  brv.rptno
      and rtg.TRACKING_GROUP_ID = tg.ID
      and tg.name = 'Patch Automation Attributes'
      and brv.base_rptno = brv1.base_rptno
      and brv.generic_or_port_specific = 'B'
      and brv.status = 35
      and brv1.rptno = :1
      and brv.utility_version = brv1.utility_version");

ARUDB::add_query(GET_ALL_BLR_TG_FROM_PSE =>
                "select substr(rtg.VALUE,10), brv.status, brv.rptno
      FROM bugdb_tracking_groups_v tg,
           bugdb_rpthead_tracking_gps_v rtg,
           bugdb_rpthead_v brv,
           bugdb_rpthead_v brv1
      where rtg.rptno =  brv.rptno
      and rtg.TRACKING_GROUP_ID = tg.ID
      and tg.name = 'Patch Automation Attributes'
      and brv.base_rptno = brv1.base_rptno
      and brv.generic_or_port_specific = 'B'
      and brv1.rptno = :1
      and brv.utility_version = brv1.utility_version");

ARUDB::add_query(FMW_NATIVE_DO_PLATFORMS =>
"select attribute_value from aru_bugfix_attributes abr , aru_bugfixes ab
where abr.bugfix_id = ab.bugfix_id
and ab.bugfix_rptno = :1
and ab.release_id = :2
and abr.attribute_type = 60003"
);

ARUDB::add_query(GET_FULL_LABEL_FOR_TXN =>
"select aba.attribute_value
   from aru_bugfixes ab, aru_bugfix_attributes aba, aru_transactions at
  where aba.attribute_type = ". ARU::Const::fusion_non_snapshot_label ."
    and aba.bugfix_id = ab.bugfix_id
    and ab.bugfix_id = at.bugfix_id
    and at.transaction_name = :1");

ARUDB::add_query(GET_TXN_MERGE_TIME =>
   "select to_char(max(bm.DATE_COMPLETED), 'YYYYMMDDHH24MISS')
      from jr_common.i\$sdd_branch_merges\@REPOS bm
         , jr_common.i\$sdd_branches\@REPOS tb
     where tb.name = :1
       and bm.source_branch_irid = tb.irid");

ARUDB::add_query(GET_INVALID_REGRESS_SUBMIT_FAILURE =>
"select transaction_id
              from  apf_remote_transactions
             where  backport_bug = :1
                  and metadata2_type='Invalid object regression submission failure'");

ARUDB::add_query(GET_SQL_VALIDATION_FAILURE_DATA =>
"select transaction_id
              from  apf_remote_transactions
             where  backport_bug = :1
                  and metadata1_type='SQL Savetrans Validation Output'");

ARUDB::add_query(GET_INVALID_REGRESS_SUBMIT_INFO =>
"select transaction_id
              from  apf_remote_transactions
             where  backport_bug = :1
                  and metadata1_type='Farm Invalid Object Regression Submitted'");

ARUDB::add_query(GET_CPM_REL_PROD_NAME =>
"select distinct acps.product_name
 from aru_cum_patch_releases acpr, aru_cum_patch_series acps
 where acpr.aru_release_id = :1
 and acps.series_id = acpr.series_id");

ARUDB::add_query(GET_GOLD_IMAGE_BACKPORT =>
"select distinct brv.rptno
from bugdb_rpthead_v brv
where ((brv.base_rptno = :1) or
       (brv.rptno = :1
        and brv.generic_or_port_specific = 'M'
        and base_rptno is null))
and aru_backport_util.pad_version(brv.utility_version) =
          aru_backport_util.pad_version(:2)
and brv.generic_or_port_specific in ('B','M')
and brv.status not in (53,55,59,96)");

ARUDB::add_query(PROACTIVE_BACKPORT_EXISTS =>
"select count(distinct brv.base_rptno)
    from aru_bugfixes ab, aru_cum_patch_releases acpr, bugdb_rpthead_v brv
    where acpr.release_id = :1
    and   ab.release_id = acpr.aru_release_id
    and brv.base_rptno = ab.bugfix_rptno
    and aru_backport_util.pad_version(brv.utility_version) = aru_backport_util.pad_version(acpr.release_version)
    and brv.generic_or_port_specific in ('B','M')");

ARUDB::add_query(GET_REBASE_REL_LABEL_ID =>
"select distinct aprl.label_id, aprl.label_name
from aru_product_release_labels aprl,
     aru_cum_patch_releases acpr,
     aru_product_releases apr
where acpr.release_id = :1
and apr.release_id = acpr.aru_release_id
and aprl.product_release_id = apr.product_release_id
and aprl.label_name = :2
and aprl.platform_id = :3");

ARUDB::add_query(GET_LATEST_REL_CYCLE =>
"select rel_cycle from (
select  distinct acpra.attribute_value  rel_cycle
from  apf_rebase_labels arl, aru_cum_patch_release_attrs acpra
where acpra.attribute_name = 'RelCycle'
and arl.release_id = acpra.release_id 
order by to_date(acpra.attribute_value,'MONYYYY') desc) where rownum = 1");

ARUDB::add_query(GET_ALL_NON_REBASED_TXNS =>
"select distinct art.release_id, acpr.release_version, art.bug_number, art.txn_name, art.base_label, art.request_id
 from apf_rebased_transactions art, aru_cum_patch_release_attrs acpra, 
     bugdb_rpthead_v brv, aru_cum_patch_releases acpr
 where acpra.attribute_name = 'RelCycle'
 and acpra.attribute_value = :1
 and acpr.release_id = acpra.release_id
 and art.release_id = acpr.release_id
  and art.auto_refreshed = 'N'
 and brv.rptno = art.bug_number
 and brv.status not in (53,55,59,96)
 and art.base_label != (select max(arl1.to_label)
 from apf_rebase_labels arl1 
 where arl1.release_id = art.release_id
 and arl1.platform_id = brv.portid
 and REGEXP_SUBSTR(arl1.to_label,'[^_]+',1,1) = REGEXP_SUBSTR(art.base_label,'[^_]+',1,1))
 order by art.release_id, art.bug_number");

ARUDB::add_query(GET_REBASE_TXN_EXISTS =>
"select count(1)
 from apf_rebased_transactions
 where bug_number = :1");

ARUDB::add_query(GET_REBASE_BACKPORT_LIST =>
"select distinct brv.rptno, nvl(brv.base_rptno, brv.rptno), abt.transaction_name
from aru_backport_transactions abt, bugdb_rpthead_v brv,
     aru_backport_requests abr, aru_cum_patch_releases acpr
where aru_backport_util.pad_version(acpr.release_version) =
    aru_backport_util.pad_version(:1)
and abr.version_id = acpr.release_id
and  abt.backport_bug = abr.backport_bug
and brv.rptno = abt.backport_bug
and  brv.generic_or_port_specific in ('B', 'M')
and  brv.portid in (:2, :3)
and brv.status = 35");

ARUDB::add_query(GET_ALL_REBASE_BACKPORT_OLD_LIST =>
"select distinct brv.rptno, nvl(brv.base_rptno, brv.rptno), abt.transaction_name, brv.status 
from aru_backport_transactions abt, bugdb_rpthead_v brv,
     aru_backport_requests abr, aru_cum_patch_releases acpr
where aru_backport_util.pad_version(acpr.release_version) =
    aru_backport_util.pad_version(:1)
and abr.version_id = acpr.release_id
and  abt.backport_bug = abr.backport_bug
and brv.rptno = abt.backport_bug
and  brv.generic_or_port_specific in ('B', 'M')
and  brv.portid in (:2, :3)
and brv.status not in (53,55,59,96)");

ARUDB::add_query(GET_ALL_REBASE_BACKPORT_LIST =>
"select  distinct brv.rptno, nvl(brv.base_rptno, brv.rptno), abrh.comments  , brv.status  
from aru_backport_requests abr, bugdb_rpthead_v brv,
     apf_build_request_history abrh, aru_cum_patch_releases acpr
where aru_backport_util.pad_version(acpr.release_version) =
    aru_backport_util.pad_version(:1)
and abr.version_id = acpr.release_id 
and brv.rptno = abr.backport_bug
and  brv.generic_or_port_specific in ('B', 'M')
and  brv.portid in (:2, :3)
and brv.status not in (53,55,59,96) 
and abrh.request_id in (select abrv.request_id
                       from apf_build_requests_v abrv
                       where abrv.backport_bug = brv.rptno)
and abrh.request_type = 95510
and abrh.comments is not null");

ARUDB::add_query(IS_REBASE_DEP_LABEL_DONE =>
"select count(distinct from_label)
from apf_rebase_labels
where release_version = :1
and from_label like :2");

ARUDB::add_query(IS_REBASE_DONE =>
"select count(distinct to_label)
from apf_rebase_labels
where  release_version = :1
and to_label = :2");
 
ARUDB::add_query(GET_REBASE_TXNS_LIST =>
"select art.bug_number, art.txn_name, art.auto_refreshed,
    art.base_label, art.request_id, brv.generic_or_port_specific
from apf_rebased_transactions art, bugdb_rpthead_v brv
where art.release_id = :1
and brv.rptno = art.bug_number
and brv.portid in (:2, :3) ");

ARUDB::add_query(GET_REBASE_TXNS_LIKE_LIST =>
"select art.bug_number, art.txn_name, art.auto_refreshed,
    art.base_label, art.request_id, brv.generic_or_port_specific
from apf_rebased_transactions art, bugdb_rpthead_v brv
where art.release_id = :1
and art.base_label like :4 
and brv.rptno = art.bug_number
and brv.portid in (:2, :3) ");

ARUDB::add_query(
IS_PSE_PATCH_REFRESHED =>
"select count(distinct ir1.request_id)
 from isd_requests ir1
 where ir1.reference_id = :1
 and   ir1.request_type_code = ".ISD::Const::st_apf_req_merge_task.
" and ir1.request_id = (select max(ir3.request_id)
                    from isd_requests ir3
                    where ir3.reference_id = :1
                    and ir3.request_type_code = ".
                             ISD::Const::st_apf_req_merge_task.")
  and ir1.creation_date <
             (select ir2.creation_date
                from isd_requests ir2
               where ir2.reference_id = :2
                 and ir2.request_type_code = ".ISD::Const::st_apf_request_task.
               " and ir2.request_id = (select max(ir4.request_id)
                                        from isd_requests ir4
                                        where ir4.reference_id = :2
                                         and ir4.request_type_code = ".
                                              ISD::Const::st_apf_request_task."))
");

ARUDB::add_query(GET_REBASE_BUG_PROD_ID =>
"select  distinct to_number(acpsp.parameter_value)
 from   aru_cum_patch_series_params acpsp
 ,      aru_cum_patch_series acps, aru_cum_patch_Releases acpr
 where acpr.release_id = :1
 and acps.series_id = acpr.series_id
 and acpsp.series_id = acps.series_id
 and acpsp.parameter_name = 'BUGDBID'");

ARUDB::add_query(GET_REBASE_FROM_LABEL =>
"select from_label
from (select distinct substr(acpr.parameter_name,0,instr(acpr.parameter_name,':#:')-1) from_label , acpr.parameter_value aru_no
from aru_cum_patch_release_params acpr, aru_bugfix_requests abr
where acpr.release_id = :1
and substr(acpr.parameter_name,0,instr(acpr.parameter_name,':#:')-1) not like :2
and acpr.parameter_type = 34615
and acpr.parameter_value < (select distinct acprr.parameter_value
                             from aru_cum_patch_release_params acprr
                             where acprr.release_id = :1
                             and acprr.parameter_name like :2
                             and acprr.parameter_type = 34615
                             and rownum = 1)
and acpr.parameter_name like :3
and abr.bugfix_request_id = to_number(acpr.parameter_value)
order by acpr.parameter_value desc)
where rownum = 1");

ARUDB::add_query(GET_REBASE_RELEASE_INFO =>
"select release_id,series_id,release_label,aru_release_id
   from  aru_cum_patch_releases
   where release_version = :1");

ARUDB::add_query(GET_REBASE_RELEASE_LABEL =>
"select distinct replace(acpr.release_label,'_LINUX.X64', ap1.value)
    RELEASE_LABEL
 from  aru_cum_patch_Releases acpr , aru_parameters ap1
  where acpr.release_id = :1
  and  ap1.name = :2");

ARUDB::add_query(GET_LATEST_GOLD_IMAGE_BUG =>
"select rptno,utility_version, last_digit
from(
select distinct brv.rptno, brv.utility_version,
    nvl(to_number(REGEXP_SUBSTR(REGEXP_SUBSTR(utility_version ,'\d+[a-zA-Z]+') ,'\d+')),0) last_digit
from bugdb_rpthead_v brv
where ((brv.base_rptno = :1) or
       (brv.rptno = :1
        and brv.generic_or_port_specific = 'M'
        and base_rptno is null))
and aru_backport_util.pad_version(brv.utility_version) like :2
and brv.generic_or_port_specific in ('B','M')
and brv.status not in (53,55,59,96)
order by last_digit desc)
where rownum = 1");

ARUDB::add_query(GET_BACKPORT_BUG_FOR_CC =>
                     "select backport_bug
                       from    aru_backport_requests
                       where   backport_request_id =:1");

ARUDB::add_query(GET_BACKPORT_RELATION_BUGS =>
"select distinct abbr.related_bug_number
from aru_backport_requests abr, aru_backport_bug_relationships abbr
where abr.backport_request_id = :1
and abbr.backport_request_id = abr.backport_request_id
and abbr.relation_type = ".ARU::Const::fixed_direct);

ARUDB::add_query(IS_BASE_PATCH_AVAILABLE =>
"select nvl(max(abr.release_id),0)
from aru_bugfix_requests abr, aru_releases ar
where abr.bug_number = :1
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal.")
and abr.release_id = ar.release_id
and ar.base_release_id = :2
and abr.platform_id in (:3,".ARU::Const::platform_generic.")");

ARUDB::add_query(IS_PATCH_AVAILABLE =>
"select  nvl(max(abr.release_id),0)
from aru_bugfix_requests abr, aru_releases ar
where abr.bug_number = :1
and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . "," .
                        ARU::Const::patch_ftped_internal.")
and ((abr.release_id = ar.release_id
      and aru_backport_util.pad_version(ar.release_name) =
          aru_backport_util.pad_version(:2))
  or (abr.release_id in
          (select acpr.aru_release_id
           from aru_cum_patch_releases acpr
           where aru_backport_util.pad_version(acpr.release_version) =
                 aru_backport_util.pad_version(:2))))
and abr.platform_id in (:3,".ARU::Const::platform_generic.")");

ARUDB::add_query(IS_BUG_HAS_VALID_TRK_GRP =>
"select count(distinct rtg.rptno)
FROM bugdb_tracking_groups_v tg, bugdb_rpthead_tracking_gps_v rtg
where rtg.rptno = :1
and tg.name = :2
and rtg.TRACKING_GROUP_ID = tg.ID");

ARUDB::add_query(GET_CPM_SERIES_NAME_BY_SERIES_ID =>
"select series_name
              from  aru_cum_patch_series
             where  series_id = :1");

ARUDB::add_query(GET_STREAM_PREV_LABEL_NAME =>
"select parameter_name from aru_cum_patch_release_params
  where release_id=:1 and parameter_type=34593");

ARUDB::add_query(GET_BUNDLE_PATCH_TYPE =>
"select family_name from aru_cum_patch_releases acpr, aru_cum_patch_series acps
  where acpr.release_id=:1 and acpr.series_id=acps.series_id");

ARUDB::add_query(GET_BUNDLE_LABEL_FRM_APF_TBL =>
"select transaction_id, transaction_name from  apf_remote_transactions where  backport_bug = :1
 and metadata2_type='Bundle Label Platform' and metadata2 = :2");

 ARUDB::add_query(GET_INVALID_OBJ_DIFF_DATA =>
 "select transaction_id, metadata3
   from  (select art.transaction_id , art.metadata3
         from apf_remote_transactions art
         where art.backport_bug=:1
         and metadata2_type='Farm Invalid Object Validation Diff'
                   and metadata2='1'
           order by creation_date,transaction_id desc)
   where rownum = 1");

 ARUDB::add_query(GET_INVALID_OBJ_DIFF_TYPE =>
 "select transaction_id, metadata2
     from  (select art.transaction_id, art.metadata2
                       from apf_remote_transactions art
                        where art.backport_bug=:1
                   and metadata2_type='Farm Invalid Object Regression Failure Type'
                      order by creation_date,transaction_id desc)
   where rownum = 1");

  ARUDB::add_query(GET_MISSING_PHASE_ERROR =>
    "select transaction_id, metadata2
       from  (select art.transaction_id, art.metadata2
                from apf_remote_transactions art
                     where art.backport_bug=:1
                       and metadata2_type='SQL Missing phase error'
                         order by creation_date,transaction_id desc)
       where rownum = 1");

ARUDB::add_query(GET_FMW12C_BI_LABEL_NAME =>
"select aprl.label_id, aprl.label_name
   from aru_product_release_labels aprl, aru_product_releases apr
  where aprl.product_release_id = apr.product_release_id
    and apr.product_id = :1
    and apr.release_id = :2
    and aprl.platform_id = :3
    and (aprl.label_name like 'BIFNDN%' or aprl.label_name like 'BISERVER%' or aprl.label_name like 'BIPUBLISHER%')");

ARUDB::add_query(GET_BP_PATCH_TYPE =>
"select acps.patch_type
  from aru_cum_patch_releases acpr, aru_cum_patch_series acps
  where acpr.series_id=acps.series_id
    and acpr.release_version  = :1");

ARUDB::add_query(GET_BP_REL_SERIES_ID =>
"select acpr.series_id
  from aru_cum_patch_releases acpr
  where acpr.release_version = :1");

ARUDB::add_query(GET_TAB_SUBMITTED_REQUEST_ID =>
"select abr.isd_request_id
    from apf_build_request_history abrh, apf_build_requests abr
    where abr.backport_bug = :1
    and abr.request_status = ". APF::Const::st_sp_tab_basic_submit_success."
    and abr.request_type = ". ISD::Const::st_apf_sys_tab_task ."
    and abrh.request_id  = abr.request_id
    and abrh.comments = :2
    and rownum = 1");

ARUDB::add_query(GET_TAB_SUBMITTED_FLAG_PSE =>
"select abr.request_id
     from apf_build_requests abr
     where abr.backport_bug = :1
     and abr.request_type   = ". ISD::Const::st_apf_sys_tab_task ."
     and abr.request_status = ". APF::Const::st_sp_tab_basic_submitted." " );

ARUDB::add_query(GET_TRACKING_BUG_NUMBER_FOR_LABEL =>
"select parameter_value
    from aru_cum_patch_release_params
    where  parameter_name like  '%' || :1 || '%' " );

ARUDB::add_query(GET_TAB_INSTALL_DETAILS =>
"select aitr.isd_request_id, aitr.request_id, aitr.tab_test_type,
        aitr.apf_patch_type, aitr.apf_tab_status
     from apf_installtest_tab_requests aitr
     where aitr.tab_job_id = :1
     and   aitr.tab_test_type = :2
     and   aitr.obsoleted  = 'N' ");

#ARUDB::add_query(GET_TAB_SUBMITTED_FLAG_JOBID =>
#"select abrh.request_id
#     from apf_build_request_history abrh
#     where abrh.request_type = ". APF::Const::st_sp_tab_job_id ."
#     and abrh.comments = :1" );
#
#ARUDB::add_query(GET_TAB_SUBMITTED_STATUS_JOBID =>
#"select abr.backport_bug
#     from apf_build_request_history abrh, aru_build_requests abr
#     where abrh.request_type = ". APF::Const::st_sp_tab_job_id ."
#     and abrh.comments = :1
#     and abr.request_id = abrh.request_id
#     and abr.request_status = ". APF::Const::st_sp_tab_success ." ");
#
#ARUDB::add_query(GET_TAB_SUBMITTED_STATUS_PSE =>
#"select abr.request_id
#     from apf_build_requests abr
#     where abr.backport_bug = :1
#     and abr.request_status = ". APF::Const::st_sp_tab_success ."
#     and rownum = 1
#     order by creation_date ");

ARUDB::add_query(GET_MAT_PATCHES =>
"select  adr.bugfix_request_id, abr.status_id
 from ARU_DTE_MATS adm , ARU_MATS_PATCH amp, apf_dte_results adr, aru_bugfix_requests abr
    where adm.mats_id=amp.mats_id
      and amp.isd_request_id=adr.isd_request_id
      and adr.bugfix_request_id=abr.bugfix_request_id
      and mats_name=:1
      and bugdb_product_id=:2");

ARUDB::add_query(GET_REGULAR_BUG_4_METADATA_ONLY =>
"select param_value from isd_request_parameters
  where param_name='regular_bundle_bug'
    and request_id=:1  ");

ARUDB::add_query(GET_CHECKIN_BUG_FOR_METADATA =>
"select parameter_value from aru_cum_patch_release_params
  where parameter_name=:1 and release_id=:2");

ARUDB::add_query(GET_CHECKIN_BUG_FOR_MULTIARU_METADATA =>
"select tracking_bug from aru_cum_patch_releases where release_id=:1");

ARUDB::add_query(GET_REGULAR_ARU_4_METADATA_ONLY =>
"select param_value from isd_request_parameters
  where param_name='regular_bundle_aru'
    and request_id=:1");

ARUDB::add_query(GET_RELEASE_ID_4_ARU =>
"select release_id from aru_bugfix_requests
  where bugfix_request_id=:1");

  ARUDB::add_query(GET_DELTA_BPS_BY_SERIES =>
  "select backport_bug
  from  aru_cum_codeline_requests
  where  series_id = :1
    --18.5.0.0.0DBRU/18.0 DEV RU i.e current bundle
  and  base_bug in (
  select base_bug
  from   aru_cum_codeline_requests
  where  series_id = :1
    --18.5.0.0.0DBRU/18.0 DEV RU i.e current bundle
  and    status_id > 34581
  minus
  select base_bug
  from   aru_cum_codeline_requests
  where    series_id = :2
    --18.4.0DBRU i.e N-1 bundle for SQLAuto
  and status_id > 34581
  )
  and  status_id >=34581
  order by last_updated_date
  ");

ARUDB::add_query(GET_DELTA_BPS_BY_RELEASE =>
"select backport_bug
from  aru_cum_codeline_requests
where  release_id = :1
  -- 18.5.2 RUR i.e current RUR  release
and  base_bug in (
select base_bug
from   aru_cum_codeline_requests
where     release_id = :1
and    status_id >=34581
  -- 18.5.2 RUR i.e current RUR  release
minus
select base_bug
from   aru_cum_codeline_requests
where    release_id = :2
  -- 18.5.1 RUR i.e N-1 RUR  release
and    status_id >=34581
)
and base_bug is not null
and  status_id >=34581
order by last_updated_date
");

ARUDB::add_query(GET_OBJ_INFO =>
"select ao.object_id, ao.object_name, ao.object_location, abov.rcs_version,
        ao.filetype_id, af.filetype_name, af.requires_porting,
        af.source_extension
   from aru_objects ao, aru_bugfix_object_versions abov, aru_filetypes af
  where abov.bugfix_id = :1
    and (abov.source like 'D%' or abov.source like '%I%')
    and af.filetype_id = ao.filetype_id
    and ao.object_id = abov.object_id
    and ao.object_id=:2");

ARUDB::add_query(GET_METADATA_DB_LABEL =>
"  select REGEXP_SUBSTR(REGEXP_SUBSTR(comments,'label:[^;]+'),'RDBMS_.+')
    from aru_bugfix_request_history
     where bugfix_request_history_id=
     (select max(bugfix_request_history_id)
       from aru_bugfix_request_history
            where bugfix_request_id=:1 and comments like 'Requesting MetadataOnly Bundle;%') ");

ARUDB::add_query(IS_DIRECTDOS_SEEDED =>
"select count(artf.file_name)
   from apf_remote_transactions art, apf_remote_transaction_files artf
  where artf.transaction_id = art.transaction_id
    and art.transaction_name = :1");

ARUDB::add_query(GET_CPM_SERIES_PRODUCT =>
"select acps.series_id, acps.product_id from
  aru_cum_patch_series acps, aru_cum_codeline_requests accr
  where acps.series_id = accr.series_id
  and accr.backport_bug = :1
  and rownum < 2");

ARUDB::add_query(CHECK_NEXT_CODELINE_OPEN_RELEASE =>
  "select release_date from aru_cum_patch_releases
  where tracking_bug = :1
  and status_id = 34522
  and release_date > (select release_date from aru_cum_patch_releases where tracking_bug = :2)");

ARUDB::add_query(GET_DB_TRACKING_BUG_FOR_JDK =>
"select max(acpr.tracking_bug)
  from aru_cum_patch_Releases acpr, aru_bugfixes ab, aru_bugfix_requests abr
  where acpr.release_version like :1 || '%'
  and acpr.release_name not like '%Revision%'
  and ab.bugfix_rptno = acpr.tracking_bug
  and abr.bugfix_id = ab.bugfix_id
  and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::ready_to_ftp_to_dev . ")"
  );

ARUDB::add_query(GET_LINUX_LABEL_ID =>
"select aprl2.label_id
from aru_product_release_labels aprl1,
     aru_product_release_labels aprl2
where aprl1.label_id = :1
  and aprl2.product_release_id = aprl1.product_release_id
  and aprl2.platform_id = :2
");

ARUDB::add_query(GET_THIRDPARTY_FIXES =>
"select q1.basebug,rpt2.rptno
from bugdb_rpthead_v rpt1,
     bugdb_rpthead_v rpt2,
     (select distinct basebug
      from (select accr.base_bug basebug, accr.codeline_request_id
            from   aru_cum_codeline_requests accr,
                   aru_cum_patch_releases acpr1,
                   aru_cum_patch_releases acpr,
                   aru_cum_patch_release_params acprp
                   where  (acpr.tracking_bug = :1 or
                   (acprp.parameter_type = 34593 and
                    to_number(acprp.parameter_value) = :1 and
                    acprp.release_id = acpr.release_id))
                    and    acpr.series_id = accr.series_id
                    and    accr.status_id in (34583, 34586, 34597,34588,96302,96371)
                    and    acpr1.release_id = accr.release_id
                    and    acpr1.tracking_bug is not null
                    order by accr.codeline_request_id asc)
                    ) q1
                    where q1.basebug = rpt1.rptno and
                    rpt1.base_rptno = rpt2.rptno and
                    rpt1.category = '3RDJARS' and
                    rpt2.product_id = 4647"
);

#select REGEXP_SUBSTR(acpr.release_name,'(Jan|Apr|Jul|Oct) \\d+'), acpr.tracking_bug

ARUDB::add_query(GET_OVERLAY_PATCH_FOR_DB12_2 =>
"select REGEXP_SUBSTR(acpr.release_name,'\\d+\$'), acpr.tracking_bug
  from aru_cum_patch_releases acpr, aru_bugfix_requests abr
  where REGEXP_LIKE(acpr.release_name, '^Database \\w+ \\d+ Release.* 12\\.2')
  and abr.bug_number = acpr.tracking_bug
  and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::patch_ftped_dev_qa . "," .
                        ARU::Const::ready_to_ftp_to_dev . ")
  and abr.platform_id = 226
");

ARUDB::add_query(GET_OVERLAY_PATCH_FOR_ABOVE_DB12_2 =>
"select REGEXP_SUBSTR(acpr.release_name,'\\d+\$'), acpr.tracking_bug
  from aru_cum_patch_releases acpr, aru_bugfix_requests abr
  where REGEXP_LIKE(acpr.release_name, '^Database Release Update.* '|| :1)
  and abr.bug_number = acpr.tracking_bug
  and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev . "," .
                        ARU::Const::ready_to_ftp_to_support . "," .
                        ARU::Const::patch_ftped_dev_qa . "," .
                        ARU::Const::ready_to_ftp_to_dev . ")
  and abr.platform_id = 226
");

ARUDB::add_query(GET_ARTIFACT_LOCAL_REPOSITORY =>
    "select value, development_value from aru_parameters where name='ARTIFACT_LOCAL_REPOSITORY'");

ARUDB::add_query(GET_LINUX_LABEL =>
 "select parameter_name from aru_cum_patch_release_params
   where release_id = :1
   and parameter_type = :2
   and parameter_name like :3 || '%'");

ARUDB::add_query(GET_BUG_PRODUCT_INFO =>
  "select product_id, category, sub_component
     from bugdb_rpthead_v
     where rptno = :1");

ARUDB::add_query(GET_RELEASE_NAME_USING_RELEASE_ID =>
"select release_name from
    aru_releases where
    release_id = :1");

ARUDB::add_query(GET_PRIOR_JENKINS_BUILD_IDS =>
"select irp.param_value
from   isd_requests ir, isd_request_parameters irp
where  ir.reference_id = :1
and    ir.request_id <> :2
and ir.request_id = irp.request_id
and irp.param_name = :3 ");

ARUDB::add_query(GET_CURRENT_JENKINS_BUILD_IDS =>
"select max(irp.param_value)
from   isd_requests ir, isd_request_parameters irp
where  ir.reference_id = :1
and    ir.request_id = :2
and ir.request_id = irp.request_id
and irp.param_name = :3 ");

ARUDB::add_query(GET_FIXED_BUGS_INFORMATION_BASED_ON_SERIES =>
"select tracking_bug
from aru_cum_patch_releases acpr,
     aru_cum_patch_series acps
where acps.series_name = :1
and   acpr.series_id = acps.series_id
and   acpr.status_id = 34524");

ARUDB::add_query(GET_FARM_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_farm_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" .
" and ald.a_uses_b = ao1.object_id
and ald.build_dependency != 'NO-SHIP'
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and not exists (select 1
                from aru_farm_dependencies ald_minus
                where ald_minus.a_uses_b        = ald.a_uses_b
                and   ald_minus.b_used_by_a     = ald.b_used_by_a
                and   ald_minus.label_dependency = '" .
                                ARU::Const::dependency_bmin . "'" .
"               and   ald_minus.label_id        = :4)
UNION
select ao2.object_name, ao2.object_location, ao2.object_id,
    ald.build_dependency
from aru_farm_dependencies ald, aru_filetypes af2, aru_objects ao2
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_bplus . "'" .
" and   ald.label_id        = :2
and ald.build_dependency != 'NO-SHIP'
and ald.a_uses_b = ao2.object_id
and af2.filetype_id = ao2.filetype_id
and af2.filetype_name = :3
order by 1");

ARUDB::add_query(GET_FARM_BASE_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_farm_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a     = :1
and   ald.label_dependency = '" . ARU::Const::dependency_base . "'" ."
and ald.a_uses_b = ao1.object_id
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and ald.label_id        = :2
and ald.build_dependency != 'NO-SHIP'");

ARUDB::add_query(GET_FARM_NONBASE_LABEL_DEP =>
"select ao1.object_name, ao1.object_location, ao1.object_id,
    ald.build_dependency
from aru_farm_dependencies ald, aru_filetypes af1, aru_objects ao1
where ald.b_used_by_a = :1
and   ald.label_dependency = '" . ARU::Const::dependency_bmin . "'" ."
and ald.a_uses_b = ao1.object_id
and af1.filetype_id = ao1.filetype_id
and af1.filetype_name = :3
and ald.label_id = :2
and ald.build_dependency != 'NO-SHIP'");

ARUDB::add_query(GET_CI_BUG =>
  "select rptno from bugdb_rpthead_v
   where base_rptno = :1
   and utility_version = :2");

ARUDB::add_query("GET_BASE_RELEASE_LABEL" =>
"select aprl.label_name
 from aru_product_release_labels aprl, aru_product_releases apr
 where aprl.product_release_id = apr.product_release_id
 and apr.product_id = 9480
 and apr.release_id = :1
 and aprl.platform_id = :2");

ARUDB::add_query(GET_PREV_STANDALONE_JDK_PATCHES=>
"select acpr.tracking_bug
  from aru_cum_patch_releases acpr, aru_bugfix_requests abr
  where REGEXP_LIKE(acpr.release_name, '^JDK Bundle Patch.* '|| :1)
  and abr.bug_number = acpr.tracking_bug
  and abr.platform_id = :2
  and abr.status_id  =".  ARU::Const::patch_ftped_support 
 );

ARUDB::add_query(GET_PREV_STANDALONE_JDK_PATCHES_18=>
"select acpr.tracking_bug
  from aru_cum_patch_releases acpr, aru_bugfix_requests abr
  where REGEXP_LIKE(acpr.release_name, '^JDK Bundle Patch.* '|| :1)
  and abr.bug_number = acpr.tracking_bug
  and abr.platform_id = :2
  and abr.status_id in (".ARU::Const::patch_ftped_support . "," .
                        ARU::Const::patch_ftped_dev .")"
 );

ARUDB::add_query(GET_HOST_ACTIVE_IT_REQS =>
"
select ir.request_id, irp.param_value, ir.status_code
  from isd_requests ir, isd_request_parameters irp
 where ir.request_type_code = " . ISD::Const::st_apf_install_type .
  "and ir.status_code = " . ISD::Const::st_apf_preproc .
  "and irp.request_id = ir.request_id
   and irp.param_name = 'current_worker_host'
   and irp.param_value like :1
   and ir.request_id <> :2
");

ARUDB::add_query(GET_CRS_BUGLIST_DESC =>
"
select brv.rptno, brv.subject from bugdb_rpthead_v brv
where brv.rptno in (
    select arbr.related_bug_number
    from aru_request_bug_relationship_v arbr, aru_bugfix_requests abr, aru_cum_patch_Releases acpr
    where acpr.release_version =  :1
    and acpr.tracking_bug = abr.bug_number
    and abr.platform_id = " . ARU::Const::platform_linux64_amd .
    " and abr.status_id in (" . ARU::Const::patch_ftped_support . ","
                             . ARU::Const::patch_ftped_dev . ","
                             . ARU::Const::patch_ftped_internal . ")" .
    " and arbr.bugfix_request_id = abr.bugfix_request_id)
");
ARUDB::add_query(GET_BACKPORT_TRANSACTION_ATTRIBUTES =>
"
select ata.attribute_value
   from aru_backport_transactions abt, aru_transactions at, aru_transaction_attributes ata
  where abt.backport_bug = :1
  and   at.transaction_name = abt.transaction_name
  and   ata.transaction_id = at.transaction_id
  and   ata.attribute_name in ('ORACLE BACKEND BRANCHED ELEMENTS','TRANS_STATE')
");

ARUDB::add_query(GET_BACKPORT_TRANSACTION_PREV_ASSIGN=>
"
select old_programmer
  from bugdb_rpthead_history_v
  where rptno = :1
  and old_status = 35
  and new_status = 11
  and rownum = 1
");

ARUDB::add_query(GET_SUPPORT_CONTACT_NAME =>
"select support_contact from bugdb_rpthead_v  where rptno = :1");

$initialized = 1;
}

1;
